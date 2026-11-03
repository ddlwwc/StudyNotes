# Figma 本地快照

不再通过 Figma MCP 反复读取同一个设计文件。仓库内提供两种本地读取方式：

1. `figma-plugins/local-export`：在 Figma 桌面端运行一次，下载结构与视觉资源。
2. `scripts/figma-snapshot.mjs`：直接查询下载的 ZIP 或 JSON，不需要网络和 MCP。

## 导出

1. 在 Figma 网页端或桌面端打开 `Study Notes — Mac & iPhone Concepts`。
2. 菜单选择 **Plugins → Development → Import plugin from manifest…**。
3. 选择仓库中的 `figma-plugins/local-export/manifest.json`。
4. 运行 **StudyNotes Local Snapshot**，点击 **扫描当前文件**。
5. 点击 **下载完整 ZIP**，保存到 `figma-data/`。

建议文件名：

```text
figma-data/studynotes.figma-snapshot.zip
```

ZIP 内容：

- `snapshot.json`：页面、节点、文字、样式、变量、原型交互和资源索引。
- `screenshots/`：每个可见顶层画板的 PNG。
- `images/`：节点图片填充引用的原始图片。

`figma-data/` 已加入 `.gitignore`。快照可能很大，默认不提交。

## 查询

```bash
node scripts/figma-snapshot.mjs figma-data/studynotes.figma-snapshot.zip summary
node scripts/figma-snapshot.mjs figma-data/studynotes.figma-snapshot.zip pages
node scripts/figma-snapshot.mjs figma-data/studynotes.figma-snapshot.zip screens
node scripts/figma-snapshot.mjs figma-data/studynotes.figma-snapshot.zip interactions
node scripts/figma-snapshot.mjs figma-data/studynotes.figma-snapshot.zip text "发布"
node scripts/figma-snapshot.mjs figma-data/studynotes.figma-snapshot.zip find "批量导入"
node scripts/figma-snapshot.mjs figma-data/studynotes.figma-snapshot.zip node 4:63
```

查询脚本直接读取 ZIP 中的 `snapshot.json`，不需要先解压。

## 结构约定

```text
snapshot.json
├── source           Figma 文件标识与导出时间
├── stats           页面、节点、画板与交互统计
├── pages           页面和嵌套节点树
├── prototype       原型交互摘要
├── styles          Paint / Text / Effect / Grid 样式
├── variables       本地变量集合与变量值
└── assets          截图和原图路径索引
```

节点字段只包含本地原型分析和实现需要的数据，但不试图复制 Figma 的全部内部格式。需要像素级视觉时读取 `screenshots/`；需要重建结构时读取 `snapshot.json`。
