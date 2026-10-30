# 学习笔记 App

一个人的学习工具：记录笔记，把知识变成可复习的卡片，并用模拟场景（教学、提问、面试）检验掌握程度。运行在 macOS 与 iPhone 上。

## 技术选型

- **Swift + SwiftUI**，一个 Xcode 工程带 macOS / iOS 两个 app target
- **StudyCore**：纯领域层，不 import UI 框架，两端共享，可直接单元测试
- **Markdown 文件即真相**，存于 iCloud Drive 中的用户目录，通过文件夹安全作用域书签访问（见 [ADR-0002](docs/adr/0002-folder-bookmark-instead-of-icloud-container.md)）
- **FSRS** 排期算法
- 语音：本地 Speech 转写 + 本地朗读，语音只是 Channel，不改变 Session 的领域模型
- AI：DeepSeek 开放平台 API（OpenAI 兼容格式）

## 当前状态

macOS 与 iOS 两个 target 均编译通过；领域层 32 个单元测试全绿。已经可以运行。

## 打开方式

```bash
open StudyNotes.xcodeproj
```

选 `StudyNotes-macOS` 或 `StudyNotes-iOS` scheme 运行。首次启动会让你选一个文件夹作为笔记目录——**选 iCloud Drive 下的某个文件夹**，Mac 与 iPhone 就自动同步。

## 目录

```
StudyNotes.xcodeproj        Xcode 工程（macOS / iOS 双 target + StudyCore framework）
Sources/StudyCore/          领域层（framework target）
  Note.swift                Note / Card
  MarkdownCardParser.swift  Markdown 解析（front-matter、卡片围栏块）
  FSRS.swift                排期算法
  ReviewState.swift         复习状态与多设备分片合并
  Deck.swift                复习集合
  Session.swift             Session / Turn / Channel
  Scenario.swift            内置场景（老师 / 提问 / 面试）
  Grade.swift               评分
  FileIO.swift              目录布局、原子读写、文件枚举
  JSONCoding.swift          状态分片的编解码约定
  ModelOutput.swift         从模型输出里提取 JSON
  Ports.swift               外部能力协议
App/Shared/                 两端共享的 app 代码
  AppModel.swift            应用级容器
  Vault/                    安全作用域书签、Vault 打开与关闭、Note 索引
  Review/                   复习状态持久化
  AI/                       DeepSeek 客户端、设置、钥匙串
  Voice/                    语音转写与朗读
  Scenario/                 场景运行时与记录存储
  Views/                    全部 SwiftUI 视图
App/macOS/                  macOS 入口
App/iOS/                    iOS 入口
Tests/StudyCoreTests/       领域层单元测试
docs/adr/                   架构决策记录
GLOSSARY.md                 领域术语表
```

## 笔记目录结构

选定根目录后 app 会建三个子目录：

```
<你选的目录>/
  notes/       笔记，一篇一个 .md
  state/       复习状态，按设备分片（<device-id>.json）
  sessions/    场景对话记录，一次会话一个 .md
```

复习状态之所以按设备分片，是为了避免两台设备同时写同一个文件互相覆盖；读取时合并各分片取最新 grade。

## 卡片写法

在笔记里用 `card` 围栏块，答案支持多行与代码：

````markdown
```card
id: c1
q: ArrayList 和 LinkedList 的区别？
a: 底层结构不同。
随机访问 ArrayList 是 O(1)，LinkedList 是 O(n)。
```
````

`id` 可省略，省略时按问题文本生成稳定哈希。**注意**：省略 id 时改一个字就变成新卡，复习进度会归零，所以重要的卡片建议显式写 `id`。

## 配置 API Key

在「设置」里填 DeepSeek 的 API Key。它存在系统钥匙串里，不写进笔记目录。

## 开发

在普通终端里直接构建：

```bash
swift build
swift test
xcodebuild -project StudyNotes.xcodeproj -scheme StudyNotes-macOS build
```

**在 DSH 沙盒里**（文件策略为 workspace-write）需要额外参数，原因见 [ADR-0004](docs/adr/0004-build-requirements-under-sandbox.md)：

```bash
export CLANG_MODULE_CACHE_PATH="$PWD/.cache/clang"
mkdir -p "$CLANG_MODULE_CACHE_PATH"

# 领域层
swift build --disable-sandbox
swift test  --disable-sandbox

# app target（需把 DerivedData 与宏沙盒都处理掉）
xcodebuild -project StudyNotes.xcodeproj -scheme StudyNotes-macOS \
  -derivedDataPath "$PWD/.dd" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  OTHER_SWIFT_FLAGS="-Xfrontend -disable-sandbox" \
  build
```

`OTHER_SWIFT_FLAGS="-Xfrontend -disable-sandbox"` 是必需的：Swift 宏（`@Observable`、`@State`）通过 `swift-plugin-server` 执行，它自己会再套一层沙盒，在受限环境里会失败并报 `external macro implementation type ... could not be found`。

这些参数只在本机受限环境需要，不要带进 CI 或提交到项目配置。
