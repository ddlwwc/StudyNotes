# 问题跟踪器：GitHub

本仓库的 Issues 与产品规格存放在 GitHub Issues 中，所有操作统一使用 `gh` CLI。

## 约定

- 创建 Issue：使用 `gh issue create --title "..." --body "..."`；多行正文使用 heredoc。
- 读取 Issue：使用 `gh issue view <编号> --json number,title,body,labels,comments`。
- 列出 Issue：使用 `gh issue list --state open --json number,title,body,labels,comments`，并根据需要筛选标签与状态。
- 将 Issue 设为子 Issue：优先使用 `gh issue create --parent <父编号>`，或使用 `gh issue edit <父编号> --add-sub-issue <子编号>`。
- 表达阻塞关系：优先使用 GitHub 原生 issue dependencies，使用 `gh issue create --blocked-by <编号>` 或 `gh issue edit <子编号> --add-blocked-by <阻塞编号>`。
- 统计未关闭阻塞项：使用 GitHub issue dependencies summary；不要仅凭 `blockedBy` 中仍包含已关闭项来判断。
- 评论 Issue：使用 `gh issue comment <编号> --body "..."`。
- 添加或移除标签：使用 `gh issue edit <编号> --add-label "..."` 或 `--remove-label "..."`。
- 关闭 Issue：先使用 `gh issue comment <编号> --body "..."` 发布说明，再使用 `gh issue close <编号>`。
- 根据 `git remote -v` 推断目标仓库；在 clone 内运行时，`gh` 会自动处理。
- 只能向用户自己的仓库提交 Issue。第一次创建 Issue 前，使用 `gh repo view --json nameWithOwner` 核对目标仓库。

## Pull Request 作为 Triage 入口

**关闭。**

外部 Pull Request 不作为功能请求进入 triage 队列。

## 当 Skill 要求“发布到问题跟踪器”

创建一个 GitHub Issue。

## 当 Skill 要求“获取相关工单”

使用本文件约定的 `gh issue view` 读取。

## Wayfinding 操作

供 `/wayfinder` 使用。一个 Map 是单个 Issue，子 Issue 是其中的工单。

- **Map**：创建带 `wayfinder:map` 标签的 Issue，正文保存 Notes、当前决策和 Fog。
- **子工单**：作为 GitHub sub-issue 关联到 Map；无法使用 sub-issue 时，将子工单加入 Map 的 task list，并在子工单正文顶部写 `Part of #<map>`。
- **标签**：使用 `wayfinder:<type>`，类型为 `research`、`prototype`、`grilling` 或 `task`。
- **领取**：使用 `gh issue edit <编号> --add-assignee @me`。
- **完成**：发布结论评论，关闭 Issue，并把结论摘要与链接追加到 Map 的当前决策中。
