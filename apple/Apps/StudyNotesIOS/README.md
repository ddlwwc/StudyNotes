# StudyNotes iOS

SwiftUI iOS 17+ 客户端，覆盖资料库、按需下载与离线保存、收件箱、搜索、轻量标注和 AI 研读。

## 构建

可安装的 App 与 Share Extension：

```bash
xcodebuild \
  -project StudyNotesIOS.xcodeproj \
  -scheme StudyNotesIOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

领域测试：

```bash
swift test
```

`Package.swift` 也提供 `StudyNotesIOS` SwiftPM executable 和可复用的
`StudyNotesIOSCore` 库。模拟器安装与 Share Extension 验证使用 Xcode 工程。

## 外部能力配置

真机签名前需要在 Apple Developer 中创建并配置：

- iCloud 容器 `iCloud.com.studynotes.app`
- App Group `group.com.studynotes.app`
- App 与 Share Extension 的 provisioning profiles

这些标识位于 `Support/*.entitlements`、`Package.swift` 和
`Sources/StudyNotesIOSCore/FileSupport.swift`。

## 本地验证数据

`Fixtures/DemoWorkspace` 可用于模拟器本地演示。以
`STUDYNOTES_FORCE_LOCAL=1` 启动时，客户端不会访问 iCloud 容器。

## 边界

- iOS 不包含发布入口。
- AI 请求由客户端直接发往用户配置的 OpenAI 兼容供应商。
- API Key 只写入 Apple 钥匙串。
- Share Extension 只写入共享收件箱，不创建完整学习材料或自动归类。
