import SwiftUI
import StudyCore

public struct NoteEditorView: View {
    @Bindable var model: AppModel
    let note: Note

    @State private var text: String = ""
    @State private var isEditing = false
    @State private var isDirty = false
    @State private var isGenerating = false
    @State private var message: String?
    @State private var selectedRenderedRange: NSRange?
    @State private var pendingRange: NSRange?
    @State private var annotationSheet: AnnotationTarget?
    @State private var layoutCache = LayoutCache()
    @State private var visibleNearestRange: NSRange?
    @State private var isEditingTags = false
    @State private var tagsDraft = ""

    public init(model: AppModel, note: Note) {
        self.model = model
        self.note = note
    }

    private struct AnnotationTarget: Identifiable {
        let id: String
    }

    private var layout: MarkdownLayout {
        cachedLayout
    }

    private var strippedText: String {
        cachedLayout.source
    }

    private var markedRanges: [NSRange] {
        model.annotations.resolved.map(\.range)
    }

    private var cachedLayout: MarkdownLayout {
        layoutCache.layout(for: text)
    }

    public var body: some View {
        VStack(spacing: 0) {
            if isEditing {
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .onChange(of: text) { _, _ in
                        isDirty = text != savedText
                    }
            } else {
                RenderedMarkdownTextView(
                    layout: layout,
                    markedRanges: markedRanges,
                    selectedRenderedRange: $selectedRenderedRange,
                    onTapMarkedRange: { tapped in
                        openBubble(forSourceRange: tapped)
                    },
                    onTapOutside: {
                        closeBubble()
                    },
                    onVisibleNearestChange: { nearest in
                        visibleNearestRange = nearest
                    }
                )
                .onChange(of: selectedRenderedRange) { _, newValue in
                    guard let newValue, newValue.length > 0 else {
                        pendingRange = nil
                        return
                    }
                    pendingRange = layout.sourceRange(forRendered: newValue)
                }
            }

            if let pendingRange, let preview = selectionPreview(pendingRange) {
                Divider()
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("选中")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(preview)
                            .font(.caption)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Button {
                        addAnnotation(range: pendingRange, preview: preview)
                    } label: {
                        Label("评论", systemImage: "text.bubble")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.yellow)
                    .foregroundStyle(.black)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.yellow.opacity(0.12))
            }

            if !isEditing, !model.annotations.resolved.isEmpty {
                annotationBar
            }

            if let message {
                Divider()
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: messageIcon)
                        .font(.caption)
                    Text(message)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button {
                        self.message = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
                .foregroundStyle(messageColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack(spacing: 12) {
                if isEditing && isDirty {
                    Text("未保存")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Spacer()

                if isEditing {
                    Button("完成") {
                        if isDirty { save() }
                        isEditing = false
                        clearSelection()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("取消") {
                        text = savedText
                        isDirty = false
                        isEditing = false
                    }
                } else {
                    Button {
                        generateCards()
                    } label: {
                        if isGenerating {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("生成卡片", systemImage: "sparkles")
                        }
                    }
                    .disabled(isGenerating || !model.settings.hasAPIKey)

                    Button {
                        isEditing = true
                        message = nil
                        clearSelection()
                    } label: {
                        Label("编辑", systemImage: "pencil")
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .navigationTitle(note.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    tagsDraft = note.tags.joined(separator: ", ")
                    isEditingTags = true
                } label: {
                    Label("分类", systemImage: "folder.badge.gearshape")
                }
            }
        }
        .alert("分类", isPresented: $isEditingTags) {
            TextField("多个用逗号分隔", text: $tagsDraft)
            Button("取消", role: .cancel) {}
            Button("保存") { applyTags() }
        } message: {
            Text("分类保存在笔记的 front matter 里，也是笔记列表的分组依据。")
        }
        .task(id: note.id) {
            text = savedText
            isDirty = false
            isEditing = false
            clearSelection()
            message = nil
            model.annotations.load(note: note)
            model.annotations.refresh(with: NoteAnnotations.stripHighlights(text))
        }
        .overlay(alignment: .bottom) {
            if let target = annotationSheet,
               let annotation = model.annotations.file.annotation(id: target.id) {
                AnnotationBubble(
                    annotation: annotation,
                    anchorText: annotation.anchorText,
                    onAddComment: { body in
                        model.annotations.addComment(body, to: target.id, source: strippedText)
                    },
                    onAddReply: { body, commentID in
                        model.annotations.addReply(
                            body,
                            to: commentID,
                            annotationID: target.id,
                            source: strippedText
                        )
                    },
                    onDelete: {
                        model.annotations.remove(annotationID: target.id, source: strippedText)
                        annotationSheet = nil
                    },
                    onClose: {
                        annotationSheet = nil
                    }
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 56)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.78), value: annotationSheet?.id)
    }

    private var annotationBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "highlighter")
                .font(.caption2)
                .foregroundStyle(.orange)

            if let latest = latestAnnotation {
                Text(latest.anchorText)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                if latest.commentCount > 0 {
                    Text("\(latest.commentCount) 层")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.18), in: Capsule())
                        .foregroundStyle(.orange)
                }
                Button {
                    openBubble(forAnnotationID: latest.id)
                } label: {
                    Label("评论", systemImage: "text.bubble")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            } else {
                Text("这里附近还没有标注")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if model.annotations.resolved.count > 1 {
                Text("共 \(model.annotations.resolved.count) 处")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.yellow.opacity(0.10))
    }

    private var latestAnnotation: Annotation? {
        if let visibleNearestRange {
            let hit = model.annotations.resolved.first { item in
                NSIntersectionRange(item.range, visibleNearestRange).length > 0
            }
            if let hit { return hit.annotation }
        }
        return model.annotations.resolved.last?.annotation
    }

    private var savedText: String {
        model.notes.body(of: note)
    }

    private var isError: Bool {
        guard let message else { return false }
        return !message.hasPrefix("已")
    }

    private var messageIcon: String {
        isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
    }

    private var messageColor: Color {
        isError ? .red : .secondary
    }

    private func clearSelection() {
        selectedRenderedRange = nil
        pendingRange = nil
    }

    private func selectionPreview(_ range: NSRange) -> String? {
        let ns = strippedText as NSString
        guard range.location >= 0, range.location + range.length <= ns.length else { return nil }
        let picked = ns.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
        return picked.isEmpty ? nil : picked
    }

    private func addAnnotation(range: NSRange, preview: String) {
        let source = strippedText
        guard let annotation = AnnotationAnchor.make(from: source, range: range, existing: []) else {
            message = "这段文字无法标注，换一段试试"
            return
        }
        model.annotations.add(annotation: annotation, source: source)
        clearSelection()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
            annotationSheet = AnnotationTarget(id: annotation.id)
        }
    }

    private func applyTags() {
        let tags = tagsDraft
            .split(whereSeparator: { $0 == "," || $0 == "，" || $0 == " " })
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let updated = MarkdownCardParser.withTags(tags, in: text)
        text = updated
        do {
            try model.notes.save(note: note, content: updated)
            layoutCache = LayoutCache()
            message = tags.isEmpty ? "已清除分类" : "已设为「\(tags.joined(separator: "、"))」"
        } catch {
            message = error.localizedDescription
        }
    }

    private func closeBubble() {
        guard annotationSheet != nil else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            annotationSheet = nil
        }
    }

    private func openBubble(forAnnotationID id: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
            annotationSheet = AnnotationTarget(id: id)
        }
    }

