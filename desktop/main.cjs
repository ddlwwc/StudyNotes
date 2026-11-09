const {
  app,
  BrowserWindow,
  dialog,
  ipcMain,
  Menu,
  shell
} = require("electron");
const { fork } = require("node:child_process");
const { existsSync } = require("node:fs");
const path = require("node:path");

app.setName("StudyNotes");

const dataDir = path.resolve(
  process.env.STUDY_NOTES_DATA_DIR ?? app.getPath("userData")
);
const applicationRoot = app.isPackaged
  ? app.getAppPath()
  : path.resolve(__dirname, "..");
app.setPath("userData", dataDir);

let mainWindow = null;
let supervisor = null;
let runtime = null;
let quitting = false;
let exitAllowed = false;
let runtimeErrorShown = false;

function supervisorPath() {
  if (app.isPackaged) {
    const unpacked = path.join(
      process.resourcesPath,
      "app.asar.unpacked",
      "desktop",
      "supervisor.cjs"
    );
    if (existsSync(unpacked)) {
      return unpacked;
    }
  }

  return path.join(__dirname, "supervisor.cjs");
}

function openExternal(url) {
  if (/^https?:\/\//i.test(url)) {
    void shell.openExternal(url);
  }
}

function setApplicationMenu() {
  Menu.setApplicationMenu(
    Menu.buildFromTemplate([
      {
        label: "StudyNotes",
        submenu: [
          { role: "about", label: "关于 StudyNotes" },
          { type: "separator" },
          { role: "hide", label: "隐藏 StudyNotes" },
          { role: "hideOthers", label: "隐藏其他" },
          { role: "unhide", label: "全部显示" },
          { type: "separator" },
          { role: "quit", label: "退出 StudyNotes" }
        ]
      },
      {
        label: "编辑",
        submenu: [
          { role: "undo", label: "撤销" },
          { role: "redo", label: "重做" },
          { type: "separator" },
          { role: "cut", label: "剪切" },
          { role: "copy", label: "复制" },
          { role: "paste", label: "粘贴" },
          { role: "selectAll", label: "全选" }
        ]
      },
      {
        label: "视图",
        submenu: [
          { role: "reload", label: "重新载入" },
          { role: "togglefullscreen", label: "切换全屏" }
        ]
      },
      {
        label: "StudyNotes 本地服务",
        submenu: [
          {
            label: "在浏览器中打开",
            enabled: Boolean(runtime?.webUrl),
            click: () => runtime?.webUrl && openExternal(runtime.webUrl)
          },
          {
            label: "打开应用数据目录",
            click: () => void shell.openPath(dataDir)
          },
          {
            label: "打开运行日志",
            click: () => void shell.openPath(path.join(dataDir, "logs"))
          }
        ]
      },
      {
        role: "windowMenu",
        label: "窗口",
        submenu: [
          { role: "minimize", label: "最小化" },
          { role: "zoom", label: "缩放" },
          { type: "separator" },
          { role: "front", label: "前置全部窗口" }
        ]
      }
    ])
  );
}

function showRuntimeFailure(error) {
  if (runtimeErrorShown || quitting) {
    return;
  }
  runtimeErrorShown = true;
  console.error(error);
  dialog.showErrorBox(
    "StudyNotes 本地服务无法启动",
    error?.stack ?? String(error)
  );
  app.quit();
}

function stopSupervisor() {
  const child = supervisor;
  supervisor = null;
  if (!child || child.exitCode !== null) {
    return Promise.resolve();
  }

  return new Promise((resolve) => {
    const timer = setTimeout(() => {
      child.kill("SIGKILL");
      resolve();
    }, 12_000);

    child.once("exit", () => {
      clearTimeout(timer);
      resolve();
    });
    if (child.connected) {
      child.send({ type: "stop" });
    } else {
      child.kill("SIGTERM");
    }
  });
}

async function createWindow(webUrl) {
  const productOrigin = new URL(webUrl).origin;
  mainWindow = new BrowserWindow({
    width: 1280,
    height: 800,
    minWidth: 960,
    minHeight: 640,
    backgroundColor: "#f4f7fc",
    title: "StudyNotes",
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      preload: path.join(__dirname, "preload.cjs")
    }
  });

  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    openExternal(url);
    return { action: "deny" };
  });
  mainWindow.webContents.on("will-navigate", (event, url) => {
    if (new URL(url).origin !== productOrigin) {
      event.preventDefault();
      openExternal(url);
    }
  });
  mainWindow.webContents.on("render-process-gone", () => {
    showRuntimeFailure(new Error("StudyNotes 页面进程异常退出。"));
  });
  mainWindow.on("closed", () => {
    mainWindow = null;
  });

  await mainWindow.loadURL(webUrl);
}

async function startSupervisor() {
  supervisor = fork(supervisorPath(), [], {
    cwd: app.isPackaged ? process.resourcesPath : applicationRoot,
    execArgv: [],
    env: {
      ...process.env,
      ELECTRON_RUN_AS_NODE: "1",
      STUDY_NOTES_DATA_DIR: dataDir
    },
    stdio: ["ignore", "pipe", "pipe", "ipc"]
  });
  supervisor.stdout?.on("data", (chunk) => process.stdout.write(chunk));
  supervisor.stderr?.on("data", (chunk) => process.stderr.write(chunk));

  let ready = false;
  supervisor.on("message", (message) => {
    if (message.phase === "error") {
      console.error(message.message);
      showRuntimeFailure(new Error(message.message));
      return;
    }
    if (message.phase !== "ready" || ready) {
      return;
    }

    ready = true;
    runtime = message;
    setApplicationMenu();
    void createWindow(message.webUrl).catch(showRuntimeFailure);
  });
  supervisor.on("error", showRuntimeFailure);
  supervisor.on("exit", (code, signal) => {
    console.error(
      `StudyNotes supervisor exited (${code ?? signal ?? "unknown"}).`
    );
    runtime = null;
    setApplicationMenu();
    if (!quitting && !exitAllowed) {
      showRuntimeFailure(
        new Error(
          `StudyNotes 本地服务异常退出（${code ?? signal ?? "unknown"}）。`
        )
      );
    }
  });

  supervisor.send({
    type: "start",
    options: {
      appRoot: applicationRoot,
      dataDir,
      packaged: app.isPackaged,
      resourcesPath: process.resourcesPath
    }
  });
}

ipcMain.handle("choose-workspace-directory", async () => {
  const result = await dialog.showOpenDialog(mainWindow, {
    title: "选择 Notebook workspace",
    properties: ["openDirectory", "createDirectory"]
  });
  return result.canceled ? null : result.filePaths[0];
});

if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  app.on("second-instance", () => {
    mainWindow?.show();
    mainWindow?.focus();
  });

  app.on("window-all-closed", () => app.quit());
  app.on("before-quit", (event) => {
    if (exitAllowed) {
      return;
    }

    event.preventDefault();
    if (quitting) {
      return;
    }

    quitting = true;
    void stopSupervisor().finally(() => {
      exitAllowed = true;
      app.quit();
    });
  });

  app.whenReady().then(async () => {
    setApplicationMenu();
    await startSupervisor();
  }).catch(showRuntimeFailure);
}
