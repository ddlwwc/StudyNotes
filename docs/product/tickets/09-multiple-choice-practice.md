## Parent

#1

## What to build

用户在 Learning session 中点击“考考我”，系统从当前资料和对话生成单选题 Practice item。用户完成作答后看到正确答案、解释和资料引用，结果被保存。

## Acceptance criteria

- [ ] 练习由用户显式触发，不在阅读或回答过程中自动弹出。
- [ ] 默认生成 3 道单选题，允许用户选择 1 至 10 道。
- [ ] 每道题包含题干、选项、正确答案、解释和 Source citation。
- [ ] 用户提交后可看到答案、解释与引用，并完成下一题。
- [ ] 作答结果按当前 workspace 和 Learning session 保存。
- [ ] 黑盒测试从会话生成题目、完成作答并验证结果。
