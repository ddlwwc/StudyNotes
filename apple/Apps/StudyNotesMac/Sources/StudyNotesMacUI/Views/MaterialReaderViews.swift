import AppKit
import PDFKit
import StudyNotesKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

struct MaterialReaderView: View {
    @Bindable var model: WorkspaceModel
    let document: MaterialDocument

    var body: some View {
        switch document.summary.kind {
        case .note, .markdown, .html, .webArticle:
            ArticleMaterialReader(model: model, document: document)
        case .pdf:
            PDFMaterialReader(model: model, document: document)
        case .image:
            ImageMaterialReader(model: model, document: document)
        }
    }
}

private struct ArticleMaterialReader: View {
    @Bindable var model: WorkspaceModel
    let document: MaterialDocument
    @Environment(\.colorScheme) private var colorScheme
    @State private var showsImageImporter = false
    @State private var showsFileImporter = false

    var body: some View {
        Group {
            if let session = model.markdownEditorSession,
               session.materialID == document.id,
               document.summary.kind == .note
                    || document.summary.kind == .markdown {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Text(session.statusLabel)
                            .font(.sn(10))
                            .foregroundStyle(SNColor.muted)

                        if session.isSaving {
                            ProgressView()
                                .controlSize(.mini)
                        }

                        Spacer()

                        Button {
                            Task {
                                await session.requestExplicitSave()
                            }
                        } label: {
                            Label("保存", systemImage: "square.and.arrow.down")
                                .font(.sn(10))
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut("s", modifiers: .command)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 34)
                    .background(SNColor.panel)

                    MarkdownEditorView(
                        session: session,
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
                ArticleWebView(
                    document: document,
                    annotations: model.annotations,
                    jumpToAnnotationID: model.annotationJumpID,
                    headingID: model.readerHeadingJumpID,
                    searchText: model.documentSearchText,
                    readingPreferences: model.readingPreferences,
                    isDarkMode: colorScheme == .dark,
                    onSelectionChanged: { selection in
                        model.updateReaderSelection(selection)
                    },
                    onAnnotationClick: { id in
                        model.annotationJumpID = id
                        model.studyPanelTab = .annotations
                        model.isStudyPanelVisible = true
                    }
                )
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        model.beginMarkdownEditing()
                    }
                )
            }
        }
        .background(SNColor.white)
        .alert(
            "标题不一致",
            isPresented: Binding(
                get: { model.markdownEditorSession?.titleConflict != nil },
                set: { _ in }
            )
        ) {
            if case let .manifestAndHeading(manifestTitle, headingTitle) =
                model.markdownEditorSession?.titleConflict {
                Button("保留清单标题“\(manifestTitle)”") {
                    Task {
                        await model.resolveMarkdownTitleConflict(
                            usingManifestTitle: true
                        )
                    }
                }
                Button("保留正文标题“\(headingTitle)”") {
                    Task {
                        await model.resolveMarkdownTitleConflict(
                            usingManifestTitle: false
                        )
                    }
                }
            }
        } message: {
            Text("保存前需要确认以哪个标题为准，正文内容尚未写入磁盘。")
        }
        .alert(
            "编辑冲突",
            isPresented: Binding(
                get: {
                    model.markdownEditorSession?.saveState.status == .conflict
                        && model.markdownEditorSession?.titleConflict == nil
                },
                set: { _ in }
            )
        ) {
            Button("重新载入磁盘版本", role: .destructive) {
                Task {
                    await model.reloadMarkdownEditorFromDisk()
                }
            }
            Button("保留我的版本") {
                Task {
                    await model.keepLocalMarkdownVersion()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(
                model.markdownEditorSession?.errorMessage
                    ?? "磁盘内容已变化，当前编辑内容仍保留在编辑器中。"
            )
        }
        .fileImporter(
            isPresented: $showsImageImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            handleAttachment(result, kind: .image)
        }
        .fileImporter(
            isPresented: $showsFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            handleAttachment(result, kind: .file)
        }
    }

    private func handleAttachment(
        _ result: Result<[URL], Error>,
        kind: MarkdownEditorAttachmentKind
    ) {
        guard case let .success(urls) = result,
              let url = urls.first,
              let session = model.markdownEditorSession else {
            return
        }
        let isAccessing = url.startAccessingSecurityScopedResource()
        Task {
            defer {
                if isAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let contentType = NoteMediaPolicy.contentType(
                forFileExtension: url.pathExtension
            ) ?? (kind == .image ? "image/jpeg" : "application/octet-stream")
            guard case let .inserted(insertion)? = await model.insertNoteMedia(
                fileAt: url,
                contentType: contentType,
                connection: .wifi,
                confirmedCellularUpload: true
            ) else {
                return
            }
            session.insertMediaReference(
                insertion.reference,
                kind: kind,
                label: url.deletingPathExtension().lastPathComponent
            )
            await model.uploadNoteMedia(id: insertion.item.id)
            await model.reloadSelectedDocumentMedia()
        }
    }
}

private struct ArticleWebView: NSViewRepresentable {
    let document: MaterialDocument
    let annotations: [MaterialAnnotation]
    let jumpToAnnotationID: UUID?
    let headingID: String?
    let searchText: String
    let readingPreferences: ReadingPreferences
    let isDarkMode: Bool
    let onSelectionChanged: (ReaderSelection?) -> Void
    let onAnnotationClick: (UUID) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(
            context.coordinator,
            name: "selectionChanged"
        )
        configuration.userContentController.add(
            context.coordinator,
            name: "annotationClick"
        )
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = webView
        context.coordinator.load(document: document, in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.documentID != document.id {
            context.coordinator.load(document: document, in: webView)
            return
        }
        context.coordinator.applyReadingPreferences(
            readingPreferences,
            isDarkMode: isDarkMode,
            in: webView
        )
        context.coordinator.applyAnnotations(annotations, in: webView)
        if let jumpToAnnotationID {
            context.coordinator.jump(to: jumpToAnnotationID, in: webView)
        }
        if let headingID {
            webView.evaluateJavaScript(
                "window.studyNotesScrollToHeading(\(javaScriptString(headingID)));"
            )
        }
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            webView.evaluateJavaScript(
                "window.studyNotesFind(\(javaScriptString(searchText)), false);"
            )
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: "selectionChanged"
        )
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: "annotationClick"
        )
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: ArticleWebView
        weak var webView: WKWebView?
        var documentID: UUID?
        private var loadedDocumentID: UUID?
        private var readingPreferencesSignature = ""

        init(parent: ArticleWebView) {
            self.parent = parent
        }

        func load(document: MaterialDocument, in webView: WKWebView) {
            documentID = document.id
            loadedDocumentID = document.id
            webView.loadHTMLString(
                document.renderedHTML,
                baseURL: document.sourceURL
            )
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            applyReadingPreferences(
                parent.readingPreferences,
                isDarkMode: parent.isDarkMode,
                in: webView
            )
            applyAnnotations(parent.annotations, in: webView)
        }

        func applyReadingPreferences(
            _ preferences: ReadingPreferences,
            isDarkMode: Bool,
            in webView: WKWebView
        ) {
            let signature = [
                String(preferences.fontSize),
                String(preferences.lineHeight),
                String(preferences.lineWidth),
                preferences.codeFont,
                String(isDarkMode)
            ].joined(separator: "|")
            guard signature != readingPreferencesSignature else {
                return
            }
            readingPreferencesSignature = signature
            let background = isDarkMode ? "#1b1c20" : "#ffffff"
            let text = isDarkMode ? "#c6c9d0" : "#374151"
            let heading = isDarkMode ? "#f0f1f3" : "#111827"
            let muted = isDarkMode ? "#a9adb7" : "#4b5563"
            let border = isDarkMode ? "#34363d" : "#e5e7eb"
            let codeBackground = isDarkMode ? "#25272d" : "#f7f8fa"
            let codeText = isDarkMode ? "#eceef2" : "#111827"
            let codeFont = preferences.codeFont
                .replacingOccurrences(of: "\"", with: "\\\"")
            let css = """
            :root { color-scheme: \(isDarkMode ? "dark" : "light"); }
            html, body { background: \(background) !important; }
            body {
              color: \(text) !important;
              font-size: \(preferences.fontSize)px !important;
              line-height: \(preferences.lineHeight) !important;
            }
            article { max-width: \(preferences.lineWidth)px !important; }
            h1, h2, h3, h4, h5, h6 { color: \(heading) !important; }
            blockquote { color: \(muted) !important; }
            pre {
              border-color: \(border) !important;
              background: \(codeBackground) !important;
              color: \(codeText) !important;
              font-family: "\(codeFont)", SFMono-Regular, Menlo, monospace !important;
              font-size: \(max(11, preferences.fontSize - 4))px !important;
            }
            code { font-family: "\(codeFont)", SFMono-Regular, Menlo, monospace !important; }
            """
            webView.evaluateJavaScript(
                """
                (() => {
                  let style = document.getElementById('studynotes-reading-preferences');
                  if (!style) {
                    style = document.createElement('style');
                    style.id = 'studynotes-reading-preferences';
                    document.head.appendChild(style);
                  }
                  style.textContent = \(javaScriptString(css));
                })();
                """
            )
        }

        func applyAnnotations(
            _ annotations: [MaterialAnnotation],
            in webView: WKWebView
        ) {
            let payload = annotations.map { annotation in
                [
                    "id": annotation.id.uuidString,
                    "quote": annotation.anchor.excerpt,
                    "note": annotation.note,
                    "unresolved": annotation.status == .unresolved
                ] as [String: Any]
            }
            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                  let json = String(data: data, encoding: .utf8) else {
                return
            }
            webView.evaluateJavaScript(
                "window.studyNotesApplyAnnotations(\(json));"
            )
        }

        func jump(to id: UUID, in webView: WKWebView) {
            webView.evaluateJavaScript(
                """
                (() => {
                  const mark = document.querySelector(
                    'mark[data-annotation-id="\(id.uuidString)"]'
                  );
                  if (mark) mark.scrollIntoView({ block: 'center', behavior: 'smooth' });
                })();
                """
            )
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            switch message.name {
            case "selectionChanged":
                guard let payload = message.body as? [String: Any],
                      let quote = payload["quote"] as? String,
                      !quote.isEmpty else {
                    parent.onSelectionChanged(nil)
                    return
                }
                parent.onSelectionChanged(
                    ReaderSelection(
                        quote: quote,
                        prefix: payload["prefix"] as? String ?? "",
                        suffix: payload["suffix"] as? String ?? "",
                        offset: payload["offset"] as? Int ?? 0,
                        blockPath: payload["blockPath"] as? [Int] ?? [],
                        anchorKind: .text
                    )
                )
            case "annotationClick":
                guard let rawID = message.body as? String,
                      let id = UUID(uuidString: rawID) else {
                    return
                }
                parent.onAnnotationClick(id)
            default:
                break
            }
        }
    }
}

