# 富文本编辑器只改变编辑体验，不改变 Markdown 真相

Status: partially superseded by ADR-0024 for the Mac editor and versioned block sidecars.

笔记和文字阅读副本改用阅读区内嵌的所见即所得编辑器，但持久化真相仍是用户可读的 Markdown 源文件，派生 `rendered.html` 继续用于阅读、标注和发布。编辑器内部可以使用临时文档树处理块级操作，但必须在保存时稳定序列化为 Markdown，不把编辑器私有 JSON 作为主数据；相比引入新的主文档格式，这保留了 iCloud 文件可迁移和跨工具可检查性，代价是编辑器只能开放能够无损往返的能力。本决定取代 ADR-0004 中“富文本编辑器不进入当前版本”的限制，以及 ADR-0011 中“不提供可视化编辑器”的限制。
