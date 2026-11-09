# StudyNotes

本地优先、资料有据的个人 AI 私教。

## 产品文档

- [产品规格](docs/product/PRODUCT-SPEC.md)
- [MVP 功能拆解](docs/product/MVP-BREAKDOWN.md)
- [MVP 规格 Issue #1](https://github.com/ddlwwc/StudyNotes/issues/1)
- [MVP Tickets](docs/product/tickets/INDEX.md)
- [领域词汇表](GLOSSARY.md)
- [架构决策记录](docs/adr/0001-local-first-grounded-personal-tutor.md)
- [蓝白 UI 原型](prototype/product-ui/index.html)

## 本地开发

环境要求：

- Node.js 22.12 或更高版本
- Python 3.9 或更高版本
- macOS 上安装 Google Chrome，用于 Playwright 黑盒测试

首次安装依赖：

```bash
npm install
```

`postinstall` 会准备 Electron 开发运行时。如果官方下载源不可达，默认使用 npm 镜像站。

一条命令启动 Web UI 与本地后端：

```bash
npm run dev
```

打开终端输出的 Web 地址，输入一个本地目录路径作为 Notebook workspace。FastAPI 依赖会在首次启动时安装到 `backend/.venv`。

启动 Electron 开发壳：

```bash
npm run dev:desktop
```

Electron 与浏览器模式加载同一份 Web UI；Electron 退出时会同时停止本地 Web 与 API 服务。

## 验证

```bash
npm run test:e2e
npm run build
backend/.venv/bin/python -m compileall -q backend
```

应用数据默认保存在 `data/app.sqlite3`。测试通过 `STUDY_NOTES_DATA_DIR` 指向临时目录，不污染本地工作区。
