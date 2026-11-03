#if os(iOS)
import Foundation
import SwiftUI
import StudyNotesIOSCore
import StudyNotesKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: IOSAppModel

    var body: some View {
        NavigationStack {
            List {
                Section("学习与内容") {
                    NavigationLink {
                        LearningDirectorySettingsView(model: model)
                    } label: {
                        SettingsRow(
                            title: "学习目录",
                            detail: model.rootState.label,
                            systemImage: "externaldrive"
                        )
                    }

                    NavigationLink {
                        AIProviderSettingsPage(model: model)
                    } label: {
                        SettingsRow(
                            title: "AI 配置",
                            detail: "\(model.providers.count) 个供应商",
                            systemImage: "sparkles"
                        )
                    }
                }

                Section("发布与凭据") {
                    NavigationLink {
                        PublishingSettingsPage(model: model)
                    } label: {
                        SettingsRow(
                            title: "发布配置",
                            detail: "仅 Mac 发起发布",
                            systemImage: "paperplane"
                        )
                    }

                    NavigationLink {
                        CredentialsSettingsPage(model: model)
                    } label: {
                        SettingsRow(
                            title: "密钥与凭据",
                            detail: "本机钥匙串",
                            systemImage: "key"
                        )
                    }
                }

                Section("阅读") {
                    NavigationLink {
                        ReadingPreferencesSettingsView(model: model)
                    } label: {
                        SettingsRow(
                            title: "阅读偏好",
                            detail: readingSummary,
                            systemImage: "textformat.size"
                        )
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var readingSummary: String {
        "\(themeLabel) · \(Int(model.readingPreferences.fontSize))pt"
    }

    private var themeLabel: String {
        switch model.readingPreferences.theme {
        case .system:
            "跟随系统"
        case .light:
            "浅色"
        case .dark:
            "深色"
        }
    }
}

private struct SettingsRow: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        Label {
            HStack {
                Text(title)
                    .foregroundStyle(SNColor.ink)
                Spacer()
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(SNColor.muted)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(SNColor.primary)
        }
    }
}

private struct LearningDirectorySettingsView: View {
    @Bindable var model: IOSAppModel

    var body: some View {
        Form {
            Section("当前目录") {
                LabeledContent("连接状态", value: model.rootState.label)
                if let rootURL = model.rootState.url {
                    LabeledContent("位置") {
                        Text(rootURL.lastPathComponent)
                            .lineLimit(1)
                    }
                }
                LabeledContent(
                    "内容",
                    value: "\(model.snapshot.knowledgeBases.count) 个知识库 · \(model.snapshot.materials.count) 份材料"
                )
            }

            Section {
                Button("刷新目录与索引") {
                    Task { await model.reloadAll() }
                }
                if !model.isICloud {
                    Button("重新连接 iCloud") {
                        Task { await model.retryICloud() }
                    }
                }
            } footer: {
                Text("学习目录与材料正文由 iCloud 文件结构承载；iOS 只保存可重建的本地派生数据。")
            }
        }
        .navigationTitle("学习目录")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AIProviderSettingsPage: View {
    @Bindable var model: IOSAppModel
    @State private var showingProviders = false

    var body: some View {
        Form {
            Section {
                ForEach(model.providers) { provider in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(provider.name)
                                .foregroundStyle(SNColor.ink)
                            Spacer()
                            ProviderKeyStatus(provider: provider, model: model)
                        }
                        Text(provider.modelID)
                            .font(.system(size: 11))
                            .foregroundStyle(SNColor.muted)
                        Text(provider.baseURL)
                            .font(.system(size: 10))
                            .foregroundStyle(SNColor.muted)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 2)
                }
            }

            Section {
                Button("管理 AI 供应商") {
                    showingProviders = true
                }
            } footer: {
                Text("API Key 只保存在本机 Apple 钥匙串，不进入 iCloud 或学习目录。")
            }
        }
        .navigationTitle("AI 配置")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingProviders) {
            AIProviderSettingsView(model: model)
        }
    }
}

private struct ProviderKeyStatus: View {
    let provider: AIProvider
    @Bindable var model: IOSAppModel
    @State private var hasKey = false

    var body: some View {
        StatusPill(
            text: hasKey ? "Key 已保存" : "需要 Key",
            color: hasKey ? SNColor.green : SNColor.amberInk,
            background: hasKey ? SNColor.greenSoft : SNColor.amberSoft,
            systemImage: hasKey ? "checkmark.circle" : "key"
        )
        .task(id: provider.id) {
            hasKey = await model.hasAPIKey(for: provider)
        }
    }
}

private struct PublishingSettingsPage: View {
    @Bindable var model: IOSAppModel
    @State private var serverURL = ""

    var body: some View {
        Form {
            Section("发布边界") {
                Label("发布动作仅在 Mac 发起", systemImage: "desktopcomputer")
                    .foregroundStyle(SNColor.ink)
                Text("iOS 设置只展示发布服务和默认参数，不提供发布、更新或下架操作。")
                    .font(.system(size: 11))
                    .foregroundStyle(SNColor.muted)
            }

            Section("发布服务") {
                TextField("服务器地址", text: $serverURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("保存服务器地址") {
                    model.savePublishingServerURL(serverURL)
                }
                if serverURL.lowercased().hasPrefix("http://") {
                    Label(
                        "当前允许 HTTP。共享媒体密钥可能被链路攻击者截获。",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(SNColor.amberInk)
                }
            }

            Section("默认发布参数") {
                LabeledContent(
                    "可见性",
                    value: IOSSettingsStore.publicationDefaults.visibilityLabel
                )
                LabeledContent(
                    "发布标注",
                    value: IOSSettingsStore.publicationDefaults.publishesAnnotations
                        ? "开启"
                        : "关闭"
                )
                LabeledContent(
                    "发布 AI 附录",
                    value: IOSSettingsStore.publicationDefaults.publishesAIAppendix
                        ? "开启"
                        : "关闭"
                )
            }

            Section("笔记媒体") {
                NavigationLink {
                    MediaKeySettingsView(model: model)
                } label: {
                    LabeledContent(
                        "媒体密钥",
                        value: model.mediaKeyConfigured ? "已配置" : "未配置"
                    )
                }
            }
        }
        .navigationTitle("发布配置")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            serverURL = model.publishingServerURL
            model.refreshMediaKeyState()
        }
    }
}

private struct CredentialsSettingsPage: View {
    @Bindable var model: IOSAppModel

    var body: some View {
        Form {
            Section("笔记媒体") {
                NavigationLink {
                    MediaKeySettingsView(model: model)
                } label: {
                    LabeledContent(
                        "Bearer 密钥",
                        value: model.mediaKeyConfigured ? "已保存" : "未配置"
                    )
                }
            }

            Section("AI 供应商") {
                ForEach(model.providers) { provider in
                    LabeledContent(provider.name) {
                        ProviderKeyStatus(provider: provider, model: model)
                    }
                }
            }

            Section("发布密钥") {
                Text("Ed25519 发布密钥只保存在 Mac 钥匙串。iOS 不登记、轮换或撤销发布密钥。")
                    .font(.system(size: 11))
                    .foregroundStyle(SNColor.muted)
            }
        }
        .navigationTitle("密钥与凭据")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            model.refreshMediaKeyState()
        }
    }
}

private struct MediaKeySettingsView: View {
    @Bindable var model: IOSAppModel
    @State private var mediaKey = ""
    @State private var errorMessage: String?
    @State private var confirmsMigration = false
    @State private var confirmsCleanup = false
    @State private var pendingCellularUploadID: UUID?

    var body: some View {
        Form {
            Section("笔记媒体 Bearer 密钥") {
                SecureField(
                    model.mediaKeyConfigured
                        ? "已保存；输入新值可替换"
                        : "输入共享媒体密钥",
                    text: $mediaKey
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                Button("保存到钥匙串") {
                    do {
                        try model.saveMediaKey(mediaKey)
                        mediaKey = ""
                        errorMessage = nil
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .disabled(
                    mediaKey.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                )

                if model.mediaKeyConfigured {
                    Button("移除媒体密钥", role: .destructive) {
                        do {
                            try model.removeMediaKey()
                            mediaKey = ""
                            errorMessage = nil
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
            }

            Section {
                Text("密钥只写入本机 Keychain，不进入 UserDefaults、iCloud、学习材料或日志。")
                    .font(.system(size: 11))
                    .foregroundStyle(SNColor.muted)
                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
            }

            Section("连接状态") {
                Button {
                    Task { await model.refreshMediaStatus() }
                } label: {
                    Label("请求媒体服务状态", systemImage: "arrow.clockwise")
                }
                .disabled(model.mediaStatusIsLoading)
                if let status = model.mediaStatus {
                    LabeledContent("Bucket", value: status.bucket)
                    LabeledContent("下载域名", value: status.domain)
                    LabeledContent("上传端点", value: status.uploadUrl)
                }
                Text(model.mediaStatusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(SNColor.muted)
                if let warning = model.mediaHTTPWarning {
                    Label(
                        warning,
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(SNColor.amberInk)
                }
            }

            Section("队列与缓存") {
                LabeledContent(
                    "待上传任务",
                    value:
                        "\(model.mediaQueue.filter { $0.state != .uploaded }.count)"
                )
                LabeledContent(
                    "本机缓存",
                    value: ByteCountFormatter.string(
                        fromByteCount: Int64(model.mediaCacheByteCount),
                        countStyle: .file
                    )
                )
                ForEach(Array(model.mediaQueue.prefix(8))) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.sourceFileName)
                                .lineLimit(1)
                            Spacer()
                            Text(mediaStateText(item.state))
                                .font(.system(size: 11))
                                .foregroundStyle(
                                    mediaStateColor(item.state)
                                )
                        }
                        HStack {
                            if item.state == .waiting {
                                Button("上传") {
                                    if model.requiresCellularConfirmation(
                                        for: item
                                    ) {
                                        pendingCellularUploadID = item.id
                                    } else {
                                        Task {
                                            await model.uploadMedia(id: item.id)
                                        }
                                    }
                                }
                                Button("取消", role: .destructive) {
                                    Task {
                                        await model.cancelMediaUpload(
                                            id: item.id
                                        )
                                    }
                                }
                            }
                            if case .failed = item.state {
                                Button("重试") {
                                    Task {
                                        await model.retryMediaUpload(
                                            id: item.id
                                        )
                                    }
                                }
                            }
                            if case .cancelled = item.state {
                                Button("重新排队") {
                                    Task {
                                        await model.retryMediaUpload(
                                            id: item.id
                                        )
                                    }
                                }
                            }
                            if case .uploading = item.state {
                                Button("取消", role: .destructive) {
                                    Task {
                                        await model.cancelMediaUpload(
                                            id: item.id
                                        )
                                    }
                                }
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Button("清除媒体缓存", role: .destructive) {
                    Task { await model.clearMediaCache() }
                }
                .disabled(model.mediaCacheByteCount == 0)
            }

            Section("扫描、迁移与清理") {
                Button("扫描当前笔记媒体") {
                    Task { await model.scanSelectedMedia() }
                }
                .disabled(
                    model.workspace.materialID == nil
                        || model.isScanningMedia
                )
                if let scan = model.mediaScan {
                    LabeledContent(
                        "当前 / 历史引用",
                        value:
                            "\(scan.summary.currentCount) / "
                            + "\(scan.summary.historyCount)"
                    )
                    LabeledContent(
                        "当前引用大小",
                        value: ByteCountFormatter.string(
                            fromByteCount: Int64(model.mediaCurrentByteCount),
                            countStyle: .file
                        )
                    )
                    LabeledContent(
                        "历史引用大小",
                        value: ByteCountFormatter.string(
                            fromByteCount:
                                Int64(model.mediaHistoricalByteCount),
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
                            "\(model.mediaCleanupCandidates.count) 个 · "
                            + ByteCountFormatter.string(
                                fromByteCount: Int64(
                                    model.mediaCleanupCandidateByteCount
                                ),
                                countStyle: .file
                            )
                    )
                    LabeledContent(
                        "缺失引用",
                        value: "\(scan.summary.missingCount)"
                    )
                    Button("迁移历史本地媒体") {
                        confirmsMigration = true
                    }
                    .disabled(scan.summary.historicalLocalCount == 0)
                    Button("清理无引用云端媒体", role: .destructive) {
                        confirmsCleanup = true
                    }
                    .disabled(model.mediaCleanupCandidates.isEmpty)
                }
            }
        }
        .navigationTitle("媒体密钥")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            model.refreshMediaKeyState()
            Task { await model.refreshMediaStatus() }
        }
        .confirmationDialog(
            "迁移历史本地媒体？",
            isPresented: $confirmsMigration
        ) {
            Button("确认加入上传队列") {
                Task { await model.migrateSelectedMediaHistory() }
            }
        } message: {
            Text("不会自动改写 Markdown 引用；失败时保留原文件。")
        }
        .confirmationDialog(
            "清理无引用云端媒体？",
            isPresented: $confirmsCleanup
        ) {
            Button("确认清理", role: .destructive) {
                Task { await model.cleanupUnreferencedMedia() }
            }
        } message: {
            Text("服务端会再次校验当前正文和历史版本引用。")
        }
        .confirmationDialog(
            "使用蜂窝网络上传？",
            isPresented: Binding(
                get: { pendingCellularUploadID != nil },
                set: {
                    if !$0 {
                        pendingCellularUploadID = nil
                    }
                }
            )
        ) {
            Button("继续上传") {
                guard let id = pendingCellularUploadID else {
                    return
                }
                pendingCellularUploadID = nil
                Task {
                    await model.uploadMedia(
                        id: id,
                        confirmedCellularUpload: true
                    )
                }
            }
        } message: {
            Text("该媒体超过 10MB，继续会消耗蜂窝网络流量。")
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

    private func mediaStateColor(
        _ state: NoteMediaUploadState
    ) -> Color {
        switch state {
        case .failed:
            SNColor.red
        case .uploaded:
            SNColor.green
        case .waiting, .uploading, .cancelled:
            SNColor.muted
        }
    }
}

private struct ReadingPreferencesSettingsView: View {
    @Bindable var model: IOSAppModel

    var body: some View {
        Form {
            Section("外观") {
                Picker("主题", selection: themeBinding) {
                    Text("跟随系统").tag(IOSReadingTheme.system)
                    Text("浅色").tag(IOSReadingTheme.light)
                    Text("深色").tag(IOSReadingTheme.dark)
                }
                .pickerStyle(.segmented)
            }

            Section("正文排版") {
                preferenceSlider(
                    title: "字号",
                    value: fontSizeBinding,
                    range: 12...24,
                    step: 1,
                    valueLabel: "\(Int(model.readingPreferences.fontSize))pt"
                )
                preferenceSlider(
                    title: "行高",
                    value: lineHeightBinding,
                    range: 1.4...2.2,
                    step: 0.05,
                    valueLabel: String(
                        format: "%.2f",
                        model.readingPreferences.lineHeight
                    )
                )
                preferenceSlider(
                    title: "行宽",
                    value: lineWidthBinding,
                    range: 420...900,
                    step: 10,
                    valueLabel: "\(Int(model.readingPreferences.lineWidth))pt"
                )
            }

            Section("代码字体") {
                TextField(
                    "字体名称",
                    text: Binding(
                        get: { model.readingPreferences.codeFont },
                        set: { value in
                            var preferences = model.readingPreferences
                            preferences.codeFont = value
                            model.updateReadingPreferences(preferences)
                        }
                    )
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            }

            Section {
                Text("阅读偏好只保存在当前设备，不写入 iCloud，也不会覆盖 Mac 的偏好。")
                    .font(.system(size: 11))
                    .foregroundStyle(SNColor.muted)
            }
        }
        .navigationTitle("阅读偏好")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var themeBinding: Binding<IOSReadingTheme> {
        Binding(
            get: { model.readingPreferences.theme },
            set: { value in
                var preferences = model.readingPreferences
                preferences.theme = value
                model.updateReadingPreferences(preferences)
            }
        )
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { model.readingPreferences.fontSize },
            set: { value in
                var preferences = model.readingPreferences
                preferences.fontSize = value
                model.updateReadingPreferences(preferences)
            }
        )
    }

    private var lineHeightBinding: Binding<Double> {
        Binding(
            get: { model.readingPreferences.lineHeight },
            set: { value in
                var preferences = model.readingPreferences
                preferences.lineHeight = value
                model.updateReadingPreferences(preferences)
            }
        )
    }

    private var lineWidthBinding: Binding<Double> {
        Binding(
            get: { model.readingPreferences.lineWidth },
            set: { value in
                var preferences = model.readingPreferences
                preferences.lineWidth = value
                model.updateReadingPreferences(preferences)
            }
        )
    }

    private func preferenceSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        valueLabel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(valueLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(SNColor.muted)
            }
            Slider(
                value: value,
                in: range,
                step: step
            )
            .tint(SNColor.primary)
        }
    }
}
#endif
