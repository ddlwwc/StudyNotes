# Mac 语雀式编辑器验收记录

| 项目 | 内容 |
| --- | --- |
| 日期 | 2026-11-05 |
| 范围 | #64 与 #65-#74 的 Mac 自动化实现 |
| 不包含 | iOS 编辑器、账号、协作、评论、分享、收藏、在线 AI、持久版本 |

## 自动化证据

| 验收项 | 证据 |
| --- | --- |
| ED-M01 / ED-M02 | `EditorMarkdownSessionTests` 覆盖新文档解锁、锁定、编辑/标注仲裁和锁定前保存 |
| ED-M03 | `EditorRuntimeTests` 在真实 WKWebView 中加载同一份编辑器运行时 |
| ED-M04 | `EditorMarkdownRichTextTests` 校验完整工具栏、斜杠菜单和块菜单命令族 |
| ED-M05 | 斜杠菜单生成代码、公式、Mermaid、数据表和图形块；`MarkdownEditorSessionTests` 覆盖块插入、更新、删除 |
| ED-M06 | `DataTableFormulaEngine`、`GraphScene` 和固定旁路块语料覆盖结构化往返 |
| ED-M07 | `EditorMarkdownFallbackTests` 覆盖复杂块可读降级 |
| ED-M08 | `StudyNotesStoreDocumentTransactionTests` 覆盖缺失、未知版本和不可序列化块定位 |
| ED-M09 | 自动保存 debounce 为 300ms；事务恢复由 `StudyNotesStoreDocumentTransactionTests` 覆盖 |
| ED-M10 | 派生重建失败保留已提交正文并记录重试状态 |
| ED-M11 | 编辑保存使用完整内容指纹；既有冲突副本逻辑与外部修改测试保留 |
| ED-M12 | 图片、附件、音频和视频使用 `media://qiniu/`；媒体队列、缓存、去重和清理测试保留 |
| ED-M13 | `ClipboardHTMLSanitizerTests` 和 Web runtime paste 白名单覆盖脚本、事件处理器和危险 URL |
| ED-M14 | `AdvancedBlockToolsTests` 覆盖画板、思维导图、流程图节点、连线、拖动、缩放和撤销 |
| ED-M15 | 数据表字段、记录、筛选、排序、公式、循环依赖和错误定位有行为测试 |
| ED-M16 | WKWebView 运行测试覆盖 760pt 窄窗口、控件名称、深浅主题和减少动态效果 CSS |
| ED-M17 | `contracts/editor-capabilities.json` 固定 75 项能力，语料与测试路径可重复运行 |

## 命令

```bash
cd apple/Packages/StudyNotesKit
swift test --disable-sandbox \
  --scratch-path /private/tmp/StudyNotesKit-final-build

cd ../../Apps/StudyNotesMac
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/StudyNotesMac-module-cache \
CLANG_MODULE_CACHE_PATH=/private/tmp/StudyNotesMac-clang-cache \
swift test --disable-sandbox \
  --scratch-path /private/tmp/StudyNotesMac-final-build

./script/build_and_run.sh --verify
```

最近一次结果：

- StudyNotesKit：156 个 Swift Testing 测试、2 个 XCTest，全部通过。
- StudyNotesMac：29 个测试全部通过。
- 打包 `.app` 启动成功，未在最近五分钟产生 `StudyNotesMac-*.ips`。
- KaTeX、Mermaid 与编辑器资源均随 SwiftPM resource bundle 打入 `.app`。

## 仍需人工或跨机器验收

- VoiceOver、中文输入法组合、高对比度和真实机械键盘路径需要人工在 Mac 上复核。
- Intel Mac 性能基线需要在 Intel 机器上重复运行；当前自动基线只证明 Apple Silicon 开发机无截断。
- 数据表关联、汇总和跨文档错误状态已保留数据模型，但没有端到端 UI 自动化。
- 画板的自由绘制、图片导入和自动布局是当前轻量实现的后续增强项。
- 真实 Word/Excel 剪贴板内容和七牛生产网络链路未在本机自动化环境中执行。
