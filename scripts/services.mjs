import { spawn } from "node:child_process";
import { access } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const backendDir = path.join(root, "backend");
const venvPython = path.join(backendDir, ".venv", "bin", "python");
const uvicorn = path.join(backendDir, ".venv", "bin", "uvicorn");
const next = path.join(root, "node_modules", ".bin", "next");

async function exists(filePath) {
  try {
    await access(filePath);
    return true;
  } catch {
    return false;
  }
}

function run(command, args, options = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      ...options,
      stdio: "inherit"
    });

    child.once("error", reject);
    child.once("exit", (code) => {
      if (code === 0) {
        resolve();
      } else {
        reject(new Error(`${command} exited with code ${code ?? "unknown"}`));
      }
    });
  });
}

async function ensureBackend() {
  if (!(await exists(venvPython))) {
    console.log("Creating the StudyNotes backend environment...");
    await run("python3", ["-m", "venv", path.join(backendDir, ".venv")], {
      cwd: root
    });
  }

  if (!(await exists(uvicorn))) {
    console.log("Installing StudyNotes backend dependencies...");
    await run(
      venvPython,
      ["-m", "pip", "install", "-r", path.join(backendDir, "requirements.txt")],
      { cwd: root }
    );
  }
}

function spawnService(command, args, options) {
  return spawn(command, args, {
    ...options,
    detached: process.platform !== "win32",
    stdio: "inherit"
  });
}

function terminate(child) {
  if (!child || child.exitCode !== null) {
    return Promise.resolve();
  }

  const exited = new Promise((resolve) => child.once("exit", resolve));

  try {
    if (process.platform !== "win32" && child.pid) {
      process.kill(-child.pid, "SIGTERM");
    } else {
      child.kill("SIGTERM");
    }
  } catch {
    child.kill("SIGTERM");
  }

  const timeout = new Promise((resolve) =>
    setTimeout(() => {
      try {
        if (process.platform !== "win32" && child.pid) {
          process.kill(-child.pid, "SIGKILL");
        } else {
          child.kill("SIGKILL");
        }
      } catch {
        // The process already exited.
      }
      resolve();
    }, 3_000)
  );

  return Promise.race([exited, timeout]);
}

export async function startServices() {
  const backendPort = Number(process.env.STUDY_NOTES_BACKEND_PORT ?? 8765);
  const webPort = Number(process.env.STUDY_NOTES_WEB_PORT ?? 3000);
  const apiUrl = `http://127.0.0.1:${backendPort}`;
  const webUrl = `http://127.0.0.1:${webPort}`;

  await ensureBackend();

  const apiProcess = spawnService(
    uvicorn,
    ["main:app", "--host", "127.0.0.1", "--port", String(backendPort)],
    {
      cwd: backendDir,
      env: process.env
    }
  );
  const webProcess = spawnService(
    next,
    ["dev", "--hostname", "127.0.0.1", "--port", String(webPort)],
    {
      cwd: root,
      env: {
        ...process.env,
        STUDY_NOTES_API_URL: apiUrl
      }
    }
  );

  return {
    apiProcess,
    apiUrl,
    backendPort,
    webProcess,
    webPort,
    webUrl
  };
}

export async function stopServices(services) {
  await Promise.all([
    terminate(services.webProcess),
    terminate(services.apiProcess)
  ]);
}
