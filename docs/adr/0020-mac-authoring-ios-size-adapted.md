# Mac 是完整创作工作台，iOS 按尺寸提供等价操作

Status: partially superseded by ADR-0024; this release defers the iOS editor and its acceptance tests.

Mac 落地完整的多栏整理、自由栏宽和富文本编辑工作流；iOS 共享同一文件模型与编辑器内核，但 iPhone 使用 Tab 和下钻导航，以长按菜单及“移动到…”代替三栏拖放，iPad 在宽屏使用多栏布局。相比要求两端界面完全同构，这一选择保留了触屏平台的原生交互，并允许 Mac 先完成复杂整理能力；代价是两端仍需分别验证导航和编辑入口。
