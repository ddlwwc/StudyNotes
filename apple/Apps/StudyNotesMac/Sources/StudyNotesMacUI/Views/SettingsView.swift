import StudyNotesKit
import SwiftUI

public struct SettingsView: View {
    @Bindable private var model: WorkspaceModel

    public init(model: WorkspaceModel) {
        self.model = model
    }

    public var body: some View {
        TabView(selection: $model.settingsPage) {
            WorkspaceSettingsPageView(model: model)
                .tabItem {
                    Label(WorkspaceSettingsPage.workspace.title, systemImage: "folder")
                }
                .tag(WorkspaceSettingsPage.workspace)

            AIConfigurationSheet(model: model)
                .tabItem {
                    Label(WorkspaceSettingsPage.ai.title, systemImage: "sparkles")
                }
                .tag(WorkspaceSettingsPage.ai)

            PublishingSettingsPage(model: model)
                .tabItem {
                    Label(WorkspaceSettingsPage.publishing.title, systemImage: "paperplane")
                }
                .tag(WorkspaceSettingsPage.publishing)

            CredentialsSettingsPage(model: model)
                .tabItem {
                    Label(WorkspaceSettingsPage.credentials.title, systemImage: "key")
                }
                .tag(WorkspaceSettingsPage.credentials)

            ReadingSettingsPage(model: model)
                .tabItem {
                    Label(WorkspaceSettingsPage.reading.title, systemImage: "textformat.size")
                }
                .tag(WorkspaceSettingsPage.reading)
        }
        .padding(12)
        .frame(minWidth: 840, minHeight: 620)
        .background(SNColor.panel)
        .preferredColorScheme(preferredColorScheme)
        .alert("无法完成设置", isPresented: errorIsPresented) {
            Button("好", role: .cancel) {
                model.dismissError()
            }
        } message: {
            Text(model.errorMessage ?? "未知错误")
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch model.readingPreferences.theme {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    model.dismissError()
                }
            }
        )
    }
}

private struct WorkspaceSettingsPageView: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        SettingsPageLayout(
            title: "学习目录",
            subtitle: "学习材料保存在本地或 iCloud 目录；栏宽与阅读偏好只保存在当前设备。"
        ) {
            SettingsCard("当前目录") {
                LabeledContent("状态") {
                    Text(model.connectionLabel)
                        .foregroundStyle(model.isConnected ? SNColor.green : SNColor.muted)
                }
                LabeledContent("位置") {
                    Text(model.connectionDetail)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Button {
                        Task { await model.chooseWorkspace() }
                    } label: {
                        Label("选择本地目录", systemImage: "folder")
                    }
                    Button {
                        Task { await model.chooseICloudWorkspace() }
                    } label: {
                        Label("选择 iCloud 目录", systemImage: "icloud")
                    }
                    Button {
                        Task { await model.reloadIndex() }
                    } label: {
                        Label("重建索引", systemImage: "arrow.clockwise")
                    }
                    .disabled(!model.isConnected)
                }
                .buttonStyle(.bordered)
            }

            SettingsCard("本地布局") {
                LabeledContent("知识库栏") {
                    Text("\(Int(model.libraryPaneWidth)) pt")
                }
                LabeledContent("材料目录栏") {
                    Text("\(Int(model.materialPaneWidth)) pt")
                }
                LabeledContent("研读层") {
                    Text("\(Int(model.studyPaneWidth)) pt")
                }
                Text("拖动分隔线连续调宽，双击恢复默认宽度。折叠状态和宽度不会写入 iCloud。")
                    .font(.sn(9))
                    .foregroundStyle(SNColor.muted)
            }
        }
    }
}

private struct PublishingSettingsPage: View {
    @Bindable var model: WorkspaceModel
    @State private var serverURL = ""
    @State private var noteMediaKey = ""
    @State private var publishingResult: ServiceConnectionStatus = .idle
    @State private var confirmsMediaCleanup = false
    @State private var confirmsMediaMigration = false

    private let tester = ServiceConnectionTester()

