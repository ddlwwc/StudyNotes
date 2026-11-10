const assert = require("node:assert/strict");
const { fork } = require("node:child_process");
const { mkdtemp, rm } = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");

const { RuntimeSupervisor } = require("../runtime.cjs");

async function probe(url) {
  try {
    const response = await fetch(url);
    return response.ok;
  } catch {
    return false;
  }
}

function waitForExit(child, timeout = 10_000) {
  if (child.exitCode !== null || child.signalCode !== null) {
    return Promise.resolve();
  }

  return new Promise((resolve, reject) => {
    const timer = setTimeout(
      () => reject(new Error("supervisor did not exit")),
      timeout
    );
    child.once("exit", () => {
      clearTimeout(timer);
      resolve();
    });
  });
}

test("runtime serves the same browser UI and API until the owner stops", async (t) => {
  const dataDir = await mkdtemp(path.join(os.tmpdir(), "studynotes-runtime-"));
  const runtime = new RuntimeSupervisor({
    appRoot: path.resolve(__dirname, "../.."),
    dataDir,
    packaged: false
  });

  t.after(async () => {
    await runtime.stop();
    await rm(dataDir, { recursive: true, force: true });
  });

  const state = await runtime.start();
  assert.equal(state.phase, "ready");

  const page = await fetch(state.webUrl);
  assert.equal(page.status, 200);
  assert.match(await page.text(), /StudyNotes/);

  const response = await fetch(`${state.webUrl}/api/workspace`);
  assert.equal(response.status, 200);
  const workspace = await response.json();
  assert.equal(workspace.workspace, null);
  assert.deepEqual(workspace.tree, []);

  const { apiUrl, webUrl } = state;
  assert.equal(await probe(`${apiUrl}/api/health`), true);
  assert.equal(await probe(webUrl), true);

  await runtime.stop();

  assert.equal(await probe(`${apiUrl}/api/health`), false);
  assert.equal(await probe(webUrl), false);
});

test("supervisor stops owned services when the Electron parent disappears", async (t) => {
  const dataDir = await mkdtemp(path.join(os.tmpdir(), "studynotes-supervisor-"));
  const supervisor = fork(path.join(__dirname, "..", "supervisor.cjs"), {
    cwd: path.resolve(__dirname, "../.."),
    env: {
      ...process.env,
      STUDY_NOTES_DATA_DIR: dataDir
    },
    stdio: ["ignore", "ignore", "pipe", "ipc"]
  });

  t.after(async () => {
    if (supervisor.exitCode === null) {
      supervisor.kill("SIGKILL");
    }
    await rm(dataDir, { recursive: true, force: true });
  });

  supervisor.send({
    type: "start",
    options: {
      appRoot: path.resolve(__dirname, "../.."),
      dataDir,
      packaged: false
    }
  });

  const ready = await new Promise((resolve, reject) => {
    const timeout = setTimeout(
      () => reject(new Error("supervisor did not become ready")),
      30_000
    );
    supervisor.once("error", reject);
    supervisor.once("exit", (code) => {
      clearTimeout(timeout);
      reject(new Error(`supervisor exited early with code ${code}`));
    });
    supervisor.on("message", (message) => {
      if (message.phase === "error") {
        clearTimeout(timeout);
        reject(new Error(message.message));
      }
      if (message.phase === "ready") {
        clearTimeout(timeout);
        resolve(message);
      }
    });
  });

  supervisor.disconnect();
  await waitForExit(supervisor);

  assert.equal(await probe(`${ready.apiUrl}/api/health`), false);
  assert.equal(await probe(ready.webUrl), false);
});
