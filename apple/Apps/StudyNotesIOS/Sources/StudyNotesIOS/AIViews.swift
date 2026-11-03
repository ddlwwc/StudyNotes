#if os(iOS)
import SwiftUI
import StudyNotesIOSCore

struct AIProviderSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: IOSAppModel
    @State private var editingProvider: AIProvider?
    @State private var isAddingProvider = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.providers) { provider in
                        Button {
                            editingProvider = provider
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(SNColor.primary)
                                    .frame(width: 30, height: 30)
                                    .background(SNColor.primarySoft)
                                    .clipShape(RoundedRectangle(cornerRadius: 7))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(provider.name)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(SNColor.ink)
                                    Text(provider.modelID)
                                        .font(.system(size: 9.5))
                                        .foregroundStyle(SNColor.muted)
                                }
                                Spacer()
                                APIKeyIndicator(
                                    provider: provider,
                                    model: model
                                )
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("具名供应商")
                } footer: {
                    Text("API Key 只保存在本机 Apple 钥匙串中，不进入 iCloud、学习材料或日志。")
                }

                Section {
                    Button {
                        isAddingProvider = true
                    } label: {
                        Label("添加 OpenAI 兼容供应商", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("AI 供应商")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(item: $editingProvider) { provider in
                ProviderEditor(
                    model: model,
                    originalProvider: provider
                )
            }
            .sheet(isPresented: $isAddingProvider) {
                ProviderEditor(model: model, originalProvider: nil)
            }
        }
    }
}

private struct APIKeyIndicator: View {
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

private struct ProviderEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: IOSAppModel
    let originalProvider: AIProvider?

    @State private var name: String
    @State private var baseURL: String
    @State private var modelID: String
    @State private var apiKey = ""
    @State private var removeStoredKey = false
    @State private var isSaving = false

