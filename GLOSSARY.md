# 学习笔记 App

一个人的学习工具：记录笔记，把知识变成可复习的卡片，并用模拟场景（教学、提问、面试）检验掌握程度。运行在 macOS 与 iPhone 上。

## 内容

**Note**:
一篇学习记录，保存为一个 Markdown 文件，是数据的持久化单位，也是用户直接编辑的对象。
_Avoid_: 文档、文章、条目

**Card**:
可被复习的最小问答单位，包含一个问题和一个参考答案。物理上内嵌于 Note 文件，逻辑上属于全局卡片池，不隶属于某篇 Note。
_Avoid_: 题目、flashcard、条目

**Deck**:
为复习而临时划定的 Card 集合，由 Tag 过滤或手动挑选构成，与笔记的目录结构无关。
_Avoid_: 分类、牌组、文件夹

## 学习

**Review**:
对一张 Card 的一次作答与评分，是驱动排期的基本事件。
_Avoid_: 考试、练习

**Grade**:
一次 Review 的评分，决定该 Card 下次出现的时间。
_Avoid_: 分数、rating

## 场景

**Scenario**:
一种模拟练习的脚本与规则，例如老师教学、提问、面试。
_Avoid_: 模式、模板

**Session**:
一次连续进行的 Scenario 对话，是对话的真相载体。Session 的内容是文字 transcript，与经由何种 Channel 进行无关。
_Avoid_: 聊天、对话记录

**Channel**:
Session 的输入输出方式，目前有文字与语音两种。语音是 Channel 的变体，不改变 Session 本身。
_Avoid_: 模式、语音功能

## 存储

**Local-first**:
所有读写先落到本地文件，网络与云端只负责把本地副本同步出去，任何操作都不等待网络。
_Avoid_: 离线模式、缓存

**Review State**:
一张 Card 的排期与评分历史，按设备分片存储（`state/<device-id>.json`），读取时合并各分片取最新 Grade，以此避免多设备同写一个文件。
_Avoid_: 进度、数据库