private struct PDFMaterialReader: View {
    @Bindable var model: WorkspaceModel
    let document: MaterialDocument
    @State private var regionSelectionEnabled = false
    @State private var zoomScale = 1.0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Label(
                    "\(document.pageCount ?? 0) 页 · \(document.hasTextLayer == true ? "含文字层" : "图像页")",
                    systemImage: "doc.richtext"
                )
                .font(.sn(10))
                .foregroundStyle(SNColor.muted)

                Spacer()

                Button {
                    zoomScale = max(0.4, zoomScale - 0.15)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.plain)
                .help("缩小 PDF")

                Text("\(Int(zoomScale * 100))%")
                    .font(.sn(9))
                    .foregroundStyle(SNColor.muted)
                    .frame(width: 40)

                Button {
                    zoomScale = min(4, zoomScale + 0.15)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.plain)
                .help("放大 PDF")

                Toggle(isOn: $regionSelectionEnabled) {
                    Label("页面区域", systemImage: "rectangle.dashed")
                        .font(.sn(10))
                }
                .toggleStyle(.button)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .frame(height: 42)
            .background(SNColor.panel)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(SNColor.border)
                    .frame(height: 1)
            }

            PDFKitReaderView(
                document: document,
                annotations: model.annotations,
                jumpToAnnotationID: model.annotationJumpID,
                regionSelectionEnabled: regionSelectionEnabled,
                zoomScale: zoomScale,
                onSelection: { selection in
                    model.updateReaderSelection(selection)
                },
                onPageRegion: { selection in
                    model.updateReaderSelection(selection)
                    model.presentAnnotationForCurrentSelection()
                }
            )
        }
    }
}

