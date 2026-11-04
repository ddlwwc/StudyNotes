import AppKit
import StudyNotesKit
import SwiftUI

struct StudyPanel: View {
    @Bindable var model: WorkspaceModel
    @Environment(\.openSettings) private var openSettings
    @State private var followUpPrompt = ""
    @State private var inlineNote = ""
    @State private var cardHeights: [UUID: CGFloat] = [:]
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

                if model.studyPanelTab == .annotations {
                    Button {
                        model.presentAnnotationForCurrentSelection()
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.readerSelection == nil)
                    .help(
                        model.readerSelection == nil
                            ? "先在正文中选择文字或元素"
                            : "新建标注"
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)

            Rectangle()
                .fill(SNColor.border)
                .frame(height: 1)

            if model.studyPanelTab == .annotations {
                annotationContent
            } else {
                ScrollView {
                    Group {
                        aiContent
                    }
                    .padding(14)
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SNColor.white)
        .background(StudyPanelScrollForwarder())
        .onChange(of: model.inlineAnnotationDraft?.id) { _, _ in
            inlineNote = model.inlineAnnotationDraft?.initialNote ?? ""
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
            .frame(maxHeight: .infinity)
        } else {
            GeometryReader { proxy in
                let placements = StudyAnnotationLayout.positions(
                    annotations: model.annotations,
                    targetY: model.annotationLayoutPositions,
                    cardHeights: cardHeights,
                    availableHeight: proxy.size.height - 8
                )
                ZStack(alignment: .topLeading) {
                    if model.annotations.isEmpty,
                       model.inlineAnnotationDraft == nil {
                        StudyPanelEmptyState(
                            systemImage: "tag",
                            title: "暂无标注",
                            description: "在正文中选择文字或元素，或右键正文创建标注。"
                        )
                        .frame(
                            width: proxy.size.width,
                            height: proxy.size.height
                        )
                    }

                    ForEach(model.annotations) { annotation in
                        annotationView(
                            annotation,
                            isEditing: model.inlineAnnotationDraft?.annotationID
                                == annotation.id
                        )
                        .frame(width: max(0, proxy.size.width - 28))
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: AnnotationCardHeightKey.self,
                                    value: [annotation.id: geometry.size.height]
                                )
                            }
                        }
                        .offset(
                            x: 14,
                            y: displayY(
                                for: annotation,
                                placement: placements[annotation.id],
                                availableHeight: proxy.size.height
                            )
                        )
                        .zIndex(
                            model.annotationJumpID == annotation.id
                                || model.inlineAnnotationDraft?.annotationID == annotation.id
                                ? 2
                                : 1
                        )
                    }

                    if let draft = model.inlineAnnotationDraft,
                       draft.annotationID == nil {
                        InlineAnnotationEditorCard(
                            title: "新建标注",
                            quote: draft.quote,
                            note: $inlineNote,
                            isSaving: model.isPerformingAction,
                            onSave: {
                                Task {
                                    await model.saveInlineAnnotation(note: inlineNote)
                                }
                            },
                            onCancel: {
                                model.cancelInlineAnnotation()
                            }
                        )
                        .frame(width: max(0, proxy.size.width - 28))
                        .offset(
                            x: 14,
                            y: min(
                                max(8, (draft.viewportY ?? 0) - 38),
                                max(8, proxy.size.height - 190)
                            )
                        )
                        .zIndex(3)
                    }
                }
                .onPreferenceChange(AnnotationCardHeightKey.self) {
                    cardHeights = $0
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

    @ViewBuilder
    private func annotationView(
        _ annotation: MaterialAnnotation,
        isEditing: Bool
    ) -> some View {
        if isEditing {
            InlineAnnotationEditorCard(
                title: "编辑标注",
                quote: annotation.quote,
                note: $inlineNote,
                isSaving: model.isPerformingAction,
                onSave: {
                    Task {
                        await model.saveInlineAnnotation(note: inlineNote)
                    }
                },
                onCancel: {
                    model.cancelInlineAnnotation()
                }
            )
        } else {
            AnnotationStudyCard(
                annotation: annotation,
                isCurrent: model.annotationJumpID == annotation.id,
                onOpen: {
                    model.annotationJumpID = annotation.id
                    model.isStudyPanelVisible = true
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

    private func displayY(
        for annotation: MaterialAnnotation,
        placement: CGFloat?,
        availableHeight: CGFloat
    ) -> CGFloat {
        let height = cardHeights[annotation.id] ?? 88
        let readerToPanelOffset: CGFloat = 38
        let proposed = max(8, (placement ?? 0) - readerToPanelOffset)
        return min(proposed, max(8, availableHeight - height - 8))
    }

    private func openAISettings() {
        model.settingsPage = .ai
        openSettings()
    }
}

private struct AnnotationStudyCard: View {
    let annotation: MaterialAnnotation
    let isCurrent: Bool
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(
                    annotation.status == .unresolved
                        ? "位置待恢复"
                        : annotation.anchor.elementType?.title ?? "标注",
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
                    Button(
                        annotation.status == .unresolved ? "重新绑定…" : "编辑…",
                        action: onEdit
                    )
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
                    .lineLimit(annotation.anchor.elementType == nil ? 4 : 2)
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
                    isCurrent
                        ? SNColor.blue
                        : annotation.status == .unresolved
                            ? SNColor.orange
                            : SNColor.yellowLine,
                    style: StrokeStyle(
                        lineWidth: isCurrent ? 2 : 1,
                        dash: annotation.status == .unresolved ? [4, 3] : []
                    )
                )
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }
}

private extension AnnotationElementType {
    var title: String {
        switch self {
        case .heading:
            "标题"
        case .paragraph:
            "段落"
        case .blockquote:
            "引用"
        case .listItem:
            "列表项"
        case .image:
            "图片"
        case .table:
            "表格"
        case .codeBlock:
            "代码块"
        }
    }
}

private struct InlineAnnotationEditorCard: View {
    let title: String
    let quote: String
    @Binding var note: String
    let isSaving: Bool
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.sn(9, weight: .medium))
                .foregroundStyle(SNColor.blue)

            if !quote.isEmpty {
                Text("“\(quote)”")
                    .font(.snReading(11))
                    .foregroundStyle(SNColor.text)
                    .lineLimit(2)
            }

            TextField("写下备注", text: $note, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.sn(10))
                .lineLimit(3...6)
                .padding(7)
                .background(SNColor.white)
                .clipShape(RoundedRectangle(cornerRadius: SNRadius.small))
                .overlay {
                    RoundedRectangle(cornerRadius: SNRadius.small)
                        .stroke(SNColor.yellowLine, lineWidth: 1)
                }

            HStack {
                Button("取消", action: onCancel)
                    .buttonStyle(.plain)
                    .foregroundStyle(SNColor.muted)
                Spacer()
                Button(action: onSave) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Text("保存")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(SNColor.blue)
                .controlSize(.small)
                .disabled(isSaving)
            }
        }
        .padding(10)
        .background(SNColor.yellow)
        .clipShape(RoundedRectangle(cornerRadius: SNRadius.control))
        .overlay {
            RoundedRectangle(cornerRadius: SNRadius.control)
                .stroke(SNColor.yellowLine, lineWidth: 1)
        }
    }
}

private struct AnnotationCardHeightKey: PreferenceKey {
    static let defaultValue: [UUID: CGFloat] = [:]

    static func reduce(
        value: inout [UUID: CGFloat],
        nextValue: () -> [UUID: CGFloat]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

private struct StudyPanelScrollForwarder: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.view = view
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.view = nsView
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.remove()
    }

    final class Coordinator: @unchecked Sendable {
        weak var view: NSView?
        private var monitor: Any?

        func install() {
            guard monitor == nil else {
                return
            }
            monitor = NSEvent.addLocalMonitorForEvents(
                matching: .scrollWheel
            ) { [weak self] event in
                let delta = event.scrollingDeltaY
                let location = event.locationInWindow
                let windowNumber = event.windowNumber
                Task { @MainActor [weak self] in
                    guard let self,
                          let view = self.view,
                          view.window?.windowNumber == windowNumber,
                          !(view.window?.firstResponder is NSTextView) else {
                        return
                    }
                    let location = view.convert(
                        location,
                        from: nil
                    )
                    guard view.bounds.contains(location) else {
                        return
                    }
                    NotificationCenter.default.post(
                        name: .studyNotesReaderScroll,
                        object: delta
                    )
                }
                return event
            }
        }

        func remove() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }
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
