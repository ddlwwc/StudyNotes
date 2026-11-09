# Web-first 界面与 Electron 桌面壳

首版使用一套 Web UI 和本地后端，Electron 只负责桌面启动、运行时监管、窗口与更新，不复制业务界面。这样可在 macOS、Windows、Linux 与浏览器间复用同一产品能力，代价是桌面安装包更大，并需要维护本地服务的生命周期。
