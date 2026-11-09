const { spawn } = require("node:child_process");
const { EventEmitter } = require("node:events");
const { createWriteStream } = require("node:fs");
const { access, mkdir } = require("node:fs/promises");
const net = require("node:net");
const path = require("node:path");

async function exists(filePath) {
  try {
    await access(filePath);
    return true;
  } catch {
    return false;
  }
}

function availablePort(preferred = 0) {
  return new Promise((resolve, reject) => {
    const server = net.createServer();

    server.once("error", (error) => {
      if (preferred && error.code === "EADDRINUSE") {
        availablePort().then(resolve, reject);
      } else {
        reject(error);
      }
    });
    server.listen(preferred, "127.0.0.1", () => {
      const port = server.address().port;
      server.close((error) => (error ? reject(error) : resolve(port)));
    });
  });
}

function probe(url) {
  return fetch(url, { signal: AbortSignal.timeout(2_500) })
    .then((response) => response.ok)
    .catch(() => false);
}

async function waitForUrl(url, isAlive) {
  const deadline = Date.now() + 120_000;

  while (Date.now() < deadline) {
    if (!isAlive()) {
      throw new Error(`A StudyNotes service exited before ${url} became ready.`);
    }
    if (await probe(url)) {
      return;
    }
    await new Promise((resolve) => setTimeout(resolve, 200));
  }

  throw new Error(`Timed out waiting for ${url}.`);
}

class RuntimeSupervisor extends EventEmitter {
  constructor(options) {
    super();
    this.options = options;
    this.children = new Set();
    this.stopping = false;
    this.state = { phase: "idle" };
  }

  childIsAlive(child) {
    return Boolean(child && child.exitCode === null && child.signalCode === null);
  }

  update(state) {
    this.state = { ...this.state, ...state };
    this.emit("status", this.state);
  }

  signal(child, signal) {
    if (!child?.pid) {
      return;
    }

    try {
      process.kill(-child.pid, signal);
    } catch {
      try {
        child.kill(signal);
      } catch {
        // The process already exited.
      }
    }
  }

  spawnOwned(command, args, options) {
    if (this.stopping) {
      throw new Error("StudyNotes runtime is stopping.");
    }

    const child = spawn(command, args, {
      ...options,
      detached: process.platform !== "win32",
      stdio: ["ignore", "pipe", "pipe"]
    });
    this.children.add(child);
    child.stdout?.pipe(this.log, { end: false });
    child.stderr?.pipe(this.log, { end: false });
    return child;
  }

  async resolveServices() {
    const appRoot = path.resolve(this.options.appRoot);

    if (this.options.packaged) {
      const resourcesPath = path.resolve(this.options.resourcesPath);
      const backend = path.join(resourcesPath, "backend", "studynotes-api");
      const web = path.join(resourcesPath, "web", "server.js");
      await Promise.all([access(backend), access(web)]);
      return {
        backend: { args: [], command: backend, cwd: this.dataDir },
        web: {
          args: [web],
          command: process.execPath,
          cwd: path.dirname(web),
          electronNode: true
        }
      };
    }

    const backendDir = path.join(appRoot, "backend");
    const python = path.join(backendDir, ".venv", "bin", "python");
    const next = path.join(appRoot, "node_modules", "next", "dist", "bin", "next");
    if (!(await exists(python))) {
      throw new Error("StudyNotes backend environment is missing. Run npm install.");
    }

    return {
      backend: {
        args: ["-m", "uvicorn", "main:app", "--host", "127.0.0.1"],
        command: python,
        cwd: backendDir
      },
      web: {
        args: [next, "dev", "--hostname", "127.0.0.1"],
        command: process.execPath,
        cwd: appRoot
      }
    };
  }

  async start() {
    if (this.state.phase === "ready") {
      return this.state;
    }

    this.stopping = false;
    this.dataDir = path.resolve(this.options.dataDir);
    const logsDir = path.join(this.dataDir, "logs");
    await mkdir(logsDir, { recursive: true });
    this.log = createWriteStream(path.join(logsDir, "runtime.log"), {
      flags: "a"
    });
    this.log.write(`\n--- StudyNotes runtime ${new Date().toISOString()} ---\n`);

    const services = await this.resolveServices();
    const backendPort = await availablePort(
      Number(process.env.STUDY_NOTES_BACKEND_PORT ?? 0)
    );
    const webPort = await availablePort(
      Number(process.env.STUDY_NOTES_WEB_PORT ?? 0)
    );
    const apiUrl = `http://127.0.0.1:${backendPort}`;
    const webUrl = `http://127.0.0.1:${webPort}`;
    const env = {
      ...process.env,
      STUDY_NOTES_API_URL: apiUrl,
      STUDY_NOTES_API_HOST: "127.0.0.1",
      STUDY_NOTES_BACKEND_PORT: String(backendPort),
      STUDY_NOTES_DATA_DIR: this.dataDir,
      NEXT_TELEMETRY_DISABLED: "1"
    };

    this.update({ phase: "starting", backendPort, apiUrl, webPort, webUrl });

    try {
      this.backend = this.spawnOwned(
        services.backend.command,
        [
          ...services.backend.args,
          "--port",
          String(backendPort)
        ],
        {
          cwd: services.backend.cwd,
          env
        }
      );
      await waitForUrl(
        `${apiUrl}/api/health`,
        () => this.childIsAlive(this.backend)
      );

      this.web = this.spawnOwned(
        services.web.command,
        [...services.web.args, "--port", String(webPort)],
        {
          cwd: services.web.cwd,
          env: {
            ...env,
            HOSTNAME: "127.0.0.1",
            PORT: String(webPort),
            ...(services.web.electronNode
              ? { ELECTRON_RUN_AS_NODE: "1" }
              : {})
          }
        }
      );
      await waitForUrl(webUrl, () => this.childIsAlive(this.web));
    } catch (error) {
      await this.stop();
      throw error;
    }

    this.update({ phase: "ready" });
    for (const child of [this.backend, this.web]) {
      child.once("exit", (code, signal) => {
        if (this.state.phase === "ready" && !this.stopping) {
          this.update({
            phase: "error",
            message: `StudyNotes service exited (${code ?? signal ?? "unknown"}).`
          });
          void this.stop({ preserveError: true });
        }
      });
    }
    return this.state;
  }

  async stop({ preserveError = false } = {}) {
    if (this.stopping) {
      return;
    }

    this.stopping = true;
    const children = [...this.children];
    for (const child of children) {
      this.signal(child, "SIGTERM");
    }

    const deadline = Date.now() + 5_000;
    while (Date.now() < deadline && children.some((child) => this.childIsAlive(child))) {
      await new Promise((resolve) => setTimeout(resolve, 100));
    }

    for (const child of children) {
      if (this.childIsAlive(child)) {
        this.signal(child, "SIGKILL");
      }
    }

    await Promise.all(
      children.map(
        (child) =>
          new Promise((resolve) => {
            if (!this.childIsAlive(child)) {
              resolve();
            } else {
              child.once("exit", resolve);
            }
          })
      )
    );

    this.children.clear();
    if (!preserveError) {
      this.update({ phase: "stopped" });
    }
    if (this.log) {
      await new Promise((resolve) => this.log.end(resolve));
    }
    this.log = null;
  }
}

module.exports = { RuntimeSupervisor, availablePort, probe, waitForUrl };
