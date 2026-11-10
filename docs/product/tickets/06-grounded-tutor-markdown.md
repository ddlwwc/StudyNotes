## Parent

#1

## What to build

用户在 Markdown 块或选区上发起 Learning session，并获得基于当前 Learning source 的流式辅导。回答必须显示有效 Source citation，资料不足时明确说明，模型补充需用户显式请求，所有发送内容可从上下文抽屉审计。

## Acceptance criteria

- [ ] 用户可配置 OpenAI-compatible Base URL、API Key 和聊天模型并完成连接测试。
- [ ] 每个 Learning session 至少绑定一个 Markdown 来源位置，不存在空白通用聊天。
- [ ] 用户可从块或选区提问，并看到流式回答、停止和重试状态。
- [ ] Grounded answer 的关键结论带可点击 Source citation 和原文片段。
- [ ] 无效引用会被重试或降级为证据不足。
- [ ] 资料不足时明确说明缺口；模型补充只在用户请求后出现且明显标记。
- [ ] 上下文抽屉展示选中资料、检索片段和实际发送范围。
- [ ] 默认采用引导式辅导，同时提供直接解释操作。
- [ ] 黑盒测试使用 mock 模型覆盖三种回答类型、取消和错误恢复。