    private func openBubble(forSourceRange range: NSRange) {
        guard let target = model.annotations.resolved.first(where: { item in
            NSIntersectionRange(item.range, range).length > 0
        }) else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
            annotationSheet = AnnotationTarget(id: target.annotation.id)
        }
    }

    private func save() {
        do {
            try model.notes.save(note: note, content: text)
            isDirty = false
            message = "已保存"
        } catch {
            message = error.localizedDescription
        }
    }

    private func generateCards() {
        guard let client = model.client else {
            message = "没有 API Key，请先到「设置」填写并保存"
            return
        }
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
            message = "笔记是空的，先写点内容"
            return
        }
        isGenerating = true
        message = nil

        Task {
            do {
                let current = MarkdownCardParser.parseNote(relativePath: note.id, content: text)
                let cards = try await client.generateCards(from: current)
                guard !cards.isEmpty else {
                    message = "模型没有给出卡片，试试把笔记写得更具体些"
                    return
                }
                let appended = appendCards(cards, to: text)
                text = appended
                try model.notes.save(note: note, content: appended)
                isDirty = false
                message = "已添加 \(cards.count) 张卡片"
            } catch {
                message = error.localizedDescription
            }
            isGenerating = false
        }
    }

    private func appendCards(_ cards: [Card], to markdown: String) -> String {
        var result = markdown
        if !result.hasSuffix("\n") { result += "\n" }
        result += "\n"
        for card in cards {
            result += "```card\n"
            result += "id: \(card.id)\n"
            result += "q: \(card.question)\n"
            result += "a: \(card.answer)\n"
            result += "```\n\n"
        }
        return result
    }
}

@MainActor
final class LayoutCache {
    private var key: String?
    private var value: MarkdownLayout?

    func layout(for text: String) -> MarkdownLayout {
        if key == text, let value {
            return value
        }
        let source = NoteAnnotations.stripHighlights(text)
        let built = MarkdownLayout.build(source: source)
        key = text
        value = built
        return built
    }
}
