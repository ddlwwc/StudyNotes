import AppKit
import PDFKit
import StudyNotesKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

extension Notification.Name {
    static let studyNotesReaderScroll = Notification.Name(
        "StudyNotes.ReaderScroll"
    )
}

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
    @State private var lockError: String?

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

                        if session.isLocked {
                            Label("已锁定", systemImage: "lock.fill")
                                .font(.sn(10))
                                .foregroundStyle(SNColor.muted)
                        } else {
                            Picker(
                                "编辑模式",
                                selection: Binding(
                                    get: { session.mode },
                                    set: { newMode in
                                        if case let .blocked(reason) =
                                            session.setMode(newMode) {
                                            lockError = reason
                                        }
                                    }
                                )
                            ) {
                                Text("编辑")
                                    .tag(MarkdownEditorMode.edit)
                                Text("标注")
                                    .tag(MarkdownEditorMode.annotate)
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 124)
                        }

                        Spacer()

                        Button {
                            if case let .blocked(reason) =
                                session.requestAnnotation() {
                                lockError = reason
                            }
                        } label: {
                            Label("标注所选", systemImage: "highlighter")
                                .font(.sn(10))
                        }
                        .buttonStyle(.plain)
                        .disabled(
                            session.mode != .annotate
                                || session.selection?.hasTarget != true
                        )
                        .help(
                            session.mode == .annotate
                                ? "标注当前选区"
                                : "切换到标注模式后创建标注"
                        )

                        Button {
                            Task {
                                if case let .blocked(reason) =
                                    await session.lock() {
                                    lockError = reason
                                }
                            }
                        } label: {
                            Label(
                                session.isLocked ? "已锁定" : "完成编辑",
                                systemImage: session.isLocked
                                    ? "lock.fill"
                                    : "checkmark.circle"
                            )
                            .font(.sn(10))
                        }
                        .buttonStyle(.plain)
                        .disabled(session.isLocked)
                        .help(
                            session.isLocked
                                ? "正文已锁定，仍可创建和编辑标注"
                                : "保存正文并锁定编辑"
                        )

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
                        annotations: model.annotations,
                        activeAnnotationID: model.annotationJumpID,
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
                    activeAnnotationID: model.annotationJumpID,
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
                    },
                    onElementAnnotation: { target in
                        let elementType = AnnotationElementType(
                            rawValue: target.elementType
                        )
                        let selection = ReaderSelection(
                            quote: target.quote,
                            prefix: target.prefix,
                            suffix: target.suffix,
                            offset: target.offset,
                            blockPath: target.blockPath,
                            anchorKind: .text,
                            elementType: elementType,
                            contentFingerprint: ContentFingerprint.sha256(
                                target.fingerprintSource
                            ),
                            contentSummary: target.quote,
                            viewportY: target.viewportY
                        )
                        model.updateReaderSelection(selection)
                        model.presentAnnotationForCurrentSelection()
                    },
                    onAnnotationLayout: { positions in
                        model.updateAnnotationLayoutPositions(positions)
                    }
                )
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        model.beginMarkdownEditing()
                    }
                )
            }
        }
        .task(id: model.markdownEditorSession?.materialID) {
            configureMarkdownSession()
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
            "无法完成编辑",
            isPresented: Binding(
                get: { lockError != nil },
                set: { isPresented in
                    if !isPresented {
                        lockError = nil
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(lockError ?? "正文尚未保存。")
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

    private func configureMarkdownSession() {
        guard let session = model.markdownEditorSession else {
            return
        }
        session.onSelectionChanged = { selection in
            model.updateReaderSelection(
                selection.map(ReaderSelection.init(editorSelection:))
            )
        }
        session.onAnnotationRequested = { selection in
            model.updateReaderSelection(
                ReaderSelection(editorSelection: selection)
            )
            model.presentAnnotationForCurrentSelection()
        }
        session.onAnnotationClicked = { annotationID in
            model.annotationJumpID = annotationID
            model.studyPanelTab = .annotations
            model.isStudyPanelVisible = true
            if let annotation = model.annotations.first(
                where: { $0.id == annotationID }
            ) {
                model.presentAnnotationEditor(for: annotation)
            }
        }
        session.onAnnotationLayoutChanged = { positions in
            model.updateAnnotationLayoutPositions(positions)
        }
        session.updateAnnotations(model.annotations)
        session.selectAnnotation(model.annotationJumpID)
    }
}

private extension ReaderSelection {
    init(editorSelection: MarkdownEditorSelection) {
        self.init(
            quote: editorSelection.quote,
            prefix: editorSelection.prefix,
            suffix: editorSelection.suffix,
            offset: editorSelection.offset,
            blockPath: editorSelection.blockPath,
            anchorKind: .text,
            elementType: editorSelection.elementType,
            contentFingerprint: editorSelection.contentFingerprint,
            contentSummary: editorSelection.quote,
            viewportY: editorSelection.viewportY.map {
                CGFloat($0)
            }
        )
    }
}

private struct ArticleElementSelection: Equatable {
    let elementType: String
    let quote: String
    let prefix: String
    let suffix: String
    let offset: Int
    let blockPath: [Int]
    let fingerprintSource: String
    let viewportY: CGFloat?
}

private struct ArticleWebView: NSViewRepresentable {
    let document: MaterialDocument
    let annotations: [MaterialAnnotation]
    let jumpToAnnotationID: UUID?
    let activeAnnotationID: UUID?
    let headingID: String?
    let searchText: String
    let readingPreferences: ReadingPreferences
    let isDarkMode: Bool
    let onSelectionChanged: (ReaderSelection?) -> Void
    let onAnnotationClick: (UUID) -> Void
    var onElementAnnotation: ((ArticleElementSelection) -> Void)?
    var onAnnotationLayout: (([UUID: CGFloat]) -> Void)?
    var onReaderScrollChanged: ((CGFloat) -> Void)?

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
        configuration.userContentController.add(
            context.coordinator,
            name: "annotationLayout"
        )
        configuration.userContentController.add(
            context.coordinator,
            name: "elementAnnotationRequest"
        )
        configuration.userContentController.add(
            context.coordinator,
            name: "readerScrollChanged"
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
        context.coordinator.setActiveAnnotation(
            activeAnnotationID,
            in: webView
        )
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
        coordinator.stopObserving()
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: "selectionChanged"
        )
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: "annotationClick"
        )
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: "annotationLayout"
        )
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: "elementAnnotationRequest"
        )
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: "readerScrollChanged"
        )
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: ArticleWebView
        weak var webView: WKWebView?
        var documentID: UUID?
        private var loadedDocumentID: UUID?
        private var readingPreferencesSignature = ""
        private var runtimeInstalled = false
        private var scrollObserver: NSObjectProtocol?

        init(parent: ArticleWebView) {
            self.parent = parent
            super.init()
            scrollObserver = NotificationCenter.default.addObserver(
                forName: .studyNotesReaderScroll,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let delta = notification.object as? CGFloat else {
                    return
                }
                Task { @MainActor [weak self] in
                    guard let webView = self?.webView else {
                        return
                    }
                    _ = try? await webView.evaluateJavaScript(
                        "window.studyNotesScrollBy?.((\(delta)));"
                    )
                }
            }
        }

        func stopObserving() {
            if let scrollObserver {
                NotificationCenter.default.removeObserver(scrollObserver)
            }
            scrollObserver = nil
        }

        func load(document: MaterialDocument, in webView: WKWebView) {
            documentID = document.id
            loadedDocumentID = document.id
            runtimeInstalled = false
            readingPreferencesSignature = ""
            webView.loadHTMLString(
                document.renderedHTML,
                baseURL: document.sourceURL
            )
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            installRuntime(in: webView)
            applyReadingPreferences(
                parent.readingPreferences,
                isDarkMode: parent.isDarkMode,
                in: webView
            )
            applyAnnotations(parent.annotations, in: webView)
        }

        func installRuntime(in webView: WKWebView) {
            guard !runtimeInstalled else {
                return
            }
            runtimeInstalled = true
            webView.evaluateJavaScript(Self.runtimeJavaScript)
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
            html, body { scrollbar-width: none !important; }
            ::-webkit-scrollbar { display: none !important; width: 0 !important; height: 0 !important; }
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
            .study-annotation-active {
              outline: 2px solid #3370ff !important;
              outline-offset: 2px;
            }
            .study-element-annotation {
              border-radius: 3px;
              background: rgba(255, 225, 94, .34) !important;
              box-shadow: inset 0 -2px 0 #e3b500;
            }
            .study-image-annotation {
              outline: 2px solid #e3b500;
              outline-offset: 3px;
              box-shadow: inset 0 -4px 0 rgba(227, 181, 0, .55);
            }
            mark.study-annotation {
              background: rgba(255, 225, 94, .58) !important;
              border-radius: 3px;
              box-shadow: inset 0 -2px 0 #e3b500;
            }
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
                var item = [
                    "id": annotation.id.uuidString,
                    "quote": annotation.quote,
                    "note": annotation.note,
                    "unresolved": annotation.status == .unresolved,
                    "blockPath": annotation.anchor.blockPath
                ] as [String: Any]
                if let elementType = annotation.anchor.elementType {
                    item["elementType"] = elementType.rawValue
                }
                return item
            }
            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                  let json = String(data: data, encoding: .utf8) else {
                return
            }
            webView.evaluateJavaScript(
                "window.studyNotesApplyAnnotations(\(json));"
            )
        }

        func setActiveAnnotation(_ id: UUID?, in webView: WKWebView) {
            let value = id.map { javaScriptString($0.uuidString) } ?? "null"
            webView.evaluateJavaScript(
                "window.studyNotesSetActiveAnnotation?.(\(value));"
            )
        }

        func jump(to id: UUID, in webView: WKWebView) {
            webView.evaluateJavaScript(
                "window.studyNotesScrollToAnnotation?.(\(javaScriptString(id.uuidString)));"
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
                        anchorKind: .text,
                        viewportY: (payload["viewportY"] as? NSNumber)
                            .map { CGFloat(truncating: $0) }
                    )
                )
            case "annotationClick":
                guard let rawID = message.body as? String,
                      let id = UUID(uuidString: rawID) else {
                    return
                }
                parent.onAnnotationClick(id)
            case "annotationLayout":
                guard let payload = message.body as? [String: Any] else {
                    return
                }
                let positions = payload.reduce(into: [UUID: CGFloat]()) {
                    result, entry in
                    guard let id = UUID(uuidString: entry.key),
                          let position = entry.value as? NSNumber else {
                        return
                    }
                    result[id] = CGFloat(truncating: position)
                }
                parent.onAnnotationLayout?(positions)
            case "elementAnnotationRequest":
                guard let payload = message.body as? [String: Any],
                      let elementType = payload["elementType"] as? String,
                      let quote = payload["quote"] as? String,
                      !quote.isEmpty else {
                    return
                }
                parent.onElementAnnotation?(
                    ArticleElementSelection(
                        elementType: elementType,
                        quote: quote,
                        prefix: payload["prefix"] as? String ?? "",
                        suffix: payload["suffix"] as? String ?? "",
                        offset: payload["offset"] as? Int ?? 0,
                        blockPath: payload["blockPath"] as? [Int] ?? [],
                        fingerprintSource: payload["fingerprintSource"] as? String
                            ?? quote,
                        viewportY: (payload["viewportY"] as? NSNumber)
                            .map { CGFloat(truncating: $0) }
                    )
                )
            case "readerScrollChanged":
                guard let offset = message.body as? NSNumber else {
                    return
                }
                parent.onReaderScrollChanged?(CGFloat(truncating: offset))
            default:
                break
            }
        }

        private static let runtimeJavaScript = #"""
        (() => {
          if (window.__studyNotesRuntimeInstalled) return;
          window.__studyNotesRuntimeInstalled = true;

          const article = document.querySelector('article');
          if (!article) return;

          const post = (name, payload) => {
            window.webkit.messageHandlers[name].postMessage(payload);
          };
          const truncate = (value, length = 160) => {
            const text = (value || '').replace(/\s+/g, ' ').trim();
            return text.length > length ? `${text.slice(0, length - 1)}…` : text;
          };
          const elementPath = (element) => {
            const path = [];
            let node = element;
            while (node && node !== article) {
              const parent = node.parentElement;
              if (!parent) return [];
              path.unshift(Array.from(parent.children).indexOf(node));
              node = parent;
            }
            return node === article ? path : [];
          };
          const elementAtPath = (path) => {
            if (!Array.isArray(path)) return null;
            const key = path.join('/');
            const tagged = Array.from(
              article.querySelectorAll('[data-block-path]')
            ).find((element) => element.dataset.blockPath === key);
            if (tagged) return tagged;
            let node = article;
            for (const index of path) {
              node = node?.children?.[index];
              if (!node) return null;
            }
            return node === article ? null : node;
          };
          const kindFor = (element) => {
            if (!element || element === article || element.matches('hr')) return null;
            if (element.closest('table')) return 'table';
            if (element.closest('pre')) return 'codeBlock';
            if (element.matches('img')) return 'image';
            if (element.closest('li')) return 'listItem';
            if (element.closest('blockquote')) return 'blockquote';
            if (element.closest('h1, h2, h3, h4, h5, h6')) return 'heading';
            if (element.closest('p')) return 'paragraph';
            return null;
          };
          const targetFor = (node) => {
            const element = node?.nodeType === Node.ELEMENT_NODE ? node : node?.parentElement;
            if (!element || !article.contains(element)) return null;
            const kind = kindFor(element);
            if (!kind) return null;
            if (kind === 'table') return [element.closest('table'), kind];
            if (kind === 'codeBlock') return [element.closest('pre'), kind];
            if (kind === 'image') return [element.closest('img'), kind];
            if (kind === 'listItem') return [element.closest('li'), kind];
            if (kind === 'blockquote') return [element.closest('blockquote'), kind];
            if (kind === 'heading') return [element.closest('h1, h2, h3, h4, h5, h6'), kind];
            return [element.closest('p'), kind];
          };
          const canonicalTarget = (element, kind) => [
            element,
            element.dataset.elementType || kind
          ];
          const canonicalPath = (element) => {
            const value = element.dataset.blockPath;
            if (!value) return elementPath(element);
            return value
              .split('/')
              .map((component) => Number.parseInt(component, 10))
              .filter(Number.isFinite);
          };
          const summaryFor = (element, kind) => {
            if (kind === 'image') {
              return truncate(
                element.alt
                  || element.title
                  || element.dataset.mediaKey
                  || element.getAttribute('src')
                  || '图片'
              );
            }
            if (kind === 'table') {
              return truncate(
                Array.from(element.rows)
                  .slice(0, 2)
                  .map((row) => Array.from(row.cells).map((cell) => cell.innerText).join(' | '))
                  .join(' / ')
              );
            }
            if (kind === 'codeBlock') {
              return truncate(element.textContent || '代码块');
            }
            return truncate(element.innerText || element.textContent);
          };
          const menuLabel = (kind) => ({
            heading: '标注此标题',
            paragraph: '标注此段落',
            blockquote: '标注此引用',
            listItem: '标注此列表项',
            image: '标注此图片',
            table: '标注此表格',
            codeBlock: '标注此代码块'
          })[kind] || '标注此元素';
          const closeMenu = () => {
            document.getElementById('studynotes-element-menu')?.remove();
          };
          const showMenu = (x, y, label, action) => {
            closeMenu();
            const menu = document.createElement('div');
            menu.id = 'studynotes-element-menu';
            menu.style.cssText = [
              'position:fixed',
              `left:${Math.min(x, window.innerWidth - 170)}px`,
              `top:${Math.min(y, window.innerHeight - 52)}px`,
              'z-index:2147483647',
              'padding:5px',
              'border:1px solid rgba(127,127,127,.35)',
              'border-radius:7px',
              'background:Canvas',
              'box-shadow:0 8px 28px rgba(0,0,0,.18)'
            ].join(';');
            const button = document.createElement('button');
            button.type = 'button';
            button.textContent = label;
            button.style.cssText = [
              'display:block',
              'width:100%',
              'padding:6px 10px',
              'border:0',
              'border-radius:4px',
              'background:transparent',
              'color:CanvasText',
              'font:12px -apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif',
              'text-align:left',
              'white-space:nowrap'
            ].join(';');
            button.addEventListener('click', () => {
              closeMenu();
              action();
            });
            menu.append(button);
            document.body.append(menu);
            setTimeout(() => {
              document.addEventListener('pointerdown', closeMenu, { once: true });
            }, 0);
          };

          window.studyNotesSetActiveAnnotation = (id) => {
            window.__studyNotesActiveAnnotation = id;
            document.querySelectorAll('.study-annotation-active').forEach((element) => {
              element.classList.remove('study-annotation-active');
            });
            if (!id) return;
            document.querySelectorAll(
              `[data-annotation-id="${CSS.escape(id)}"], [data-study-annotation-id="${CSS.escape(id)}"]`
            ).forEach((element) => element.classList.add('study-annotation-active'));
          };
          window.studyNotesScrollToAnnotation = (id) => {
            const element = document.querySelector(
              `[data-annotation-id="${CSS.escape(id)}"], [data-study-annotation-id="${CSS.escape(id)}"]`
            );
            element?.scrollIntoView({ block: 'center', behavior: 'smooth' });
          };
          window.studyNotesScrollBy = (delta) => {
            if (Number.isFinite(delta)) window.scrollBy(0, delta);
          };

          const unwrap = (element) => {
            const parent = element.parentNode;
            if (!parent) return;
            while (element.firstChild) parent.insertBefore(element.firstChild, element);
            parent.removeChild(element);
          };
          const applyText = (item) => {
            if (!item.quote) return;
            const walker = document.createTreeWalker(article, NodeFilter.SHOW_TEXT);
            let node;
            while ((node = walker.nextNode())) {
              if (node.parentElement?.closest('mark.study-annotation')) continue;
              const index = node.nodeValue.indexOf(item.quote);
              if (index < 0) continue;
              const range = document.createRange();
              range.setStart(node, index);
              range.setEnd(node, index + item.quote.length);
              try {
                const mark = document.createElement('mark');
                mark.className = 'study-annotation'
                  + (item.unresolved ? ' unresolved' : '')
                  + (item.active ? ' study-annotation-active' : '');
                mark.dataset.annotationId = item.id;
                mark.title = item.note || item.quote;
                range.surroundContents(mark);
              } catch {}
              break;
            }
          };
          const applyElement = (item) => {
            if (!item.elementType || item.unresolved) return;
            let element = elementAtPath(item.blockPath);
            const normalized = (value) => (value || '').replace(/\s+/g, ' ').trim();
            const contentFor = (candidate) => normalized(
              candidate?.dataset.elementType === 'image'
                ? candidate.getAttribute('alt')
                  || candidate.getAttribute('title')
                  || candidate.dataset.mediaKey
                  || candidate.getAttribute('src')
                  || ''
                : candidate?.innerText || candidate?.textContent || ''
            );
            if (!contentFor(element).includes(normalized(item.quote))) {
              const matches = Array.from(
                article.querySelectorAll(
                  `[data-element-type="${CSS.escape(item.elementType)}"]`
                )
              ).filter((candidate) => contentFor(candidate)
                .includes(normalized(item.quote)));
              if (matches.length > 0) {
                const full = article.innerText || article.textContent || '';
                const ranked = matches.map((candidate) => {
                  const range = document.createRange();
                  range.selectNodeContents(article);
                  range.setEndBefore(candidate);
                  const offset = range.toString().length;
                  const before = normalized(
                    full.slice(Math.max(0, offset - 48), offset)
                  );
                  const after = normalized(
                    full.slice(offset, offset + 48)
                  );
                  const prefix = normalized(item.prefix);
                  const suffix = normalized(item.suffix);
                  let score = 0;
                  if (prefix && before.endsWith(prefix)) score += 2;
                  if (suffix && after.startsWith(suffix)) score += 2;
                  return { candidate, score };
                });
                const bestScore = Math.max(...ranked.map((entry) => entry.score));
                const best = ranked.filter((entry) => entry.score === bestScore);
                if (best.length === 1) element = best[0].candidate;
              }
            }
            if (!element) return;
            element.dataset.studyAnnotationId = item.id;
            element.classList.add('study-element-annotation');
            if (item.elementType === 'image') {
              element.classList.add('study-image-annotation');
            }
            if (item.active) element.classList.add('study-annotation-active');
          };
          window.studyNotesApplyAnnotations = (items) => {
            document.querySelectorAll('mark.study-annotation').forEach(unwrap);
            document.querySelectorAll('[data-study-annotation-id]').forEach((element) => {
              element.classList.remove(
                'study-element-annotation',
                'study-image-annotation',
                'study-annotation-active'
              );
              delete element.dataset.studyAnnotationId;
            });
            for (const item of Array.isArray(items) ? items : []) {
              if (item.elementType) applyElement(item);
              else applyText(item);
            }
            window.studyNotesSetActiveAnnotation(window.__studyNotesActiveAnnotation);
            requestAnimationFrame(reportLayout);
          };

          article.addEventListener('click', (event) => {
            const text = event.target.closest?.('mark[data-annotation-id]');
            if (text) {
              event.preventDefault();
              post('annotationClick', text.dataset.annotationId);
              return;
            }
            const element = event.target.closest?.('[data-study-annotation-id]');
            if (element) {
              event.preventDefault();
              post('annotationClick', element.dataset.studyAnnotationId);
            }
          });

          article.addEventListener('contextmenu', (event) => {
            const selection = window.studyNotesCurrentSelection?.();
            if (selection) {
              event.preventDefault();
              showMenu(event.clientX, event.clientY, '标注所选文字', () => {
                post('elementAnnotationRequest', {
                  elementType: 'text',
                  quote: selection.quote,
                  prefix: selection.prefix,
                  suffix: selection.suffix,
                  offset: selection.offset,
                  blockPath: selection.blockPath,
                  fingerprintSource: selection.quote,
                  viewportY: selection.viewportY
                });
              });
              return;
            }

            const target = targetFor(event.target);
            if (!target?.[0]) return;
            const [element, rawKind] = target;
            const [canonicalElement, kind] = canonicalTarget(
              element,
              rawKind
            );
            event.preventDefault();
            showMenu(event.clientX, event.clientY, menuLabel(kind), () => {
              const summary = summaryFor(canonicalElement, kind);
              if (!summary) return;
              const preRange = document.createRange();
              preRange.selectNodeContents(article);
              preRange.setEndBefore(canonicalElement);
              const offset = preRange.toString().length;
              const full = article.innerText || article.textContent || '';
              post('elementAnnotationRequest', {
                elementType: kind,
                quote: summary,
                prefix: full.slice(Math.max(0, offset - 48), offset),
                suffix: full.slice(offset, offset + 48),
                offset,
                blockPath: canonicalPath(canonicalElement),
                fingerprintSource: canonicalElement.innerText
                  || canonicalElement.textContent
                  || canonicalElement.getAttribute('alt')
                  || summary,
                viewportY: canonicalElement.getBoundingClientRect().top
              });
            });
          });

          let layoutFrame = 0;
          function reportLayout() {
            cancelAnimationFrame(layoutFrame);
            layoutFrame = requestAnimationFrame(() => {
              const positions = {};
              article.querySelectorAll(
                'mark[data-annotation-id], [data-study-annotation-id]'
              ).forEach((element) => {
                const id = element.dataset.annotationId || element.dataset.studyAnnotationId;
                if (!id || element.classList.contains('unresolved')) return;
                positions[id] = element.getBoundingClientRect().top;
              });
              post('annotationLayout', positions);
              post('readerScrollChanged', window.scrollY);
            });
          }
          window.addEventListener('scroll', reportLayout, { passive: true });
          window.addEventListener('resize', reportLayout, { passive: true });
          new ResizeObserver(reportLayout).observe(article);
          requestAnimationFrame(reportLayout);
        })();
        """#
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
        Self.hideScrollbars(in: pdfView)
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
        Self.hideScrollbars(in: pdfView)
    }

    static func dismantleNSView(_ pdfView: SelectablePDFView, coordinator: Coordinator) {
        coordinator.stopObserving()
        pdfView.onPageRegion = nil
    }

    private static func hideScrollbars(in view: NSView) {
        if let scrollView = view as? NSScrollView {
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true
        }
        for subview in view.subviews {
            hideScrollbars(in: subview)
        }
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
                .scrollIndicators(.hidden)
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
