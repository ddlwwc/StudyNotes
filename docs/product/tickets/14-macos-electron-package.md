## Parent

#1

## What to build

把同一 Web UI 与本地后端打包为可双击启动的 macOS Electron 应用。Electron 负责启动、就绪、关闭、崩溃恢复和本地数据路径，不复制业务界面；浏览器访问仍保留。

## Acceptance criteria

- [ ] 非开发环境可通过安装包启动应用。
- [ ] Electron 启动本地后端与 Web UI，并在就绪后显示同一业务界面。
- [ ] 关闭应用会停止由其启动的本地服务。
- [ ] 异常退出后再次启动可恢复本地服务与当前 workspace。
- [ ] 应用数据写入稳定的 macOS 应用数据目录。
- [ ] 同一业务 UI 仍可通过本地浏览器访问。
- [ ] 黑盒 smoke test 从干净数据目录启动、检查就绪并验证关闭。
