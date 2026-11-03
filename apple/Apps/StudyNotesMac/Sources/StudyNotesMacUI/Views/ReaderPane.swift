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
                if let note = model.selectedNote {
                    ReaderDocumentView(
                        note: note,
                        knowledgeBaseName: knowledgeBaseName(for: note.summary.knowledgeBaseID)
                    )
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

    private func knowledgeBaseName(for id: UUID) -> String {
        model.knowledgeBases.first { $0.id == id }?.name ?? "知识库"
    }
}

private struct ReaderTopBar: View {
    @Bindable var model: WorkspaceModel

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
                isEnabled: false,
                help: "目录功能尚未接入"
            ) {}

            ReaderToolButton(
                title: "搜索",
                systemImage: "magnifyingglass",
                isEnabled: false,
                help: "文档内搜索尚未接入"
            ) {}

            ReaderToolButton(
                title: "编辑副本",
                systemImage: "square.and.pencil",
                isEnabled: false,
                help: "阅读副本编辑尚未接入"
            ) {}

            Rectangle()
                .fill(SNColor.border)
                .frame(width: 1, height: 20)
                .padding(.horizontal, 2)

            ReaderToolButton(
                title: model.isStudyPanelVisible ? "收起研读层" : "显示研读层",
                systemImage: "sidebar.right",
                isEnabled: model.selectedNote != nil,
                help: model.isStudyPanelVisible ? "收起研读层" : "显示研读层"
            ) {
                withAnimation(.easeInOut(duration: 0.18)) {
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
        if let note = model.selectedNote {
            let knowledgeBase = model.knowledgeBases.first {
                $0.id == note.summary.knowledgeBaseID
            }
            return "\(knowledgeBase?.name ?? "知识库") / \(note.summary.title)"
        }
        return model.selectedKnowledgeBase?.name ?? "阅读"
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
                }
                .font(.sn(11))
                .foregroundStyle(SNColor.muted)
                .padding(.top, 8)

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