    var body: some View {
        SettingsPageLayout(
            title: "发布配置",
            subtitle: "发布默认使用未列出可见性；标注和 AI 附录默认不公开。"
        ) {
            SettingsCard("服务与凭据") {
                TextField("服务器地址", text: $serverURL)
                    .textFieldStyle(.roundedBorder)
                Button("保存服务器地址") {
                    saveServerURL()
                }
                .buttonStyle(.bordered)
                .disabled(serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                SecureField("笔记媒体 Bearer 密钥", text: $noteMediaKey)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button {
                        saveServerURL()
                        if model.saveNoteMediaKey(noteMediaKey) {
                            noteMediaKey = ""
                        }
                    } label: {
                        Label("保存媒体密钥", systemImage: "key")
                    }
                    .disabled(noteMediaKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Label(
                        model.hasNoteMediaKey ? "钥匙串已有媒体密钥" : "钥匙串中没有媒体密钥",
                        systemImage: model.hasNoteMediaKey ? "checkmark.shield" : "key.slash"
                    )
                    .font(.sn(9))
                    .foregroundStyle(SNColor.muted)
                }
                Text("媒体密钥只保存在本机钥匙串，不写入普通配置、iCloud 或日志。")
                    .font(.sn(9))
                    .foregroundStyle(SNColor.muted)
            }

            SettingsCard("默认发布范围") {
                Picker(
                    "默认可见性",
                    selection: Binding(
                        get: { model.appSettings.defaultPublishVisibility },
                        set: { value in
                            model.updateAppSettings {
                                $0.defaultPublishVisibility = value
                            }
                        }
                    )
                ) {
                    ForEach(PublishVisibility.allCases) { visibility in
                        Text(visibility.title).tag(visibility)
                    }
                }
                .pickerStyle(.segmented)

                Toggle(
                    "默认公开标注与备注",
                    isOn: Binding(
                        get: { model.appSettings.publishAnnotationsByDefault },
                        set: { value in
                            model.updateAppSettings {
                                $0.publishAnnotationsByDefault = value
                            }
                        }
                    )
                )
                .toggleStyle(.checkbox)

                Toggle(
                    "默认公开 AI 附录",
                    isOn: Binding(
                        get: { model.appSettings.publishAIByDefault },
                        set: { value in
                            model.updateAppSettings {
                                $0.publishAIByDefault = value
                            }
                        }
                    )
                )
                .toggleStyle(.checkbox)
            }

            SettingsCard("连接测试") {
                HStack {
                    Button("测试发布服务") {
                        Task {
                            publishingResult = .testing
                            publishingResult = await tester.test(
                                .publishing,
                                serverURLText: serverURL
                            ).status
                        }
                    }
                    Button("测试媒体服务") {
                        saveServerURL()
                        Task {
                            await model.refreshNoteMediaState()
                        }
                    }
                }
                ConnectionStatusRow(title: "发布服务", status: publishingResult)
                ConnectionStatusRow(title: "媒体服务", status: model.noteMediaConnection)
                if let status = model.noteMediaStatus {
                    LabeledContent("Bucket", value: status.bucket)
                    LabeledContent("下载域名", value: status.domain)
                    LabeledContent("上传端点", value: status.uploadUrl)
                    if let message = status.message {
                        Text(message)
                            .font(.sn(9))
                            .foregroundStyle(SNColor.muted)
                    }
                }
                if serverURL
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                    .hasPrefix("http://") {
                    Label(
                        "发布服务使用 HTTP，发布请求和响应可能在链路中被观察或篡改。",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.sn(9))
                    .foregroundStyle(SNColor.orange)
                }
                if let warning = model.noteMediaHTTPWarning {
                    Label(
                        warning,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.sn(9))
                    .foregroundStyle(SNColor.orange)
                }
                Text("连接状态来自 /api/v1/library-media/status，服务端不会返回永久七牛密钥。")
                    .font(.sn(9))
                    .foregroundStyle(SNColor.muted)
            }

            SettingsCard("媒体队列与缓存") {
                LabeledContent(
                    "待上传任务",
                    value:
                        "\(model.noteMediaQueue.filter { $0.state != .uploaded }.count)"
                )
                LabeledContent(
                    "本机缓存",
                    value: ByteCountFormatter.string(
                        fromByteCount: Int64(model.noteMediaCacheByteCount),
                        countStyle: .file
                    )
                )
                ForEach(Array(model.noteMediaQueue.prefix(8))) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.sourceFileName)
                                .lineLimit(1)
                            Spacer()
                            Text(mediaStateText(item.state))
                                .font(.sn(9))
                                .foregroundStyle(
                                    mediaStateColor(item.state)
                                )
                        }
                        HStack {
                            if item.state == .waiting {
                                Button("上传") {
                                    Task {
                                        await model.uploadNoteMedia(id: item.id)
                                    }
                                }
                                Button("取消") {
                                    Task {
                                        await model.cancelNoteMediaUpload(
                                            id: item.id
                                        )
                                    }
                                }
                            }
                            if case .failed = item.state {
                                Button("重试") {
                                    Task {
                                        await model.retryNoteMediaUpload(
                                            id: item.id
                                        )
                                    }
                                }
                            }
                            if case .cancelled = item.state {
                                Button("重新排队") {
                                    Task {
                                        await model.retryNoteMediaUpload(
                                            id: item.id
                                        )
                                    }
                                }
                            }
                            if case .uploading = item.state {
                                Button("取消") {
                                    Task {
                                        await model.cancelNoteMediaUpload(
                                            id: item.id
                                        )
                                    }
                                }
                            }
                        }
                        .buttonStyle(.link)
                    }
                }
                HStack {
                    Button {
                        Task { await model.refreshNoteMediaState() }
                    } label: {
                        Label("刷新媒体状态", systemImage: "arrow.clockwise")
                    }
                    Button(role: .destructive) {
                        Task { await model.clearNoteMediaCache() }
                    } label: {
                        Label("清除缓存", systemImage: "trash")
                    }
                    .disabled(model.noteMediaCacheByteCount == 0)
                }
                .buttonStyle(.bordered)
            }

            SettingsCard("媒体扫描、迁移与清理") {
                Button {
                    Task { await model.scanSelectedNoteMedia() }
                } label: {
                    Label(
                        "扫描当前笔记与历史版本",
                        systemImage: "doc.text.magnifyingglass"
                    )
                }
                .buttonStyle(.bordered)
                .disabled(
                    model.selectedDocument == nil
                        || model.isScanningNoteMedia
                )

                if let scan = model.noteMediaScan {
                    LabeledContent(
                        "当前 / 历史引用",
                        value:
                            "\(scan.summary.currentCount) / "
                            + "\(scan.summary.historyCount)"
                    )
                    LabeledContent(
                        "当前引用大小",
                        value: ByteCountFormatter.string(
                            fromByteCount:
                                Int64(model.noteMediaCurrentByteCount),
                            countStyle: .file
                        )
                    )
                    LabeledContent(
                        "历史引用大小",
                        value: ByteCountFormatter.string(
                            fromByteCount:
                                Int64(model.noteMediaHistoricalByteCount),
                            countStyle: .file
                        )
                    )
                    LabeledContent(
                        "引用总大小",
                        value: ByteCountFormatter.string(
                            fromByteCount: Int64(scan.summary.totalSize),
                            countStyle: .file
                        )
                    )
                    LabeledContent(
                        "历史本地媒体",
                        value:
                            "\(scan.summary.historicalLocalCount) 个 · "
                            + ByteCountFormatter.string(
                                fromByteCount:
                                    Int64(scan.summary.historicalLocalSize),
                                countStyle: .file
                            )
                    )
                    LabeledContent(
                        "可清理云端媒体",
                        value:
                            "\(model.noteMediaCleanupCandidates.count) 个 · "
                            + ByteCountFormatter.string(
                                fromByteCount: Int64(
                                    model.noteMediaCleanupCandidateByteCount
                                ),
                                countStyle: .file
                            )
                    )
                    LabeledContent(
                        "缺失引用",
                        value: "\(scan.summary.missingCount)"
                    )
                    HStack {
                        Button {
                            confirmsMediaMigration = true
                        } label: {
                            Label(
                                "迁移历史本地媒体",
                                systemImage: "icloud.and.arrow.up"
                            )
                        }
                        .disabled(scan.summary.historicalLocalCount == 0)
                        Button(role: .destructive) {
                            confirmsMediaCleanup = true
                        } label: {
                            Label(
                                "清理无引用媒体",
                                systemImage: "trash.slash"
                            )
                        }
                        .disabled(model.noteMediaCleanupCandidates.isEmpty)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Text("先扫描，确认数量、大小和引用关系后再执行迁移或清理。")
                        .font(.sn(9))
                        .foregroundStyle(SNColor.muted)
                }
            }
        }
        .onAppear {
            serverURL = model.appSettings.publishingServerURL
            Task { await model.refreshNoteMediaState() }
        }
        .confirmationDialog(
            "迁移历史本地媒体？",
            isPresented: $confirmsMediaMigration
        ) {
            Button("确认加入上传队列") {
                Task { await model.migrateSelectedNoteMediaHistory() }
            }
        } message: {
            Text("不会自动改写 Markdown 引用；迁移失败时保留原文件并允许重试。")
        }
        .confirmationDialog(
            "清理无引用云端媒体？",
            isPresented: $confirmsMediaCleanup
        ) {
            Button("确认清理", role: .destructive) {
                Task { await model.cleanupUnreferencedNoteMedia() }
            }
        } message: {
            Text("服务端会再次校验引用关系；仍被当前正文或历史版本使用的对象不会删除。")
        }
    }

    private func mediaStateText(_ state: NoteMediaUploadState) -> String {
        switch state {
        case .waiting:
            "等待上传"
        case let .uploading(progress):
            "上传 \(Int(progress * 100))%"
        case let .failed(message):
            "失败：\(message)"
        case .cancelled:
            "已取消"
        case .uploaded:
            "已上传"
        }
    }

    private func mediaStateColor(_ state: NoteMediaUploadState) -> Color {
        switch state {
        case .failed:
            SNColor.red
        case .uploaded:
            SNColor.green
        case .waiting, .uploading, .cancelled:
            SNColor.muted
        }
    }

    private func saveServerURL() {
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        serverURL = trimmed
        model.updateAppSettings {
            $0.publishingServerURL = trimmed
        }
    }
}