private struct PDFKitReaderView: NSViewRepresentable {
    let document: MaterialDocument
    let annotations: [MaterialAnnotation]
    let jumpToAnnotationID: UUID?
    let regionSelectionEnabled: Bool
    let zoomScale: Double
    let onSelection: (ReaderSelection?) -> Void
    let onPageRegion: (ReaderSelection) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> SelectablePDFView {
        let pdfView = SelectablePDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .white
        pdfView.isRegionSelectionMode = regionSelectionEnabled
        pdfView.onPageRegion = { selection in
            context.coordinator.parent.onPageRegion(selection)
        }
        context.coordinator.pdfView = pdfView
        context.coordinator.observe(pdfView)
        context.coordinator.load(document: document, in: pdfView)
        return pdfView
    }

    func updateNSView(_ pdfView: SelectablePDFView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.documentID != document.id {
            context.coordinator.load(document: document, in: pdfView)
        } else {
            context.coordinator.render(annotations)
        }
        context.coordinator.jumpIfNeeded(to: jumpToAnnotationID)
        pdfView.isRegionSelectionMode = regionSelectionEnabled
        if abs(pdfView.scaleFactor - zoomScale) > 0.01 {
            pdfView.autoScales = false
            pdfView.scaleFactor = zoomScale
        }
    }

