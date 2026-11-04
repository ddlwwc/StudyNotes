import Foundation
import StudyNotesKit
import SwiftUI

struct AIConfigurationSettingsPage: View {
    @Bindable var model: WorkspaceModel
    @State private var profilePendingDeletion: AIProviderProfile?
    @State private var isConfirmingDeletion = false

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("AI 配置")
                            .font(.sn(22, weight: .semibold))
                            .foregroundStyle(SNColor.ink)
                        Text("AI 请求由本机直连所选供应商；API Key 只保存在 macOS 钥匙串。")
                            .font(.sn(10))
                            .foregroundStyle(SNColor.muted)
                    }

                    HStack(alignment: .top, spacing: 14) {
                        providerList
                            .frame(
                                minWidth: 220,
                                idealWidth: 250,
                                maxWidth: 280,
                                alignment: .top
                            )
                            .frame(maxHeight: .infinity, alignment: .top)

                        providerEditor
                            .frame(
                                minWidth: 340,
                                maxWidth: .infinity,
                                alignment: .top
                            )
                            .frame(maxHeight: .infinity, alignment: .top)
                    }
                    .frame(
                        minHeight: max(430, geometry.size.height - 112),
                        alignment: .top
                    )

                    Spacer(minLength: 0)
                }
                .padding(22)
                .frame(maxWidth: 1_100, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SNColor.panel)
        .confirmationDialog(
            "删除供应商“\(profilePendingDeletion?.name ?? "")”？",
            isPresented: $isConfirmingDeletion,
            presenting: profilePendingDeletion
        ) { profile in
            Button("删除供应商和对应 Key", role: .destructive) {
                model.deleteProviderProfile(profile)
            }
            Button("取消", role: .cancel) {}
        } message: { profile in
            Text("“\(profile.name)”的配置会从本机删除，钥匙串中的 API Key 也会一并移除。")
        }
    }

    private var providerList: some View {
        AIProviderPanel("供应商") {
            HStack {
                Text("\(model.providerProfiles.count) 个配置")
                    .font(.sn(9))
                    .foregroundStyle(SNColor.muted)
                Spacer()
                Button {
                    model.requestNewAIProviderDraft()
                } label: {
                    Label("新增", systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("新增供应商")
                .accessibilityLabel("新增供应商")
            }

            if model.providerProfiles.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(SNColor.blue)
                    Text("还没有 AI 供应商")
                        .font(.sn(11, weight: .medium))
                        .foregroundStyle(SNColor.ink)
                    Text("添加一个 OpenAI 兼容供应商后即可开始 AI 研读。")
                        .font(.sn(9))
                        .foregroundStyle(SNColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("新增供应商") {
                        model.requestNewAIProviderDraft()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SNColor.blue)
                }
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 5) {
                    ForEach(model.providerProfiles) { profile in
                        providerRow(profile)
                    }
                }
            }
        }
    }

    private func providerRow(_ profile: AIProviderProfile) -> some View {
        let isEditing = model.providerEditingID == profile.id
        let isDefault = model.defaultProviderID == profile.id
        let hasKey = model.hasAPIKey(for: profile)

        return Button {
            model.requestEditProvider(profile.id)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(profile.name)
                        .font(.sn(11, weight: .medium))
                        .foregroundStyle(SNColor.ink)
                        .lineLimit(1)
                    if isDefault {
                        Text("默认")
                            .font(.sn(8, weight: .medium))
                            .foregroundStyle(SNColor.blue)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(SNColor.blueSoft)
                            .clipShape(Capsule())
                    }
                    Spacer(minLength: 0)
                    if isEditing {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(SNColor.blue)
                    }
                }

                Text(profile.model)
                    .font(.sn(9))
                    .foregroundStyle(SNColor.text)
                    .lineLimit(1)

                Text(baseURLSummary(profile.baseURL))
                    .font(.sn(8))
                    .foregroundStyle(SNColor.muted)
                    .lineLimit(1)

                Label(
                    hasKey ? "Key 已在钥匙串" : "缺少 Key",
                    systemImage: hasKey ? "checkmark.shield" : "key.slash"
                )
                .font(.sn(8))
                .foregroundStyle(hasKey ? SNColor.green : SNColor.orange)
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(isEditing ? SNColor.blueSoft : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: SNRadius.control))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(profile.name)，\(profile.model)，\(hasKey ? "Key 已在钥匙串" : "缺少 Key")"
        )
    }

    @ViewBuilder
    private var providerEditor: some View {
        if model.providerProfiles.isEmpty && !model.isCreatingAIProviderDraft {
            AIProviderPanel("供应商详情") {
                VStack(spacing: 10) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(SNColor.muted)
                    Text("选择一个供应商，或创建一个新配置。")
                        .font(.sn(10))
                        .foregroundStyle(SNColor.muted)
                    Button("新增供应商") {
                        model.requestNewAIProviderDraft()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SNColor.blue)
                }
                .frame(maxWidth: .infinity, minHeight: 430)
            }
        } else {
            AIProviderPanel(
                model.isCreatingAIProviderDraft ? "新增供应商" : "供应商详情"
            ) {
                editorHeader

                AIProviderFieldLabel("名称")
                TextField("例如：主力模型", text: $model.providerDraftName)
                    .textFieldStyle(.roundedBorder)

                AIProviderFieldLabel("基础地址")
                TextField(
                    "https://api.openai.com/v1",
                    text: $model.providerDraftBaseURLText
                )
                .textFieldStyle(.roundedBorder)

                AIProviderFieldLabel("模型标识")
                TextField("例如：gpt-4.1-mini", text: $model.providerDraftModel)
                    .textFieldStyle(.roundedBorder)

                AIProviderFieldLabel("API Key")
                SecureField(
                    model.providerEditingID == nil
                        ? "输入 API Key"
                        : "留空则保留原 Key",
                    text: $model.providerDraftAPIKey
                )
                .textFieldStyle(.roundedBorder)

                if let profile = editingProfile {
                    Label(
                        model.hasAPIKey(for: profile)
                            ? "钥匙串中已有 Key"
                            : "钥匙串中没有 Key",
                        systemImage: model.hasAPIKey(for: profile)
                            ? "checkmark.shield"
                            : "key.slash"
                    )
                    .font(.sn(9))
                    .foregroundStyle(SNColor.muted)
                }

                HStack(spacing: 10) {
                    if model.hasUnsavedAIProviderChanges {
                        Label("有未保存修改", systemImage: "circle.fill")
                            .font(.sn(9, weight: .medium))
                            .foregroundStyle(SNColor.orange)
                    }
                    Spacer()
                    Button("保存供应商") {
                        model.saveAIProviderDraft()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SNColor.blue)
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        model.providerDraftName.isEmpty
                            || model.providerDraftModel.isEmpty
                            || model.providerDraftBaseURLText.isEmpty
                    )
                }
                .padding(.top, 4)

                if let profile = editingProfile {
                    Divider()

                    HStack {
                        Button("清除已保存 Key", role: .destructive) {
                            model.clearProviderAPIKey(profile)
                        }
                        .disabled(!model.hasAPIKey(for: profile))

                        Button("删除供应商", role: .destructive) {
                            profilePendingDeletion = profile
                            isConfirmingDeletion = true
                        }

                        Spacer()
                    }
                    .buttonStyle(.bordered)
                }

                if let notice = model.actionNotice {
                    Text(notice)
                        .font(.sn(9))
                        .foregroundStyle(SNColor.muted)
                }
            }
        }
    }

    private var editorHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(
                model.isCreatingAIProviderDraft
                    ? "新建配置"
                    : model.providerDraftName.isEmpty
                        ? "配置详情"
                        : model.providerDraftName
            )
            .font(.sn(12, weight: .medium))
            .foregroundStyle(SNColor.ink)
            .lineLimit(1)

            if model.providerEditingID == model.defaultProviderID,
               model.providerEditingID != nil {
                Text("默认供应商")
                    .font(.sn(8, weight: .medium))
                    .foregroundStyle(SNColor.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(SNColor.blueSoft)
                    .clipShape(Capsule())
            }

            Spacer()

            if let id = model.providerEditingID,
               id != model.defaultProviderID {
                Button("设为默认") {
                    model.setDefaultAIProvider(id)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var editingProfile: AIProviderProfile? {
        guard let id = model.providerEditingID else {
            return nil
        }
        return model.providerProfiles.first { $0.id == id }
    }

    private func baseURLSummary(_ url: URL) -> String {
        guard let host = url.host else {
            return url.absoluteString
        }
        let path = url.path == "/" ? "" : url.path
        return host + path
    }
}

private struct AIProviderPanel<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 11) {
                content
            }
            .font(.sn(10))
            .frame(
                maxWidth: .infinity,
                minHeight: 430,
                maxHeight: .infinity,
                alignment: .topLeading
            )
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct AIProviderFieldLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.sn(9, weight: .medium))
            .foregroundStyle(SNColor.muted)
    }
}
