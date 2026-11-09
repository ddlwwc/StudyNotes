import assert from "node:assert/strict";
import { once } from "node:events";
import { access, mkdir, mkdtemp, readdir, rm, writeFile } from "node:fs/promises";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import { _electron as electron, chromium } from "playwright";

const root = path.resolve(import.meta.dirname, "..");

async function exists(filePath) {
  try {
    await access(filePath);
    return true;
  } catch {
    return false;
  }
}

async function findPackagedApp() {
  const explicit = process.env.STUDY_NOTES_PACKAGED_APP;
  if (explicit) {
    return path.resolve(explicit);
  }

  const dist = path.join(root, "dist");
  for (const entry of await readdir(dist, { withFileTypes: true }).catch(() => [])) {
    if (!entry.isDirectory() || !entry.name.startsWith("mac")) {
      continue;
    }
    const candidate = path.join(dist, entry.name, "StudyNotes.app");
    if (await exists(candidate)) {
      return candidate;
    }
  }

  throw new Error("StudyNotes.app was not found. Run npm run package:mac first.");
}

function reservePort() {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const port = server.address().port;
      server.close((error) => (error ? reject(error) : resolve(port)));
    });
  });
}

async function probe(url) {
  try {
    const response = await fetch(url, { signal: AbortSignal.timeout(2_500) });
    return response.ok;
  } catch {
    return false;
  }
}

async function waitForUrl(url, timeout = 90_000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    if (await probe(url)) {
      return;
    }
    await new Promise((resolve) => setTimeout(resolve, 200));
  }
  throw new Error(`Timed out waiting for ${url}`);
}

async function waitForStopped(url, timeout = 15_000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    if (!(await probe(url))) {
      return;
    }
    await new Promise((resolve) => setTimeout(resolve, 200));
  }
  throw new Error(`${url} was still reachable after shutdown.`);
}

async function waitForExit(child, timeout = 15_000) {
  if (child.exitCode !== null || child.signalCode !== null) {
    return;
  }
  await Promise.race([
    once(child, "exit"),
    new Promise((_, reject) =>
      setTimeout(() => reject(new Error("Electron process did not exit.")), timeout)
    )
  ]);
}

const appBundle = await findPackagedApp();
const executable = path.join(
  appBundle,
  "Contents",
  "MacOS",
  path.basename(appBundle, ".app")
);
assert.equal(await exists(executable), true, `Missing packaged executable: ${executable}`);

const dataDir = await mkdtemp(path.join(os.tmpdir(), "StudyNotes 干净数据 "));
const workspaceDir = await mkdtemp(path.join(os.tmpdir(), "StudyNotes 工作区 "));
const backendPort = await reservePort();
const webPort = await reservePort();
const apiUrl = `http://127.0.0.1:${backendPort}`;
const webUrl = `http://127.0.0.1:${webPort}`;
const env = {
  ...process.env,
  STUDY_NOTES_BACKEND_PORT: String(backendPort),
  STUDY_NOTES_DATA_DIR: dataDir,
  STUDY_NOTES_WEB_PORT: String(webPort)
};

await mkdir(path.join(workspaceDir, "课程"), { recursive: true });
await writeFile(
  path.join(workspaceDir, "课程", "桌面壳.md"),
  "# 桌面壳\n\n打包后的应用仍使用同一业务界面。\n",
  "utf8"
);

let firstApp;
let secondApp;
let browser;
try {
  firstApp = await electron.launch({
    executablePath: executable,
    env
  });
  const firstWindow = await firstApp.firstWindow();
  await firstWindow
    .getByRole("heading", { name: "打开你的学习空间" })
    .waitFor({ timeout: 60_000 });

  await waitForUrl(`${apiUrl}/api/health`);
  await waitForUrl(webUrl);

  await firstWindow
    .getByLabel("Notebook workspace 路径")
    .fill(workspaceDir);
  await firstWindow.getByRole("button", { name: "打开工作区" }).click();
  await firstWindow
    .getByRole("button", { name: "桌面壳.md", exact: true })
    .waitFor();

  browser = await chromium.launch({ channel: "chrome", headless: true });
  const browserPage = await browser.newPage({ viewport: { width: 1280, height: 800 } });
  await browserPage.goto(webUrl);
  await browserPage
    .getByRole("button", { name: "桌面壳.md", exact: true })
    .waitFor();

  const electronProcess = firstApp.process();
  electronProcess.kill("SIGKILL");
  firstApp = null;
  await waitForExit(electronProcess);
  await waitForStopped(apiUrl);
  await waitForStopped(webUrl);

  secondApp = await electron.launch({ executablePath: executable, env });
  const secondWindow = await secondApp.firstWindow();
  await secondWindow
    .getByRole("button", { name: "桌面壳.md", exact: true })
    .waitFor({ timeout: 60_000 });

  await secondApp.close();
  secondApp = null;
  await waitForStopped(apiUrl);
  await waitForStopped(webUrl);

  console.log(
    "PASS: packaged app starts cleanly, serves the shared UI in browser, recovers after forced exit, and releases both services."
  );
} finally {
  await browser?.close();
  await firstApp?.close().catch(() => {});
  await secondApp?.close().catch(() => {});
  await rm(dataDir, { recursive: true, force: true });
  await rm(workspaceDir, { recursive: true, force: true });
}