private struct CredentialsSettingsPage: View {
    @Bindable var model: WorkspaceModel
    @State private var publishing = PublishingPanelModel()
    @State private var registrationSecret = ""
    @State private var confirmsRotation = false
    @State private var confirmsRevocation = false

    var body: some View {
        SettingsPageLayout(
            title: "密钥与凭据",
            subtitle: "AI Key、发布私钥和笔记媒体密钥均只保存在本机 macOS 钥匙串。"
        ) {
            SettingsCard("发布密钥") {
                LabeledContent("公钥") {
                    Text(publishing.credentialKid ?? "尚未生成")
                        .lineLimit(1)
                        .font(.system(size: 9, design: .monospaced))
                }
                SecureField("发布密钥登记凭据（仅用于本次操作）", text: $registrationSecret)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button(
                        publishing.credentialKid == nil ? "生成并登记公钥" : "登记现有公钥"
                    ) {
                        publishing.registrationSecret = registrationSecret
                        Task { await publishing.registerKey() }
                    }
                    .disabled(registrationSecret.isEmpty || publishing.isBusy)
                    Button("轮换") {
                        confirmsRotation = true
                    }
                    .disabled(registrationSecret.isEmpty || publishing.isBusy)
                    Button("撤销", role: .destructive) {
                        confirmsRevocation = true
                    }
                    .disabled(publishing.credentialKid == nil || publishing.isBusy)
                }
                .buttonStyle(.bordered)
                if let message = publishing.statusMessage {
                    Text(message)
                        .font(.sn(9))
                        .foregroundStyle(publishing.hasError ? SNColor.red : SNColor.muted)
                }
            }

            SettingsCard("AI 供应商") {
                if model.providerProfiles.isEmpty {
                    Text("尚未配置 AI 供应商。")
                        .foregroundStyle(SNColor.muted)
                } else {
                    ForEach(model.providerProfiles) { profile in
                        LabeledContent(profile.name) {
                            Label(
                                model.hasAPIKey(for: profile) ? "Key 已在钥匙串" : "缺少 Key",
                                systemImage: model.hasAPIKey(for: profile)
                                    ? "checkmark.shield"
                                    : "key.slash"
                            )
                            .font(.sn(9))
                            .foregroundStyle(SNColor.muted)
                        }
                    }
                }
                Button("前往 AI 配置") {
                    model.settingsPage = .ai
                }
                .buttonStyle(.bordered)
            }

            SettingsCard("笔记媒体") {
                LabeledContent("Bearer 密钥") {
                    Label(
                        model.hasNoteMediaKey ? "已在钥匙串" : "尚未配置",
                        systemImage: model.hasNoteMediaKey ? "checkmark.shield" : "key.slash"
                    )
                    .font(.sn(9))
                    .foregroundStyle(SNColor.muted)
                }
                Button("前往发布配置") {
                    model.settingsPage = .publishing
                }
                .buttonStyle(.bordered)
            }
        }
        .confirmationDialog("轮换发布密钥？", isPresented: $confirmsRotation) {
            Button("撤销旧公钥并轮换", role: .destructive) {
                publishing.registrationSecret = registrationSecret
                Task { await publishing.rotateKey() }
            }
        } message: {
            Text("旧公钥会先撤销，新私钥只保存到本机钥匙串。")
        }
        .confirmationDialog("撤销本机发布密钥？", isPresented: $confirmsRevocation) {
            Button("撤销并删除本机私钥", role: .destructive) {
                Task { await publishing.revokeKey() }
            }
        } message: {
            Text("撤销后必须重新生成并登记公钥才能继续发布。")
        }
    }
}

