const { app, BrowserWindow, dialog, ipcMain } = require("electron");
const path = require("node:path");
const { pathToFileURL } = require("node:url");

let services = null;
let quitting = false;

async function waitForUrl(url) {
  const deadline = Date.now() + 60_000;

  while (Date.now() < deadline) {
    try {
      const response = await fetch(url);
      if (response.ok) {
        return;
      }
    } catch {
      // Services are still starting.
    }

    await new Promise((resolve) => setTimeout(resolve, 250));
  }

  throw new Error(`Timed out waiting for ${url}`);
}

async function createWindow() {
  const servicesModule = await import(
    pathToFileURL(path.join(__dirname, "..", "scripts", "services.mjs")).href
  );
  services = await servicesModule.startServices();

  await Promise.all([
    waitForUrl(`${services.apiUrl}/api/health`),
    waitForUrl(services.webUrl)
  ]);

  ipcMain.handle("choose-workspace-directory", async () => {
    const result = await dialog.showOpenDialog({
      title: "选择 Notebook workspace",
      properties: ["openDirectory", "createDirectory"]
    });
    return result.canceled ? null : result.filePaths[0];
  });

  const window = new BrowserWindow({
    width: 1280,
    height: 800,
    minWidth: 960,
    minHeight: 640,
    backgroundColor: "#f4f7fc",
    title: "StudyNotes",
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      preload: path.join(__dirname, "preload.cjs")
    }
  });

  await window.loadURL(services.webUrl);
}

app.whenReady().then(createWindow).catch((error) => {
  dialog.showErrorBox("StudyNotes 无法启动", error.stack ?? String(error));
  app.quit();
});

app.on("window-all-closed", () => {
  app.quit();
});

app.on("before-quit", (event) => {
  if (!services || quitting) {
    return;
  }

  event.preventDefault();
  quitting = true;
  const runningServices = services;
  services = null;

  import(pathToFileURL(path.join(__dirname, "..", "scripts", "services.mjs")).href)
    .then(({ stopServices }) => stopServices(runningServices))
    .finally(() => app.quit());
});
