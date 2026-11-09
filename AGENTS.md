# AGENTS.md

## 沟通语言

使用简体中文沟通。

## 执行策略

- 遇到敏感或高危命令时，先停止并询问用户。
- `approval_policy = "on-request"`
- `sandbox_mode = "workspace-write"`
- `reasoning_effort = "high"`

## Agent skills

### 问题跟踪器

本仓库使用 GitHub Issues 跟踪工作。详见 `docs/agents/issue-tracker.md`。

### Triage 标签

本仓库使用五个默认 triage 标签。详见 `docs/agents/triage-labels.md`。

### 领域文档

本仓库采用 single-context 领域文档布局。详见 `docs/agents/domain.md`。
