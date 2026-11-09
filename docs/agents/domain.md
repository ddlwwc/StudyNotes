# 领域文档

Engineering Skills 在探索代码库时，应按以下规则读取本仓库的领域文档。

## 探索前

- 读取仓库根目录的 `GLOSSARY.md`。
- 读取 `docs/adr/` 中与当前任务相关的 ADR。
- 如果这些文件不存在，则静默继续，不主动提示缺失。

## 文件结构

本仓库采用 single-context：

```text
/
├── GLOSSARY.md
├── docs/adr/
└── ...
```

## 使用 Glossary 词汇

- Issue 标题、重构方案、假设和测试名称必须使用 `GLOSSARY.md` 中的规范术语。
- 不要使用词汇表明确标记为避免的别名或近义词。
- 如果需要的新概念尚未出现在词汇表中，先判断是否真的需要；确定需要时交给 domain-modeling Skill 记录。

## ADR 冲突

如果输出与现有 ADR 冲突，必须明确指出，不能静默覆盖。
