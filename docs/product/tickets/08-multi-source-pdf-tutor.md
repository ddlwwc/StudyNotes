## Parent

#1

## What to build

扩展现有 Grounded tutor，让一个 Learning session 从当前选区开始，并允许用户固定其他 Markdown 页面、PDF 或片段。回答可以跨 Learning source 引用，并能跳回正确块或页码。

## Acceptance criteria

- [ ] 用户可在会话中固定其他 Markdown、PDF 或选中片段。
- [ ] 重复来源会被去重，超出上下文限制时显示取舍结果。
- [ ] Grounded answer 可同时引用 Markdown 块和 PDF 页码。
- [ ] 每条 Source citation 可打开正确文件并定位到对应位置。
- [ ] PDF 选区可直接发起 Learning session。
- [ ] 黑盒测试覆盖 Markdown 与 PDF 混合来源的回答和跳转。
