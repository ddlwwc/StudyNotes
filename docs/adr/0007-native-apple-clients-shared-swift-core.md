# Apple 客户端采用原生双端与共享 Swift 核心

Mac 和 iOS 分别使用 SwiftUI 开发原生应用，同时通过 Swift Package 共享领域模型、文件存储、标注协议、AI 客户端和通用界面组件。阅读器中的 PDF、Web 内容、文本选择和系统能力继续使用 PDFKit、WKWebView、AppKit 与 UIKit。相比 Flutter 或 React Native，这样可以避免为 iCloud、PDF 标注、PencilKit、Keychain 和系统分享维护高风险桥接层；代价是两端的页面组合和平台交互需要分别实现。