    init(model: IOSAppModel, originalProvider: AIProvider?) {
        self.model = model
        self.originalProvider = originalProvider
        _name = State(initialValue: originalProvider?.name ?? "")
        _baseURL = State(
            initialValue: originalProvider?.baseURL ?? "https://api.deepseek.com/v1"
        )
        _modelID = State(
            initialValue: originalProvider?.modelID ?? "deepseek-chat"
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("供应商") {
                    TextField("名称，如 DeepSeek", text: $name)
                    TextField("基础地址", text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    TextField("模型 ID", text: $modelID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("API Key") {
                    SecureField(
                        originalProvider == nil ? "sk-..." : "留空表示不修改",
                        text: $apiKey
                    )
                    if originalProvider != nil {
                        Toggle("删除已保存 Key", isOn: $removeStoredKey)
                            .tint(.red)
                    }
                }
                Section {
                    Text("API Key 只保存在本机钥匙串，不进入 iCloud；请求由本机直接发往供应商。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(SNColor.muted)
                }
                if originalProvider != nil {
                    Section {
                        Button("删除供应商", role: .destructive) {
                            guard let originalProvider else {
                                return
                            }
                            Task {
                                await model.deleteProvider(originalProvider)
                                dismiss()
                            }
                        }
                    }
                }
            }
            .navigationTitle(originalProvider == nil ? "添加供应商" : "编辑供应商")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "保存中" : "保存") {
                        save()
                    }
                    .disabled(
                        isSaving
                            || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || URL(string: baseURL)?.scheme == nil
                            || modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
        }
    }

    private func save() {
        isSaving = true
        let provider = AIProvider(
            id: originalProvider?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            modelID: modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let keyUpdate: String?
        if removeStoredKey {
            keyUpdate = ""
        } else if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            keyUpdate = nil
        } else {
            keyUpdate = apiKey
        }
        Task {
            await model.saveProvider(provider, apiKey: keyUpdate)
            isSaving = false
            dismiss()
        }
    }
}

struct AISheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var session: ReaderSessionModel
    @Bindable var model: IOSAppModel
    @State private var prompt = ""
    @State private var selectedAction = "解释选中内容"
    @State private var showingWholeMaterialConfirmation = false
    @State private var showingProviderSettings = false
    @State private var hasKey = false

    private let actions = ["解释选中内容", "总结整份材料"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                scopePicker
                Divider()
                conversationBody
                Divider()
                composer
            }
            .background(SNColor.page)
            .navigationTitle("AI 研读")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingProviderSettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("AI 供应商设置")
                }
            }
            .sheet(isPresented: $showingProviderSettings) {
                AIProviderSettingsView(model: model)
            }
            .alert("发送整份材料？", isPresented: $showingWholeMaterialConfirmation) {
                Button("取消", role: .cancel) {}
                Button("确认发送") {
                    Task { await send() }
                }
            } message: {
                Text(
                    "将向 \(session.selectedProvider?.name ?? "供应商") 发送约 \(session.wholeContext.approximateLength) 字。"
                )
            }
            .task {
                await refreshKeyState()
                if session.selectedTextAnchor == nil {
                    selectedAction = "总结整份材料"
                }
                if prompt.isEmpty {
                    prompt = defaultPrompt
                }
            }
            .onChange(of: session.providerID) {
                Task { await refreshKeyState() }
                session.streamError = nil
            }
        }
    }

    private var scopePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("供应商", selection: $session.providerID) {
                    ForEach(session.providers) { provider in
                        Text(provider.name).tag(Optional(provider.id))
                    }
                }
                .pickerStyle(.menu)
                .tint(SNColor.primary)
                Spacer()
                StatusPill(
                    text: hasKey ? "Key 已保存" : "需要 API Key",
                    color: hasKey ? SNColor.green : SNColor.amberInk,
                    background: hasKey ? SNColor.greenSoft : SNColor.amberSoft,
                    systemImage: hasKey ? "checkmark.circle" : "key"
                )
            }
            Picker("动作", selection: $selectedAction) {
                ForEach(actions, id: \.self) { action in
                    Text(action).tag(action)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedAction) {
                prompt = defaultPrompt
            }
            HStack(spacing: 6) {
                Image(systemName: "scope")
                Text(requestContext.scopeDescription)
                Text("·")
                Text("约 \(requestContext.approximateLength) 字")
            }
            .font(.system(size: 10))
            .foregroundStyle(SNColor.muted)
        }
        .padding(14)
        .background(Color.white)
    }

    private var conversationBody: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if session.activeConversation == nil,
                   session.streamingText.isEmpty,
                   !session.conversations.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("历史会话")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(SNColor.muted)
                        ForEach(session.conversations.prefix(5)) { conversation in
                            Button {
                                session.selectConversation(conversation)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(
                                        conversation.messages.first(where: {
                                            $0.role == .user
                                        })?.content ?? conversation.action
                                    )
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(SNColor.ink)
                                    .lineLimit(2)
                                    Text(
                                        "\(conversation.providerName) · \(conversation.updatedAt.formatted(date: .abbreviated, time: .shortened))"
                                    )
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(SNColor.muted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(SNColor.border, lineWidth: 1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 8)
                } else if session.activeConversation == nil,
                          session.streamingText.isEmpty {
                    ContentUnavailableView(
                        "围绕当前材料研读",
                        systemImage: "sparkles",
                        description: Text("先选择发送范围，再发起一次明确请求。")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 32)
                }
                if let conversation = session.activeConversation {
                    ForEach(conversation.messages.filter { !$0.content.isEmpty }) { message in
                        AIMessageRow(message: message)
                    }
                } else if !session.streamingText.isEmpty {
                    AIMessageRow(
                        message: AIMessage(
                            role: .assistant,
                            content: session.streamingText
                        )
                    )
                }
                if session.isStreaming, session.activeConversation != nil {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在生成")
                            .font(.system(size: 10))
                            .foregroundStyle(SNColor.muted)
                    }
                }
                if let error = session.streamError {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("请求失败", systemImage: "exclamationmark.triangle")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(SNColor.amberInk)
                        Text(error)
                            .font(.system(size: 10.5))
                            .foregroundStyle(SNColor.text)
                        HStack {
                            Button("手动重试") {
                                Task { await session.retryAI() }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(SNColor.primary)
                            Button("切换供应商") {
                                showingProviderSettings = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(12)
                    .background(SNColor.amberSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(14)
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            TextField("针对当前研读结果继续追问", text: $prompt, axis: .vertical)
                .lineLimit(2...5)
                .padding(10)
                .background(SNColor.nav)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            HStack {
                if !hasKey {
                    Button("配置 API Key") {
                        showingProviderSettings = true
                    }
                    .font(.system(size: 10.5, weight: .medium))
                }
                Spacer()
                if session.isStreaming {
                    Button("停止") {
                        session.stopAI()
                    }
                    .buttonStyle(.bordered)
                    .tint(SNColor.amberInk)
                } else {
                    Button(primaryActionTitle) {
                        if requestContext.requiresWholeMaterialConfirmation {
                            showingWholeMaterialConfirmation = true
                        } else {
                            Task { await send() }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SNColor.primary)
                    .disabled(
                        !hasKey
                            || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || session.selectedProvider == nil
                    )
                }
            }
        }
        .padding(12)
        .background(Color.white)
    }

    private var requestContext: AIContext {
        if selectedAction == "解释选中内容",
           let context = session.selectedContext() {
            return context
        }
        return session.wholeContext
    }

    private var defaultPrompt: String {
        if selectedAction == "解释选中内容" {
            "请解释这段内容在整篇材料中的含义，并指出关键概念之间的关系。"
        } else {
            "请总结整份材料的核心观点、论证结构和值得继续追问的问题。"
        }
    }

    private var primaryActionTitle: String {
        session.activeConversation == nil ? "发送" : "继续追问"
    }

    private func send() async {
        let action = selectedAction == "解释选中内容" ? "解释" : "总结"
        await session.startAI(
            action: action,
            context: requestContext,
            prompt: prompt
        )
        prompt = ""
    }

    private func refreshKeyState() async {
        hasKey = await session.hasAPIKey()
    }
}

private struct AIMessageRow: View {
    let message: AIMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 44)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(message.role == .user ? "你" : "AI 研读")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(
                            message.role == .user ? SNColor.primary : SNColor.muted
                        )
                    Spacer()
                    if let prompt = message.promptTokens,
                       let completion = message.completionTokens {
                        Text("\(prompt) / \(completion) tokens")
                            .font(.system(size: 8.5))
                            .foregroundStyle(SNColor.muted)
                    }
                }
                Text(message.content)
                    .font(.system(size: 13))
                    .lineSpacing(5)
                    .foregroundStyle(SNColor.ink)
                    .textSelection(.enabled)
            }
            .padding(11)
            .background(
                message.role == .user
                    ? SNColor.primarySoft
                    : Color.white
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(SNColor.border, lineWidth: 1)
            }
            if message.role != .user {
                Spacer(minLength: 44)
            }
        }
    }
}
#endif
