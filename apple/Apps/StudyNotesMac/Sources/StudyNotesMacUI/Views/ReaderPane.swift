import StudyNotesKit
import SwiftUI

struct ReaderPane: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        VStack(spacing: 0) {
            if model.isConnected {
                ReaderTopBar(model: model)
            }

            Group {
                if let document = model.selectedDocument {
                    MaterialReaderView(model: model, document: document)
                } else {
                    emptyContent
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SNColor.white)
    }

    @ViewBuilder
    private var emptyContent: some View {
        switch model.connectionState {
        case .restoring, .connecting:
            VStack(spacing: 12) {
                ProgressView()
                Text(model.connectionLabel)
                    .font(.sn(12))
                    .foregroundStyle(SNColor.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(message):
            ReaderWelcomeView(
                model: model,
                failureMessage: message
            )
        case .disconnected:
            ReaderWelcomeView(
                model: model,
                failureMessage: nil
            )
        case .connected:
            ReaderConnectedEmptyView(model: model)
        }
    }

    private func knowledgeBaseName(for id: UUID?) -> String {
        guard let id else {
            return "收件箱"
        }
        return model.knowledgeBases.first { $0.id == id }?.name ?? "知识库"
    }
}

private struct ReaderTopBar: View {
    @Bindable var model: WorkspaceModel
    @State private var showingOutline = false
    @State private var showingSearch = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "books.vertical")
                .font(.system(size: 12))
                .foregroundStyle(SNColor.muted)

            Text(breadcrumb)
                .font(.sn(11))
                .foregroundStyle(SNColor.text)
                .lineLimit(1)

            Spacer(minLength: 12)

            ReaderToolButton(
                title: "目录",
                systemImage: "list.bullet.rectangle",
                isEnabled: !(model.selectedDocument?.headings.isEmpty ?? true),
                help: "目录"
            ) {
                showingOutline.toggle()
            }
            .popover(isPresented: $showingOutline, arrowEdge: .bottom) {
                outlinePopover
            }

            ReaderToolButton(
                title: "搜索",
                systemImage: "magnifyingglass",
                isEnabled: model.selectedDocument != nil,
                help: "文档内搜索"
            ) {
                showingSearch.toggle()
            }
            .popover(isPresented: $showingSearch, arrowEdge: .bottom) {
                searchPopover
            }

            ReaderToolButton(
                title: model.isEditingMarkdown ? "完成编辑" : "编辑",
                systemImage: model.isEditingMarkdown
                    ? "checkmark.circle"
                    : "square.and.pencil",
                isEnabled: model.selectedDocument?.summary.kind == .note
                    || model.selectedDocument?.summary.kind == .markdown,
                help: model.isEditingMarkdown
                    ? "保存并结束编辑（⌘E）"
                    : "在阅读区编辑（⌘E）"
            ) {
                Task {
                    await model.toggleMarkdownEditing()
                }
            }
            .keyboardShortcut("e", modifiers: .command)

            ReaderToolButton(
                title: "版本",
                systemImage: "clock.arrow.circlepath",
                isEnabled: model.selectedDocument?.summary.kind.isTextDocument == true,
                help: "查看最近 10 个文字版本"
            ) {
                Task {
                    await model.loadRevisions()
                    model.isShowingVersions = true
                }
            }

            if let selection = model.readerSelection,
               !selection.quote.isEmpty || selection.rect != nil {
                ReaderToolButton(
                    title: "标注选段",
                    systemImage: "highlighter",
                    isEnabled: true,
                    help: "创建或更新当前选区的标注"
                ) {
                    model.presentAnnotationForCurrentSelection()
                }

                if !selection.quote.isEmpty {
                    ReaderToolButton(
                        title: "AI 解释",
                        systemImage: "sparkles",
                        isEnabled: model.canExplainSelection,
                        help: model.canExplainSelection
                            ? "确认后向所选 AI 供应商发送选段"
                            : "请先配置 AI 供应商"
                    ) {
                        model.prepareSelectionExplanation()
                    }
                }
            }

            Rectangle()
                .fill(SNColor.border)
                .frame(width: 1, height: 20)
                .padding(.horizontal, 2)

            ReaderToolButton(
                title: model.isStudyPanelVisible ? "收起研读层" : "显示研读层",
                systemImage: "sidebar.right",
                isEnabled: model.selectedDocument != nil,
                help: model.isStudyPanelVisible ? "收起研读层" : "显示研读层"
            ) {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                    model.isStudyPanelVisible.toggle()
                }
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
        .background(SNColor.white)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SNColor.border)
                .frame(height: 1)
        }
    }

    private var breadcrumb: String {
        if let document = model.selectedDocument {
            let knowledgeBase = model.knowledgeBases.first {
                $0.id == document.summary.knowledgeBaseID
            }
            if document.summary.deletedAt != nil {
                return "回收站 / \(document.summary.title)"
            }
            return "\(knowledgeBase?.name ?? "收件箱") / \(document.summary.title)"
        }
        return model.scopeTitle
    }

    private var outlinePopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("目录")
                .font(.sn(12, weight: .semibold))
                .foregroundStyle(SNColor.ink)
                .padding(12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(model.selectedDocument?.headings ?? []) { heading in
                        HStack(spacing: 4) {
                            Button {
                                model.readerHeadingJumpID = heading.id
                                showingOutline = false
                            } label: {
                                Text(heading.title)
                                    .font(.sn(11))
                                    .foregroundStyle(SNColor.text)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.leading, CGFloat(max(0, heading.level - 1)) * 12)
                                    .padding(.vertical, 6)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Button {
                                model.prepareSectionSummary(heading: heading)
                                showingOutline = false
                            } label: {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 10))
                                    .foregroundStyle(SNColor.blue)
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.plain)
                            .disabled(model.selectedProvider == nil)
                            .help("总结本节")
                        }
                    }
                }
                .padding(8)
            }
        }
        .frame(width: 280, height: 340)
    }

    private var searchPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("文内搜索")
                .font(.sn(12, weight: .semibold))
                .foregroundStyle(SNColor.ink)

            TextField("输入关键词", text: $model.documentSearchText)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    model.documentSearchText += " "
                }

            Text("搜索只作用于当前阅读视图，不会创建标注或修改原文。")
                .font(.sn(9))
                .foregroundStyle(SNColor.muted)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("关闭") {
                    model.documentSearchText = ""
                    showingSearch = false
                }
            }
        }
        .padding(14)
        .frame(width: 300)
    }
}

