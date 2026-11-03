#if os(iOS)
import PDFKit
import SwiftUI
import StudyNotesIOSCore
import StudyNotesKit
import UniformTypeIdentifiers

struct ReaderView: View {
    @Bindable var model: IOSAppModel
    let materialID: UUID

    @State private var session: ReaderSessionModel?
    @State private var loadError: String?
    @State private var showingAnnotationList = false
    @State private var showingAISheet = false
    @State private var textAnchorDraft: TextAnchor?
    @State private var imageRectangleDraft: NormalizedRectangle?
    @State private var showingTextComposer = false
    @State private var showingImageComposer = false
    @State private var showsImageImporter = false
    @State private var showsFileImporter = false
    @State private var pendingMediaURL: URL?
    @State private var pendingMediaKind: MarkdownEditorAttachmentKind?
    @State private var showsCellularConfirmation = false

    var body: some View {
        Group {
            if let session {
                reader(session)
            } else if let loadError {
                ContentUnavailableView(
                    "无法打开材料",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else {
                ProgressView("正在打开")
                    .task {
                        await loadSession()
                    }
            }
        }
        .navigationTitle(model.material(id: materialID)?.title ?? "阅读")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func reader(_ session: ReaderSessionModel) -> some View {
        Group {
            if isEditing(session) {
                markdownEditor(session)
            } else if session.document.material.kind == .image {
                ImageAnnotationCanvas(
                    contentURL: session.document.contentURL,
                    annotations: session.annotations,
                    pendingRectangle: $imageRectangleDraft
                )
            } else if session.document.material.kind == .pdf {
                PDFDocumentView(url: session.document.contentURL)
            } else {
                TextReaderWebView(
                    html: session.textHTML(preferences: model.readingPreferences),
                    annotations: session.annotations,
                    focusBlockPath: session.focusBlockPath,
                    onSelection: { anchor in
                        session.selectedTextAnchor = anchor
                        textAnchorDraft = anchor
                    }
                )
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        guard session.isMarkdownEditable else {
                            return
                        }
                        session.beginEditingMarkdown(
                            initialDraft: model.editorDraft(for: materialID)
                        )
                        model.setEditing(true)
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) {
            if !isEditing(session),
               textAnchorDraft != nil,
               session.document.material.kind.supportsTextAnnotation {
                selectionToolbar(session)
            } else if !isEditing(session), let imageRectangleDraft {
                imageToolbar(session, rectangle: imageRectangleDraft)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if session.isMarkdownEditable {
                    Button {
                        if isEditing(session) {
                            Task {
                                if await session.finishMarkdownEditing() {
                                    model.setEditing(false)
                                    model.clearEditorDraft(materialID: materialID)
                            model.noticeMessage = "笔记已保存"
                                    await model.reloadAll()
                                }
                            }
                        } else {
                    session.beginEditingMarkdown(
                        initialDraft: model.editorDraft(for: materialID)
                    )
                            model.setEditing(true)
                        }
                    } label: {
                        Image(
                            systemName: isEditing(session)
                                ? "checkmark.circle"
                                : "pencil"
                        )
                    }
                    .disabled(session.isSavingMarkdown)
                    .accessibilityLabel(
                        isEditing(session) ? "完成并保存" : "编辑笔记"
                    )
                }

                if !isEditing(session) {
                Button {
                    showingAnnotationList = true
                } label: {
                    Image(systemName: "highlighter")
                }
                .accessibilityLabel("标注列表")

                Button {
                    showingAISheet = true
                } label: {
                    Image(systemName: "sparkles")
                }
                .accessibilityLabel("AI 研读")
                }

                Menu {
                    if session.document.material.accessState == .offline {
                        Button("移除离线副本", systemImage: "icloud.slash", role: .destructive) {
                            Task { await model.removeOffline(materialID: materialID) }
                        }
                    } else {
                        Button("离线保存", systemImage: "arrow.down.circle") {
                            Task { await model.saveOffline(materialID: materialID) }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("阅读设置")
            }
        }
        .sheet(isPresented: $showingAnnotationList) {
            AnnotationListView(session: session)
        }
        .sheet(isPresented: $showingAISheet) {
            AISheet(session: session, model: model)
        }
        .sheet(
            isPresented: $showingTextComposer
        ) {
            if let textAnchorDraft {
                AnnotationComposer(
                    title: "文字标注",
                    quote: textAnchorDraft.quote,
                    initialNote: session.annotations.first(where: {
                        TextAnchorResolver.anchorsAreEquivalent(
                            $0.anchor,
                            .text(textAnchorDraft)
                        )
                    })?.note ?? ""
                ) { note in
                    Task {
                        await session.saveTextAnnotation(
                            anchor: textAnchorDraft,
                            note: note
                        )
                        self.textAnchorDraft = nil
                    }
                }
            }
        }
        .sheet(
            isPresented: $showingImageComposer
        ) {
            if let imageRectangleDraft {
                AnnotationComposer(
                    title: "图片区域标注",
                    quote: "归一化矩形区域",
                    initialNote: session.annotations.first(where: {
                        TextAnchorResolver.anchorsAreEquivalent(
                            $0.anchor,
                            .imageRectangle(imageRectangleDraft)
                        )
                    })?.note ?? ""
                ) { note in
                    Task {
                        await session.saveImageAnnotation(
                            rectangle: imageRectangleDraft,
                            note: note
                        )
                        self.imageRectangleDraft = nil
                    }
                }
            }
        }
        .alert(
            "操作未完成",
            isPresented: Binding(
                get: {
                    session.errorMessage != nil
                        || session.markdownError != nil
                },
                set: {
                    if !$0 {
                        session.errorMessage = nil
                        session.markdownError = nil
                    }
                }
            )
        ) {
            Button("知道了", role: .cancel) {
                session.errorMessage = nil
                session.markdownError = nil
            }
        } message: {
            Text(session.errorMessage ?? session.markdownError ?? "")
        }
        .alert(
            "标题不一致",
            isPresented: Binding(
                get: { session.editorSession?.titleConflict != nil },
                set: { _ in }
            )
        ) {
            if case let .manifestAndHeading(manifestTitle, headingTitle) =
                session.editorSession?.titleConflict {
                Button("保留清单标题“\(manifestTitle)”") {
                    Task {
                        await session.resolveMarkdownTitleConflict(
                            usingManifestTitle: true
                        )
                    }
                }
                Button("保留正文标题“\(headingTitle)”") {
                    Task {
                        await session.resolveMarkdownTitleConflict(
                            usingManifestTitle: false
                        )
                    }
                }
            }
        } message: {
            Text("保存前需要确认以哪个标题为准。")
        }
        .alert(
            "编辑冲突",
            isPresented: Binding(
                get: {
                    session.editorSession?.saveState.status == .conflict
                        && session.editorSession?.titleConflict == nil
                },
                set: { _ in }
            )
        ) {
            Button("重新载入磁盘版本", role: .destructive) {
                Task {
                    await session.reloadMarkdownFromDisk()
                }
            }
            Button("保留我的版本") {
                Task {
                    await session.keepLocalMarkdownVersion()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(
                session.editorSession?.errorMessage
                    ?? "磁盘内容已变化，当前编辑内容仍保留。"
            )
        }
        .onChange(of: session.editorSession?.markdown) {
            guard isEditing(session),
                  let markdown = session.editorSession?.markdown else {
                return
            }
            model.updateEditorDraft(
                markdown,
                materialID: materialID
            )
        }
    }

    private func isEditing(_ session: ReaderSessionModel) -> Bool {
        session.isMarkdownEditable
            && model.workspace.materialID == materialID
            && model.workspace.isEditing
    }

    private func markdownEditor(_ session: ReaderSessionModel) -> some View {
        Group {
            if let editorSession = session.editorSession {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Text(editorSession.statusLabel)
                            .font(.system(size: 10))
                            .foregroundStyle(SNColor.muted)
                        if editorSession.isSaving {
                            ProgressView()
                                .controlSize(.mini)
                        }
                        Spacer()
                        Button("保存") {
                            Task {
                                await editorSession.requestExplicitSave()
                            }
                        }
                        .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(SNColor.page)

                    MarkdownEditorView(
                        session: editorSession,
                        readingPreferences: model.readingPreferences,
                        mediaCoordinator: model.readerMediaCoordinator
                    ) { kind in
                        switch kind {
                        case .image:
                            showsImageImporter = true
                        case .file:
                            showsFileImporter = true
                        }
                    }
                }
            } else {
                ProgressView("正在准备编辑器")
            }
        }
        .fileImporter(
            isPresented: $showsImageImporter,
            allowedContentTypes: [.image]
        ) { result in
            handlePickedAttachment(result, kind: .image)
        }
        .fileImporter(
            isPresented: $showsFileImporter,
            allowedContentTypes: [.item]
        ) { result in
            handlePickedAttachment(result, kind: .file)
        }
        .alert(
            "使用蜂窝网络上传？",
            isPresented: $showsCellularConfirmation
        ) {
            Button("取消", role: .cancel) {
                pendingMediaURL = nil
                pendingMediaKind = nil
            }
            Button("继续上传") {
                guard let url = pendingMediaURL,
                      let kind = pendingMediaKind,
                      let editorSession = session.editorSession else {
                    return
                }
                pendingMediaURL = nil
                pendingMediaKind = nil
                insertPickedMedia(
                    url,
                    kind: kind,
                    session: editorSession,
                    confirmedCellularUpload: true
                )
            }
        } message: {
            Text("该文件超过 10MB，上传会使用当前蜂窝网络流量。")
        }
    }

    private func handlePickedAttachment(
        _ result: Result<URL, Error>,
        kind: MarkdownEditorAttachmentKind
    ) {
        guard case let .success(url) = result,
              let editorSession = session?.editorSession else {
            return
        }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if model.mediaConnection == .cellular,
           size > NoteMediaPolicy.cellularConfirmationByteCount {
            pendingMediaURL = url
            pendingMediaKind = kind
            showsCellularConfirmation = true
            return
        }
        insertPickedMedia(
            url,
            kind: kind,
            session: editorSession,
            confirmedCellularUpload: false
        )
    }

    private func insertPickedMedia(
        _ url: URL,
        kind: MarkdownEditorAttachmentKind,
        session: MarkdownEditorSession,
        confirmedCellularUpload: Bool
    ) {
        Task {
            let isAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if isAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let contentType = NoteMediaPolicy.contentType(
                forFileExtension: url.pathExtension
            ) ?? (kind == .image ? "image/jpeg" : "application/octet-stream")
            guard let decision = await model.insertMedia(
                fileAt: url,
                contentType: contentType,
                connection: model.mediaConnection,
                confirmedCellularUpload: confirmedCellularUpload
            ) else {
                return
            }
            switch decision {
            case .requiresCellularConfirmation:
                pendingMediaURL = url
                pendingMediaKind = kind
                showsCellularConfirmation = true
            case let .inserted(insertion):
                session.insertMediaReference(
                    insertion.reference,
                    kind: kind,
                    label: url.deletingPathExtension().lastPathComponent
                )
                await self.session?.resolveMediaURLs()
                _ = await model.uploadMedia(
                    id: insertion.item.id,
                    confirmedCellularUpload: true
                )
                await self.session?.resolveMediaURLs()
            }
        }
    }

    private func selectionToolbar(_ session: ReaderSessionModel) -> some View {
        HStack(spacing: 10) {
            Button {
                guard let anchor = textAnchorDraft else {
                    return
                }
                Task {
                    await session.saveTextAnnotation(anchor: anchor, note: "")
                    textAnchorDraft = nil
                }
            } label: {
                Label("高亮", systemImage: "highlighter")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                showingTextComposer = true
            } label: {
                Label("高亮并备注", systemImage: "note.text.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(SNColor.primary)
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func imageToolbar(
        _ session: ReaderSessionModel,
        rectangle: NormalizedRectangle
    ) -> some View {
        HStack {
            Text("已框选图片区域")
                .font(.system(size: 11))
                .foregroundStyle(SNColor.text)
            Spacer()
            Button("取消") {
                imageRectangleDraft = nil
            }
            .buttonStyle(.bordered)
            Button("添加标注") {
                showingImageComposer = true
            }
            .buttonStyle(.borderedProminent)
            .tint(SNColor.primary)
        }
        .font(.system(size: 11.5, weight: .medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func loadSession() async {
        do {
            let loaded = try await model.makeReaderModel(materialID: materialID)
            session = loaded
            if let draft = model.editorDraft(for: materialID) {
                loaded.draftMarkdown = draft
            }
            if model.workspace.materialID == materialID,
               model.workspace.isEditing {
                loaded.beginEditingMarkdown(
                    initialDraft: model.editorDraft(for: materialID)
                )
            }
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct PDFDocumentView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = UIColor(SNColor.nav)
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
    }
}

private struct AnnotationComposer: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let quote: String
    var initialNote = ""
    let onSave: (String) -> Void
    @State private var note = ""

    init(
        title: String,
        quote: String,
        initialNote: String = "",
        onSave: @escaping (String) -> Void
    ) {
        self.title = title
        self.quote = quote
        self.initialNote = initialNote
        self.onSave = onSave
        _note = State(initialValue: initialNote)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("锚定内容") {
                    Text(quote)
                        .font(.system(size: 13))
                        .foregroundStyle(SNColor.text)
                        .lineLimit(6)
                }
                Section("备注") {
                    TextEditor(text: $note)
                        .frame(minHeight: 130)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(note)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct AnnotationListView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var session: ReaderSessionModel
    @State private var editingAnnotation: StudyAnnotation?

    var body: some View {
        NavigationStack {
            List {
                if session.annotations.isEmpty {
                    ContentUnavailableView(
                        "还没有标注",
                        systemImage: "highlighter",
                        description: Text("选择正文或图片区域后可添加。")
                    )
                } else {
                    ForEach(session.annotations) { annotation in
                        Button {
                            session.jump(to: annotation)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(annotation.quote ?? "图片区域")
                                        .font(.system(size: 12.5, weight: .medium))
                                        .foregroundStyle(SNColor.ink)
                                        .lineLimit(2)
                                    Spacer()
                                    StatusPill(
                                        text: annotation.resolution.label,
                                        color: annotation.resolution == .resolved
                                            ? SNColor.green
                                            : SNColor.amberInk,
                                        background: annotation.resolution == .resolved
                                            ? SNColor.greenSoft
                                            : SNColor.amberSoft,
                                        systemImage: annotation.resolution == .resolved
                                            ? "scope"
                                            : "exclamationmark.triangle"
                                    )
                                }
                                if !annotation.note.isEmpty {
                                    Text(annotation.note)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(SNColor.text)
                                        .lineLimit(3)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("删除", role: .destructive) {
                                Task { await session.deleteAnnotation(annotation) }
                            }
                            Button("编辑") {
                                editingAnnotation = annotation
                            }
                            .tint(SNColor.primary)
                        }
                    }
                }
            }
            .navigationTitle("标注")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(item: $editingAnnotation) { annotation in
                AnnotationComposer(
                    title: "编辑标注",
                    quote: annotation.quote ?? "图片区域",
                    initialNote: annotation.note
                ) { note in
                    Task {
                        await session.updateAnnotationNote(annotation, note: note)
                    }
                }
            }
        }
    }
}
#endif
