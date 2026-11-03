import SwiftUI
import StudyNotesKit

struct StudyPanel: View {
    @Bindable var model: WorkspaceModel
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var followUpPrompt = ""
    @State private var conversationToRename: AIConversation?
    @State private var conversationName = ""
    @State private var isRenamingConversation = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("研读层")
                    .font(.sn(15, weight: .semibold))
                    .foregroundStyle(SNColor.ink)

                Spacer()

                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                        model.isStudyPanelVisible = false
                    }
                } label: {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 13))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(SNColor.muted)
                .help("收起研读层")
                .accessibilityLabel("收起研读层")
            }
            .padding(.horizontal, 14)
            .frame(height: 52)

            Rectangle()
                .fill(SNColor.border)
                .frame(height: 1)

            HStack(spacing: 18) {
                ForEach(StudyPanelTab.allCases) { tab in
                    Button {
                        model.studyPanelTab = tab
                    } label: {
                        VStack(spacing: 7) {
                            Text(tab.title)
                                .font(.sn(11, weight: model.studyPanelTab == tab ? .medium : .regular))
                                .foregroundStyle(model.studyPanelTab == tab ? SNColor.ink : SNColor.muted)

                            Rectangle()
                                .fill(model.studyPanelTab == tab ? SNColor.blue : Color.clear)
                                .frame(height: 2)
                                .clipShape(RoundedRectangle(cornerRadius: 1))
                        }
                        .frame(minWidth: 42)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.title)
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)

            Rectangle()
                .fill(SNColor.border)
                .frame(height: 1)

            ScrollView {
                Group {
                    if model.studyPanelTab == .annotations {
                        annotationContent
                    } else {
                        aiContent
                    }
                }
                .padding(14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SNColor.panel)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(SNColor.border)
                .frame(width: 1)
        }
        .alert("重命名 AI 研读会话", isPresented: $isRenamingConversation) {
            TextField("会话名称", text: $conversationName)
            Button("取消", role: .cancel) {}
            Button("保存") {
                guard let conversationToRename else {
                    return
                }
                Task {
                    await model.renameConversation(
                        conversationToRename,
                        title: conversationName
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var annotationContent: some View {
        if model.selectedDocument == nil {
            StudyPanelEmptyState(
                systemImage: "text.badge.xmark",
                title: "未打开材料",
                description: "选择学习材料后查看对应标注。"
            )
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text("\(model.annotations.count) 条标注")
                        .font(.sn(10, weight: .medium))
                        .foregroundStyle(SNColor.text)

                    Spacer()

                    Button {
                        model.presentAnnotationForCurrentSelection()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .disabled(model.readerSelection == nil)
                    .help(model.readerSelection == nil ? "先在正文中选择文字或区域" : "新建标注")

                    Button {
                        model.isShowingLinkMaterials = true
                    } label: {
                        Image(systemName: "link")
                    }
                    .buttonStyle(.plain)
                    .help("关联学习材料")
                }

                if let document = model.selectedDocument,
                   !document.summary.linkedMaterialIDs.isEmpty {
                    LinkedMaterialsSummary(document: document, model: model)
                }

                if model.annotations.isEmpty {
                    StudyPanelEmptyState(
                        systemImage: "tag",
                        title: "暂无标注",
                        description: "在正文中选择文字，或在 PDF、图片中选择区域。"
                    )
                } else {
                    ForEach(model.annotations) { annotation in
                        AnnotationStudyCard(
                            annotation: annotation,
                            onOpen: {
                                model.annotationJumpID = annotation.id
                            },
                            onEdit: {
                                model.presentAnnotationEditor(for: annotation)
                            },
                            onDelete: {
                                Task {
                                    await model.deleteAnnotation(annotation)
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    private var aiContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                if let provider = model.selectedProvider {
                    Label(provider.name, systemImage: "sparkles")
                        .font(.sn(10, weight: .medium))
                        .foregroundStyle(SNColor.blue)
                } else {
                    Text("未配置供应商")
                        .font(.sn(10, weight: .medium))
                        .foregroundStyle(SNColor.muted)
                }

                Spacer()

                Button {
                    openAISettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .help("AI 供应商设置")
            }

            if model.providerProfiles.isEmpty {
                StudyPanelEmptyState(
                    systemImage: "key",
                    title: "配置 AI 供应商",
                    description: "API Key 只保存在 Apple 钥匙串。"
                )
                Button("打开供应商设置") {
                    openAISettings()
                }
                .buttonStyle(.borderedProminent)
                .tint(SNColor.blue)
                .controlSize(.small)
            } else {
                HStack(spacing: 6) {
                    Button {
                        model.prepareMaterialSummary()
                    } label: {
                        Label("整篇总结", systemImage: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if model.readerSelection?.quote.isEmpty == false {
                        Button {
                            model.prepareSelectionExplanation()
                        } label: {
                            Label("解释选段", systemImage: "text.quote")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(SNColor.blue)
                        .controlSize(.small)
                    }
                }

                if let conversation = model.activeConversation {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(conversation.title)
                                .font(.sn(11, weight: .medium))
                                .foregroundStyle(SNColor.ink)
                                .lineLimit(2)
                            Spacer()
                            Menu {
                                Button("重命名…") {
                                    conversationToRename = conversation
                                    conversationName = conversation.title
                                    isRenamingConversation = true
                                }
                                Button("删除", role: .destructive) {
                                    Task {
                                        await model.deleteConversation(conversation)
                                    }
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                            }
                            .menuStyle(.borderlessButton)
                            .frame(width: 24)
                        }

                        ForEach(conversation.messages.filter { $0.role != .system }) { message in
                            AIMessageBubble(
                                message: message,
                                conversation: conversation,
                                model: model
                            )
                        }

                        if !model.aiStreamingText.isEmpty {
                            Text(model.aiStreamingText)
                                .font(.sn(10))
                                .foregroundStyle(SNColor.text)
                                .lineSpacing(3)
                                .padding(9)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(SNColor.purpleSoft)
                                .clipShape(RoundedRectangle(cornerRadius: SNRadius.control))
                        }

                        switch model.aiPhase {
                        case .streaming:
                            Button {
                                model.stopAIStream()
                            } label: {
                                Label("停止生成", systemImage: "stop.circle.fill")
                            }
                            .buttonStyle(.bordered)
                            .tint(SNColor.red)
                            .controlSize(.small)
                        case .stopped:
                            Text("已停止。已收到的内容会保留在会话中。")
                                .font(.sn(9))
                                .foregroundStyle(SNColor.orange)
                        case let .failed(message):
                            VStack(alignment: .leading, spacing: 6) {
                                Text(message)
                                    .font(.sn(9))
                                    .foregroundStyle(SNColor.red)
                                    .fixedSize(horizontal: false, vertical: true)
                                Button {
                                    model.retryActiveAIRequest()
                                } label: {
                                    Label("手动重试", systemImage: "arrow.clockwise")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        case .idle:
                            EmptyView()
                        }
                    }
                    .padding(10)
                    .background(SNColor.white)
                    .clipShape(RoundedRectangle(cornerRadius: SNRadius.control))
                    .overlay {
                        RoundedRectangle(cornerRadius: SNRadius.control)
                            .stroke(SNColor.border, lineWidth: 1)
                    }
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text(model.activeConversation == nil ? "选择一段选中文字发起解释，或总结整篇材料。" : "继续追问")
                        .font(.sn(9))
                        .foregroundStyle(SNColor.muted)
                    TextField("输入问题", text: $followUpPrompt, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.sn(11))
                        .lineLimit(2...4)
                        .padding(8)
                        .background(SNColor.white)
                        .clipShape(RoundedRectangle(cornerRadius: SNRadius.control))
                        .overlay {
                            RoundedRectangle(cornerRadius: SNRadius.control)
                                .stroke(SNColor.border, lineWidth: 1)
                        }

                    Button {
                        if model.activeConversation != nil {
                            model.continueAIConversation(prompt: followUpPrompt)
                        } else {
                            model.aiPromptText = followUpPrompt
                            model.prepareMaterialSummary()
                        }
                        followUpPrompt = ""
                    } label: {
                        Label("发送", systemImage: "arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SNColor.blue)
                    .controlSize(.small)
                    .disabled(
                        followUpPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || model.aiPhase.isStreaming
                            || model.selectedProvider == nil
                    )
                }
            }
        }
    }

    private func openAISettings() {
        model.settingsPage = .ai
        openSettings()
    }
}

private struct AnnotationStudyCard: View {
    let annotation: MaterialAnnotation
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(
                    annotation.status == .unresolved ? "位置待恢复" : "标注",
                    systemImage: annotation.status == .unresolved
                        ? "exclamationmark.triangle"
                        : "highlighter"
                )
                .font(.sn(9, weight: .medium))
                .foregroundStyle(
                    annotation.status == .unresolved ? SNColor.orange : SNColor.blue
                )
                Spacer()
                Menu {
                    Button("定位原文", action: onOpen)
                    Button("编辑…", action: onEdit)
                    Button("删除", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 22)
            }

            if !annotation.quote.isEmpty {
                Text("“\(annotation.quote)”")
                    .font(.snReading(12))
                    .foregroundStyle(SNColor.text)
                    .lineSpacing(3)
                    .lineLimit(4)
            }

            if !annotation.note.isEmpty {
                Text(annotation.note)
                    .font(.sn(10))
                    .foregroundStyle(SNColor.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(annotation.status == .unresolved ? SNColor.orangeSoft : SNColor.yellow)
        .clipShape(RoundedRectangle(cornerRadius: SNRadius.control))
        .overlay {
            RoundedRectangle(cornerRadius: SNRadius.control)
                .stroke(
                    annotation.status == .unresolved ? SNColor.orange : SNColor.yellowLine,
                    lineWidth: 1
                )
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }
}

private struct LinkedMaterialsSummary: View {
    let document: MaterialDocument
    let model: WorkspaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("关联材料", systemImage: "link")
                .font(.sn(9, weight: .medium))
                .foregroundStyle(SNColor.muted)

            ForEach(linkedMaterials) { material in
                Button {
                    Task {
                        await model.selectMaterial(material.id)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: material.kind.systemImage)
                            .font(.system(size: 9))
                        Text(material.title)
                            .font(.sn(9))
                            .lineLimit(1)
                        Spacer()
                    }
                    .foregroundStyle(SNColor.blue)
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var linkedMaterials: [StudyMaterialSummary] {
        let ids = Set(document.summary.linkedMaterialIDs)
        return model.allActiveMaterials.filter { ids.contains($0.id) }
    }
}

private struct AIMessageBubble: View {
    let message: AIMessage
    let conversation: AIConversation
    let model: WorkspaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.role == .user ? "你" : "AI")
                .font(.sn(8, weight: .medium))
                .foregroundStyle(SNColor.muted)
            Text(message.content)
                .font(.sn(10))
                .foregroundStyle(SNColor.text)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(message.role == .user ? SNColor.nav : SNColor.purpleSoft)
        .clipShape(RoundedRectangle(cornerRadius: SNRadius.control))
        .contextMenu {
            if message.role == .assistant {
                ForEach(
                    AIPromotionTarget.allCases.filter {
                        $0 != .annotation || conversation.originAnchor != nil
                    }
                ) { target in
                    Button(target.title) {
                        Task {
                            await model.promoteConversationMessage(
                                conversation,
                                message: message,
                                target: target
                            )
                        }
                    }
                }
            }
        }
    }
}
private struct StudyPanelEmptyState: View {
    let systemImage: String
    let title: String
    let description: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(SNColor.muted)
            Text(title)
                .font(.sn(11, weight: .medium))
                .foregroundStyle(SNColor.text)
                .multilineTextAlignment(.center)
            Text(description)
                .font(.sn(9))
                .foregroundStyle(SNColor.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }
}
