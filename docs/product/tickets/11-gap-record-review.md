## Parent

#1

## What to build

把未掌握内容转化为显式 Gap record，并进入 Review 流程。用户在 Review 页面完成到期项，选择“重来”或“通过”，系统按 1、3、7、14 天更新下一次复习时间。

## Acceptance criteria

- [ ] 用户可从 Practice item 或 Learning session 创建 Gap record。
- [ ] Gap record 保存标题、来源引用、关联记录和下次复习时间。
- [ ] Review 页面按到期顺序展示，单批最多 20 项。
- [ ] 用户完成复习后可选择“重来”或“通过”。
- [ ] “重来”重置为 1 天；“通过”按 1、3、7、14 天推进。
- [ ] 用户可手动修改或清除下一次复习日期。
- [ ] 删除会话不删除 Gap record、Practice item 或 Review item。
- [ ] 黑盒测试完成“练习失败 → Gap → Review → 新日期”的闭环。