    static func dismantleNSView(_ pdfView: SelectablePDFView, coordinator: Coordinator) {
        coordinator.stopObserving()
        pdfView.onPageRegion = nil
    }

    @MainActor
    final class Coordinator: @unchecked Sendable {
        var parent: PDFKitReaderView
        weak var pdfView: SelectablePDFView?
        var documentID: UUID?
        private var observer: NSObjectProtocol?
        private var lastJumpID: UUID?

        init(parent: PDFKitReaderView) {
            self.parent = parent
        }

        func load(document: MaterialDocument, in pdfView: SelectablePDFView) {
            documentID = document.id
            guard let sourceURL = document.sourceFileURL,
                  let source = PDFDocument(url: sourceURL),
                  let copy = source.copy() as? PDFDocument else {
                pdfView.document = nil
                return
            }
            pdfView.document = copy
            render(parent.annotations)
        }

        func observe(_ pdfView: PDFView) {
            observer = NotificationCenter.default.addObserver(
                forName: Notification.Name.PDFViewSelectionChanged,
                object: pdfView,
                queue: .main
            ) { [weak self, weak pdfView] _ in
                Task { @MainActor in
                    guard let self, let pdfView else {
                        return
                    }
                    self.selectionChanged(in: pdfView)
                }
            }
        }

        func stopObserving() {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
            observer = nil
        }

        func selectionChanged(in pdfView: PDFView) {
            guard let selection = pdfView.currentSelection,
                  let page = selection.pages.first,
                  let document = pdfView.document else {
                parent.onSelection(nil)
                return
            }
            let pageIndex = document.index(for: page)
            let bounds = selection.bounds(for: page)
            let normalized = normalizedRect(bounds, in: page)
            parent.onSelection(
                ReaderSelection(
                    quote: selection.string ?? "",
                    pageIndex: pageIndex,
                    rect: normalized,
                    anchorKind: .pdfText
                )
            )
        }

