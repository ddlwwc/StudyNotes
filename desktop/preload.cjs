const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("studyNotes", {
  chooseWorkspaceDirectory: () =>
    ipcRenderer.invoke("choose-workspace-directory")
});
