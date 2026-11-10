# StudyNotes MVP Tickets

父规格：[Issue #1](https://github.com/ddlwwc/StudyNotes/issues/1)

所有 tickets 挂为 Issue #1 的 GitHub sub-issues，并使用 GitHub 原生 blocking links。

| Ticket | 标题 | Blocked by | Status |
| --- | --- | --- | --- |
| [#2](https://github.com/ddlwwc/StudyNotes/issues/2) | Walking skeleton：打开本地 Notebook workspace | None | Closed |
| [#3](https://github.com/ddlwwc/StudyNotes/issues/3) | Notebook 页面生命周期与文件监听 | #2 | Closed |
| [#4](https://github.com/ddlwwc/StudyNotes/issues/4) | BlockNote 编辑与 Markdown sidecar 往返 | #3 | Closed |
| [#5](https://github.com/ddlwwc/StudyNotes/issues/5) | PDF 阅读与 Source citation 锚点 | #2 | Closed |
| [#6](https://github.com/ddlwwc/StudyNotes/issues/6) | 本地全文索引与 `Cmd+K` 搜索 | #3、#4、#5 | Closed |
| [#7](https://github.com/ddlwwc/StudyNotes/issues/7) | Markdown 选区上的 Grounded tutor | #4、#6 | Closed |
| [#8](https://github.com/ddlwwc/StudyNotes/issues/8) | 七牛图片插入与上传 | #4 | Closed |
| [#9](https://github.com/ddlwwc/StudyNotes/issues/9) | 多来源与 PDF 的 Grounded tutoring | #5、#7 | Closed |
| [#10](https://github.com/ddlwwc/StudyNotes/issues/10) | 单选题 Practice item | #7 | Closed |
| [#11](https://github.com/ddlwwc/StudyNotes/issues/11) | 短答题反馈与自评修正 | #10 | Closed |
| [#12](https://github.com/ddlwwc/StudyNotes/issues/12) | Gap record 与 Review 闭环 | #11 | Closed |
| [#13](https://github.com/ddlwwc/StudyNotes/issues/13) | 可选向量检索与全文降级 | #6、#7 | Closed |
| [#14](https://github.com/ddlwwc/StudyNotes/issues/14) | 学习数据备份与恢复 | #8、#9、#12、#13 | Closed |
| [#15](https://github.com/ddlwwc/StudyNotes/issues/15) | macOS Electron 可安装应用 | #2 | Closed |
| [#16](https://github.com/ddlwwc/StudyNotes/issues/16) | MVP 端到端工程验收 | #9、#12、#13、#14、#15 | Open: ready-for-human |

## Frontier

Agent 可执行 tickets 已全部关闭。当前仅剩 **#16** 的人工验收项：

- 5 位目标用户完成至少 15 次学习闭环。
- 至少 60% 的 Practice item 被评为有助于理解。
- 真实模型、Embedding、七牛服务与 macOS 签名/公证完成发布验证。