private struct ReaderToolButton: View {
    let title: String
    let systemImage: String
    var isEnabled = true
    var help: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 11))
                Text(title)
                    .font(.sn(10))
            }
            .foregroundStyle(SNColor.text)
            .padding(.horizontal, 6)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
        .help(help ?? title)
        .accessibilityLabel(title)
    }
}

private struct ReaderDocumentView: View {
    let note: MarkdownNote
    let knowledgeBaseName: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(note.summary.title)
                    .font(.sn(30, weight: .semibold))
                    .foregroundStyle(SNColor.ink)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Text("Markdown 笔记")
                    Text("·")
                    Text("更新于 \(WorkspaceFormatting.updatedDate(note.summary.updatedAt))")
                    Text("·")
                    Text(knowledgeBaseName)
                    if !note.summary.folderPath.isEmpty {
                        Text("·")
                        Text(WorkspaceFormatting.folderPathDisplay(note.summary.folderPath))
                    }
                    if let deletedAt = note.summary.deletedAt {
                        Text("·")
                        Text("删除于 \(WorkspaceFormatting.updatedDate(deletedAt))")
                            .foregroundStyle(SNColor.red)
                    }
                }
                .font(.sn(11))
                .foregroundStyle(SNColor.muted)
                .padding(.top, 8)

                if !note.summary.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            ForEach(note.summary.tags, id: \.self) { tag in
                                Text("# \(tag)")
                                    .font(.sn(9, weight: .medium))
                                    .foregroundStyle(SNColor.blue)
                                    .padding(.horizontal, 7)
                                    .frame(height: 22)
                                    .background(SNColor.blueSoft)
                                    .clipShape(RoundedRectangle(cornerRadius: SNRadius.small))
                            }
                        }
                    }
                    .padding(.top, 10)
                }

                Rectangle()
                    .fill(SNColor.border)
                    .frame(height: 1)
                    .padding(.vertical, 22)

                if !note.summary.conflictCopies.isEmpty {
                    ConflictCopyNotice(copies: note.summary.conflictCopies)
                        .padding(.bottom, 22)
                }

                if bodyMarkdown.isEmpty {
                    Text("这篇笔记还没有正文。")
                        .font(.snReading(16))
                        .foregroundStyle(SNColor.muted)
                        .padding(.vertical, 30)
                } else {
                    MarkdownRenderer(markdown: bodyMarkdown)
                }
            }
            .frame(maxWidth: 648, alignment: .leading)
            .padding(.horizontal, 36)
            .padding(.top, 30)
            .padding(.bottom, 56)
            .frame(maxWidth: .infinity)
        }
    }

    private var bodyMarkdown: String {
        let lines = note.markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        guard let firstContentIndex = lines.firstIndex(where: {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }) else {
            return ""
        }

        let firstLine = lines[firstContentIndex].trimmingCharacters(in: .whitespaces)
        if firstLine == "# \(note.summary.title)" {
            return lines.dropFirst(firstContentIndex + 1).joined(separator: "\n")
        }
        return note.markdown
    }
}

