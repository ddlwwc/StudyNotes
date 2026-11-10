# Markdown 为主数据，BlockNote 元数据放 sidecar

学习笔记本以普通 `.md` 文件承载全部可读内容，并在同目录使用 `.md.note.json` 保存 BlockNote 块 ID、自定义块属性和布局等无法由 Markdown 自洽表达的元数据。外部修改 Markdown 后必须重新解析，存在未保存编辑时进入冲突处理，不允许 sidecar 静默覆盖用户文件。