        func render(_ annotations: [MaterialAnnotation]) {
            guard let pdfView,
                  let document = pdfView.document else {
                return
            }
            for pageIndex in 0..<document.pageCount {
                guard let page = document.page(at: pageIndex) else {
                    continue
                }
                for annotation in page.annotations
                where annotation.userName == "StudyNotesRuntime" {
                    page.removeAnnotation(annotation)
                }
            }
            for annotation in annotations {
                let pageIndex: Int?
                let rect: NormalizedRect?
                switch annotation.anchor.kind {
                case .pdfText, .pdfPageRect:
                    pageIndex = annotation.anchor.pageIndex
                    rect = annotation.anchor.rect
                case .text, .imageRect:
                    pageIndex = nil
                    rect = nil
                }
                guard let pageIndex,
                      let rect,
                      let page = document.page(at: pageIndex) else {
                    continue
                }
                let bounds = page.bounds(for: .cropBox)
                let pdfBounds = CGRect(
                    x: bounds.minX + rect.x * bounds.width,
                    y: bounds.minY + (1 - rect.y - rect.height) * bounds.height,
                    width: rect.width * bounds.width,
                    height: rect.height * bounds.height
                )
                let pdfAnnotation = PDFAnnotation(
                    bounds: pdfBounds,
                    forType: .square,
                    withProperties: nil
                )
                pdfAnnotation.color = annotation.status == .unresolved
                    ? NSColor.systemOrange.withAlphaComponent(0.25)
                    : NSColor.systemYellow.withAlphaComponent(0.32)
                pdfAnnotation.userName = "StudyNotesRuntime"
                page.addAnnotation(pdfAnnotation)
            }
        }

        func jumpIfNeeded(to id: UUID?) {
            guard let id, id != lastJumpID,
                  let pdfView,
                  let document = pdfView.document,
                  let annotation = parent.annotations.first(where: { $0.id == id }),
                  let pageIndex = annotation.anchor.pageIndex,
                  let page = document.page(at: pageIndex) else {
                return
            }
            lastJumpID = id
            pdfView.go(to: page)
        }
    }
}

private final class SelectablePDFView: PDFView {
    var onPageRegion: ((ReaderSelection) -> Void)?
    var isRegionSelectionMode = false
    private var dragPage: PDFPage?
    private var dragStart: CGPoint?

    override func mouseDown(with event: NSEvent) {
        guard isRegionSelectionMode || event.modifierFlags.contains(.option),
              let page = page(
                  for: convert(event.locationInWindow, from: nil),
                  nearest: true
              ) else {
            super.mouseDown(with: event)
            return
        }
        dragPage = page
        dragStart = convert(convert(event.locationInWindow, from: nil), to: page)
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragPage != nil else {
            super.mouseDragged(with: event)
            return
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let page = dragPage,
              let start = dragStart else {
            super.mouseUp(with: event)
            return
        }
        defer {
            dragPage = nil
            dragStart = nil
        }
        let end = convert(convert(event.locationInWindow, from: nil), to: page)
        let rect = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
        guard rect.width > 4, rect.height > 4,
              let document,
              let selectionRect = normalizedRect(rect, in: page) else {
            return
        }
        onPageRegion?(
            ReaderSelection(
                quote: "",
                pageIndex: document.index(for: page),
                rect: selectionRect,
                anchorKind: .pdfPageRect
            )
        )
    }
}

private struct ImageMaterialReader: View {
    @Bindable var model: WorkspaceModel
    let document: MaterialDocument
    @State private var zoom = 1.0
    @State private var isSelectingRegion = false
    @State private var dragStart: CGPoint?
    @State private var dragRect: CGRect?

    private var image: NSImage? {
        guard let sourceURL = document.sourceFileURL else {
            return nil
        }
        return NSImage(contentsOf: sourceURL)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Label("图片", systemImage: "photo")
                    .font(.sn(11, weight: .medium))
                    .foregroundStyle(SNColor.text)

                Spacer()

                Button {
                    zoom = max(0.25, zoom - 0.25)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.plain)
                .help("缩小")

                Text("\(Int(zoom * 100))%")
                    .font(.sn(10))
                    .foregroundStyle(SNColor.muted)
                    .frame(width: 44)

                Button {
                    zoom = min(4, zoom + 0.25)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.plain)
                .help("放大")

                Toggle(isOn: $isSelectingRegion) {
                    Label("框选区域", systemImage: "rectangle.dashed")
                        .font(.sn(10))
                }
                .toggleStyle(.button)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .frame(height: 42)
            .background(SNColor.panel)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(SNColor.border)
                    .frame(height: 1)
            }