private struct ConflictCopyNotice: View {
    let copies: [ConflictCopy]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("发现 \(copies.count) 个冲突副本", systemImage: "exclamationmark.triangle.fill")
                .font(.sn(11, weight: .semibold))
                .foregroundStyle(SNColor.red)

            Text("当前正文来自主学习材料包，以下副本会保留在原地，等待你手动核对。")
                .font(.sn(10))
                .foregroundStyle(SNColor.text)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(copies) { copy in
                Text(copy.displayName)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(SNColor.text)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SNColor.redSoft)
        .clipShape(RoundedRectangle(cornerRadius: SNRadius.control))
        .overlay {
            RoundedRectangle(cornerRadius: SNRadius.control)
                .stroke(SNColor.red.opacity(0.25), lineWidth: 1)
        }
    }
}

private struct ReaderWelcomeView: View {
    @Bindable var model: WorkspaceModel
    let failureMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: SNRadius.panel)
                            .fill(SNColor.blueSoft)
                        Image(systemName: "folder.badge.gearshape")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(SNColor.blue)
                    }
                    .frame(width: 54, height: 54)

                    Text("连接你的学习目录")
                        .font(.sn(24, weight: .semibold))
                        .foregroundStyle(SNColor.ink)

                    Text("选择一个本地或 iCloud Drive 文件夹。StudyNotes 会读取其中已有的知识库与 Markdown 笔记。")
                        .font(.sn(12))
                        .foregroundStyle(SNColor.text)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                    if let failureMessage {
                        Text(failureMessage)
                            .font(.sn(11))
                            .foregroundStyle(SNColor.red)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(SNColor.redSoft)
                            .clipShape(RoundedRectangle(cornerRadius: SNRadius.control))
                    }

                    HStack(spacing: 10) {
                        Button {
                            Task {
                                await model.chooseICloudWorkspace()
                            }
                        } label: {
                            Label("使用 iCloud Drive", systemImage: "icloud")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(SNColor.blue)
                        .disabled(model.isPerformingAction)

                        Button {
                            Task {
                                await model.chooseWorkspace()
                            }
                        } label: {
                            Label("选择其它目录", systemImage: "folder.badge.plus")
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.isPerformingAction)
                    }
                    .controlSize(.large)
                }
                .padding(.vertical, 36)
            }
            .frame(maxWidth: 648, alignment: .leading)
            .padding(.horizontal, 36)
            .padding(.top, 28)
            .padding(.bottom, 56)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct ReaderConnectedEmptyView: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: model.knowledgeBases.isEmpty ? "books.vertical" : "doc.text")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(SNColor.muted)

            Text(model.knowledgeBases.isEmpty ? "先创建一个知识库" : "选择一篇笔记开始阅读")
                .font(.sn(16, weight: .medium))
                .foregroundStyle(SNColor.ink)

            Text(
                model.knowledgeBases.isEmpty
                    ? "学习目录已连接，但其中还没有知识库。"
                    : "从左侧材料列表选择笔记，或创建一篇新的 Markdown 笔记。"
            )
            .font(.sn(11))
            .foregroundStyle(SNColor.muted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 360)

            if model.knowledgeBases.isEmpty {
                Button("新建知识库") {
                    model.presentCreateKnowledgeBaseSheet()
                }
                .buttonStyle(.borderedProminent)
                .tint(SNColor.blue)
                .controlSize(.large)
            } else if model.canCreateNote {
                Button("新建 Markdown 笔记") {
                    model.presentCreateNoteSheet()
                }
                .buttonStyle(.borderedProminent)
                .tint(SNColor.blue)
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
}
