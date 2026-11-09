# 个人资料型 AI 私教

这个 context 描述一种以用户自有资料为可信依据、帮助个人完成学习闭环的 AI 辅导产品。

## Language

**Learning source（学习资料）**:
用户明确交给产品、可作为 AI 辅导与练习依据的 Markdown、PDF、课程材料或笔记。
_Avoid_: 聊天附件、模型知识

**Grounded tutor（资料型 AI 私教）**:
以 Learning source 为主要可信依据，并明确区分资料内容与模型补充的 AI 辅导者。
_Avoid_: 通用聊天机器人、搜索引擎

**Learning session（学习会话）**:
围绕一个或多个 Learning source 进行阅读、辅导与练习，并持续保存上下文和学习证据的一次学习过程。
_Avoid_: 聊天记录、普通对话

**Practice item（练习项）**:
从 Learning source 或已暴露的知识缺口生成，要求学习者主动作答并由产品记录结果的练习。
_Avoid_: 题目消息、聊天问答

**Review item（复习项）**:
由未掌握或待巩固的 Practice item 形成、带有下一次复习安排的长期学习记录。
_Avoid_: 错题消息、待办任务

**Source citation（资料引用）**:
从 AI 回答或练习反馈指向具体 Learning source 位置与原文片段的可验证链接。
_Avoid_: 参考资料列表、来源标签

**Learning notebook（学习笔记本）**:
由多个 Markdown 页面组成、可由用户直接编辑并作为 Learning source 使用的学习空间，支持标签、模板和每日笔记。
_Avoid_: 收藏夹、阅读记录、聊天历史

**Notebook workspace（笔记本工作区）**:
用户关联到产品的一个本地目录，拥有独立的资料树、索引和学习上下文；同一时间只有一个工作区处于激活状态。
_Avoid_: 文件夹标签、全局资料库

**Grounded answer（有据回答）**:
关键结论由 Source citation 支持的 AI 回答；资料不足时必须明确说明，不能伪装成资料结论。
_Avoid_: 通用回答、模型猜测

**Unsupported supplement（非资料补充）**:
仅在用户明确要求后提供的模型知识，必须与 Grounded answer 视觉区分并标明不来自 Learning source。
_Avoid_: 混合回答、未标注补充

**Gap record（知识缺口）**:
由一次 Learning session 或 Practice item 明确产生的待巩固问题，关联来源证据与下一次复习时间。
_Avoid_: 记忆、自动知识点、错题消息