private struct ReadingSettingsPage: View {
    @Bindable var model: WorkspaceModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SettingsPageLayout(
            title: "阅读偏好",
            subtitle: "主题覆盖整个 App；排版只影响阅读与编辑器正文，并保存在当前设备。"
        ) {
            SettingsCard("外观") {
                Picker("主题", selection: $model.readingPreferences.theme) {
                    Text("跟随系统").tag(ReadingTheme.system)
                    Text("浅色").tag(ReadingTheme.light)
                    Text("深色").tag(ReadingTheme.dark)
                }
                .pickerStyle(.segmented)
            }

            SettingsCard("正文排版") {
                ReadingSlider(
                    title: "字号",
                    value: $model.readingPreferences.fontSize,
                    range: ReadingPreferences.fontSizeRange,
                    label: "\(Int(model.readingPreferences.fontSize)) pt"
                )
                ReadingSlider(
                    title: "行宽",
                    value: $model.readingPreferences.lineWidth,
                    range: ReadingPreferences.lineWidthRange,
                    label: "\(Int(model.readingPreferences.lineWidth)) pt"
                )
                ReadingSlider(
                    title: "行高",
                    value: $model.readingPreferences.lineHeight,
                    range: ReadingPreferences.lineHeightRange,
                    label: String(format: "%.2f", model.readingPreferences.lineHeight)
                )
                LabeledContent("代码字体") {
                    TextField("SFMono-Regular", text: $model.readingPreferences.codeFont)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }
            }

            SettingsCard("无障碍") {
                LabeledContent("减少动态效果") {
                    Text(reduceMotion ? "系统已开启" : "系统未开启")
                        .foregroundStyle(reduceMotion ? SNColor.green : SNColor.muted)
                }
                Text("侧栏与文件夹动画会遵循系统设置；关闭动态效果时只更新最终状态。")
                    .font(.sn(9))
                    .foregroundStyle(SNColor.muted)
                Button("恢复默认阅读偏好") {
                    model.readingPreferences = ReadingPreferences()
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

private struct ReadingSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let label: String

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                Slider(value: $value, in: range)
                    .frame(width: 260)
                Text(label)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(SNColor.muted)
                    .frame(width: 64, alignment: .trailing)
            }
        }
    }
}

private struct ConnectionStatusRow: View {
    let title: String
    let status: ServiceConnectionStatus

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.sn(10, weight: .medium))
            Spacer()
            switch status {
            case .idle:
                Text("未测试")
                    .foregroundStyle(SNColor.muted)
            case .testing:
                ProgressView()
                    .controlSize(.mini)
                Text("测试中")
                    .foregroundStyle(SNColor.muted)
            case let .succeeded(message):
                Label(message, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(SNColor.green)
            case let .failed(message):
                Label(message, systemImage: "xmark.circle.fill")
                    .foregroundStyle(SNColor.red)
            }
        }
        .font(.sn(9))
    }
}

private struct SettingsPageLayout<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.sn(22, weight: .semibold))
                        .foregroundStyle(SNColor.ink)
                    Text(subtitle)
                        .font(.sn(10))
                        .foregroundStyle(SNColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                content
                Spacer(minLength: 0)
            }
            .padding(22)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SNColor.panel)
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .font(.sn(10))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }
}
