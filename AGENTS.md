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

<!-- BEGIN:nextjs-agent-rules -->

## This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` (resolved from this file's directory; in monorepos the `next` package may not be visible from the repo root) before writing any code. Heed deprecation notices.

This block is written and re-added by `next dev` — verify at `node_modules/next/dist/server/lib/generate-agent-files.js`. Removing it from a diff only re-creates the uncommitted change; committing it with your work keeps the tree clean.

<!-- END:nextjs-agent-rules -->
