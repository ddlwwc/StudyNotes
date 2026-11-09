## Parent

#1

## What to build

启动完整的本地应用壳，选择并激活一个 Notebook workspace，从真实文件系统展示资料树，并打开一个 Markdown 文件进行只读阅读。该 slice 同时建立唯一的产品级黑盒测试 seam：通过浏览器 UI 操作运行中的应用，并在临时 workspace 中检查真实文件系统与本地数据。

## Acceptance criteria

- [ ] 用户可通过一条开发命令启动 Web UI 与本地后端。
- [ ] Electron 开发壳可加载同一 Web UI，并在退出时停止本地服务。
- [ ] 首次启动允许选择一个本地 Notebook workspace。
- [ ] 资料树直接映射目录与 Markdown 文件，重新打开应用后保留当前 workspace。
- [ ] 用户可打开 Markdown 并阅读渲染后的内容。
- [ ] 黑盒测试可在临时 workspace 中启动应用、选择目录并打开页面。

## Blocked by

None（can start immediately）。