            if let image {
                ScrollView([.horizontal, .vertical]) {
                    imageCanvas(image)
                        .padding(28)
                }
                .background(SNColor.nav)
            } else {
                ContentUnavailableView(
                    "无法打开图片",
                    systemImage: "photo.badge.exclamationmark",
                    description: Text("原始图片可能仍在从 iCloud 下载。")
                )
            }
        }
    }

    private func imageCanvas(_ image: NSImage) -> some View {
        let width = max(120, image.size.width * zoom)
        let height = max(80, image.size.height * zoom)
        return ZStack(alignment: .topLeading) {
            Image(nsImage: image)
                .resizable()
                .frame(width: width, height: height)

            GeometryReader { geometry in
                ForEach(model.annotations.filter { $0.anchor.kind == .imageRect }) { annotation in
                    if let rect = annotation.anchor.rect {
                        let isJumpedTo = model.annotationJumpID == annotation.id
                        Rectangle()
                            .fill(
                                isJumpedTo
                                    ? SNColor.blue.opacity(0.18)
                                    : annotation.status == .unresolved
                                    ? SNColor.orange.opacity(0.12)
                                    : SNColor.yellow.opacity(0.24)
                            )
                            .overlay {
                                Rectangle()
                                    .stroke(
                                        annotation.status == .unresolved
                                            ? SNColor.orange
                                            : isJumpedTo
                                            ? SNColor.blue
                                            : SNColor.yellowLine,
                                        style: StrokeStyle(
                                            lineWidth: 1.5,
                                            dash: annotation.status == .unresolved ? [5, 3] : []
                                        )
                                    )
                            }
                            .frame(
                                width: rect.width * geometry.size.width,
                                height: rect.height * geometry.size.height
                            )
                            .offset(
                                x: rect.x * geometry.size.width,
                                y: rect.y * geometry.size.height
                            )
                    }
                }

                if let dragRect {
                    Rectangle()
                        .fill(SNColor.blue.opacity(0.16))
                        .overlay {
                            Rectangle()
                                .stroke(SNColor.blue, lineWidth: 1.5)
                        }
                        .frame(width: dragRect.width, height: dragRect.height)
                        .offset(x: dragRect.minX, y: dragRect.minY)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                isSelectingRegion
                    ? DragGesture(minimumDistance: 4)
                        .onChanged { value in
                            if dragStart == nil {
                                dragStart = value.startLocation
                            }
                            guard let start = dragStart else {
                                return
                            }
                            dragRect = CGRect(
                                x: min(start.x, value.location.x),
                                y: min(start.y, value.location.y),
                                width: abs(value.location.x - start.x),
                                height: abs(value.location.y - start.y)
                            )
                        }
                        .onEnded { value in
                            guard let start = dragStart else {
                                return
                            }
                            let rect = CGRect(
                                x: min(start.x, value.location.x),
                                y: min(start.y, value.location.y),
                                width: abs(value.location.x - start.x),
                                height: abs(value.location.y - start.y)
                            )
                            dragStart = nil
                            dragRect = nil
                            guard rect.width > 4, rect.height > 4 else {
                                return
                            }
                            model.updateReaderSelection(
                                ReaderSelection(
                                    quote: "",
                                    rect: NormalizedRect(
                                        x: rect.minX / width,
                                        y: rect.minY / height,
                                        width: rect.width / width,
                                        height: rect.height / height
                                    ),
                                    anchorKind: .imageRect
                                )
                            )
                            model.presentAnnotationForCurrentSelection()
                        }
                    : nil
            )
        }
        .frame(width: width, height: height)
    }
}

struct PublishHTMLPreview: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        return WKWebView(frame: .zero, configuration: configuration)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(html, baseURL: nil)
    }
}

private func normalizedRect(_ rect: CGRect, in page: PDFPage) -> NormalizedRect? {
    let bounds = page.bounds(for: .cropBox)
    guard bounds.width > 0, bounds.height > 0, !rect.isNull, !rect.isEmpty else {
        return nil
    }
    return NormalizedRect(
        x: (rect.minX - bounds.minX) / bounds.width,
        y: 1 - (rect.maxY - bounds.minY) / bounds.height,
        width: rect.width / bounds.width,
        height: rect.height / bounds.height
    )
}

private func javaScriptString(_ value: String) -> String {
    guard let data = try? JSONEncoder().encode(value),
          let string = String(data: data, encoding: .utf8) else {
        return "\"\""
    }
    return string
}
