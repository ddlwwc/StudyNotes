## Parent

#1

## What to build

在现有本地全文检索上增加可选 embedding 与向量索引。用户配置后获得语义检索；未配置、关闭或失败时自动使用全文检索，两种路径返回一致的 Source citation。

## Acceptance criteria

- [ ] 模型设置中可配置、测试和关闭 embedding。
- [ ] 向量索引保存在本地 workspace 作用域内。
- [ ] 开启语义检索后，AI 上下文可以命中含义相关但措辞不同的片段。
- [ ] embedding 未配置、失败或被关闭时自动回退全文检索。
- [ ] 检索模式变化在界面中可见，不显示假进度。
- [ ] 两种检索路径产生一致的 Source citation 契约。
- [ ] 黑盒测试比较语义命中与全文降级结果。
