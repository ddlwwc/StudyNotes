# Swift + SwiftUI，单工程双 target，领域层独立成 Swift Package

选中 Swift + SwiftUI，因为目标只有 macOS 与 iPhone，两端共享同一套 UI 框架、Foundation 与系统能力（语音转写、朗读、iCloud 访问都可以直接用系统 API）。工程结构是一个 Xcode 工程带 macOS 与 iOS 两个 app target，另有一个本地 Swift Package `StudyCore` 承载领域层——Note、Card、Review、Grade、Deck、排期算法与 Markdown 解析。领域层不 import 任何 UI 框架，因此可以被单元测试直接驱动，也被两端共享。

## Considered Options

- **`#if os(macOS)` 条件编译塞满 app target**：代码会迅速难以阅读，且领域逻辑无法独立测试。
- **拆成多个 Swift Package（Core / Storage / AI / UI）**：对这个体量属于过度分层。
- **Flutter / React Native / Kotlin Multiplatform**：目标只有 Apple 两端，跨平台方案的代价（UI 手感、系统集成能力）换不到收益。

## Consequences

语音、AI 调用、文件访问这些平台相关能力留在 app target，通过 protocol 注入到领域层，以便替换实现而不改动 `StudyCore`。
