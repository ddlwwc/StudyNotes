#if canImport(SwiftUI) && canImport(WebKit)
import SwiftUI
import WebKit

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

public struct MarkdownEditorView: View {
    @Bindable private var session: MarkdownEditorSession
    private let onAttachmentRequested:
        ((MarkdownEditorAttachmentKind) -> Void)?
    private let readingPreferences: ReadingPreferences
    private let mediaCoordinator: NoteMediaCoordinator?
    private let annotations: [MaterialAnnotation]
    private let activeAnnotationID: UUID?
    @Environment(\.colorScheme) private var colorScheme

    public init(
        session: MarkdownEditorSession,
        annotations: [MaterialAnnotation] = [],
        activeAnnotationID: UUID? = nil,
        readingPreferences: ReadingPreferences = .init(),
        mediaCoordinator: NoteMediaCoordinator? = nil,
        onAttachmentRequested:
            ((MarkdownEditorAttachmentKind) -> Void)? = nil
    ) {
        _session = Bindable(session)
        self.annotations = annotations
        self.activeAnnotationID = activeAnnotationID
        self.readingPreferences = readingPreferences
        self.mediaCoordinator = mediaCoordinator
        self.onAttachmentRequested = onAttachmentRequested
    }

    public var body: some View {
        MarkdownEditorNativeView(
            session: session,
            isDarkMode: colorScheme == .dark,
            readingPreferences: readingPreferences,
            mediaCoordinator: mediaCoordinator,
            onAttachmentRequested: onAttachmentRequested
        )
        .onAppear {
            session.updateAnnotations(annotations)
            session.selectAnnotation(activeAnnotationID)
        }
        .onChange(of: annotations) { _, newValue in
            session.updateAnnotations(newValue)
        }
        .onChange(of: activeAnnotationID) { _, newValue in
            session.selectAnnotation(newValue)
        }
        .onDisappear {
            Task { await session.flush(.materialSwitch) }
        }
    }
}

#if os(macOS)
private struct MarkdownEditorNativeView: NSViewRepresentable {
    let session: MarkdownEditorSession
    let isDarkMode: Bool
    let readingPreferences: ReadingPreferences
    let mediaCoordinator: NoteMediaCoordinator?
    let onAttachmentRequested:
        ((MarkdownEditorAttachmentKind) -> Void)?

    func makeCoordinator() -> MarkdownEditorWebCoordinator {
        MarkdownEditorWebCoordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = makeWebView(
            coordinator: context.coordinator,
            mediaCoordinator: mediaCoordinator
        )
        context.coordinator.attach(
            webView: webView,
            session: session,
            isDarkMode: isDarkMode,
            readingPreferences: readingPreferences,
            onAttachmentRequested: onAttachmentRequested
        )
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.update(
            session: session,
            isDarkMode: isDarkMode,
            readingPreferences: readingPreferences,
            onAttachmentRequested: onAttachmentRequested
        )
    }

    static func dismantleNSView(
        _ webView: WKWebView,
        coordinator: Coordinator
    ) {
        coordinator.detach(webView: webView)
    }
}
#elseif os(iOS)
private struct MarkdownEditorNativeView: UIViewRepresentable {
    let session: MarkdownEditorSession
    let isDarkMode: Bool
    let readingPreferences: ReadingPreferences
    let mediaCoordinator: NoteMediaCoordinator?
    let onAttachmentRequested:
        ((MarkdownEditorAttachmentKind) -> Void)?

    func makeCoordinator() -> MarkdownEditorWebCoordinator {
        MarkdownEditorWebCoordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = makeWebView(
            coordinator: context.coordinator,
            mediaCoordinator: mediaCoordinator
        )
        context.coordinator.attach(
            webView: webView,
            session: session,
            isDarkMode: isDarkMode,
            readingPreferences: readingPreferences,
            onAttachmentRequested: onAttachmentRequested
        )
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.update(
            session: session,
            isDarkMode: isDarkMode,
            readingPreferences: readingPreferences,
            onAttachmentRequested: onAttachmentRequested
        )
    }

    static func dismantleUIView(
        _ webView: WKWebView,
        coordinator: Coordinator
    ) {
        coordinator.detach(webView: webView)
    }
}
#endif

@MainActor
private func makeWebView(
    coordinator: MarkdownEditorWebCoordinator,
    mediaCoordinator: NoteMediaCoordinator?
) -> WKWebView {
    let resource = MarkdownEditorResources.webResource
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = true
    configuration.userContentController.add(
        coordinator,
        name: resource.messageHandlerName
    )
    if let mediaCoordinator {
        configuration.setURLSchemeHandler(
            MarkdownMediaSchemeHandler(coordinator: mediaCoordinator),
            forURLScheme: "media"
        )
    }
    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.navigationDelegate = coordinator
    #if os(macOS)
    webView.setValue(false, forKey: "drawsBackground")
    #elseif os(iOS)
    webView.isOpaque = false
    webView.backgroundColor = .clear
    webView.scrollView.backgroundColor = .clear
    #endif
    coordinator.load(resource: resource, in: webView)
    return webView
}

@MainActor
private final class MarkdownEditorWebCoordinator:
    NSObject,
    WKNavigationDelegate,
    WKScriptMessageHandler,
    WKUIDelegate,
    MarkdownEditorHosting
{
    private(set) var resource: MarkdownEditorWebResource?
    private weak var webView: WKWebView?
    private weak var session: MarkdownEditorSession?
    private var isDarkMode = false
    private var readingPreferences = ReadingPreferences()
    private var onAttachmentRequested:
        ((MarkdownEditorAttachmentKind) -> Void)?
    private var lifecycleObservers: [NSObjectProtocol] = []

    override init() {
        super.init()
    }

    func attach(
        webView: WKWebView,
        session: MarkdownEditorSession,
        isDarkMode: Bool,
        readingPreferences: ReadingPreferences,
        onAttachmentRequested:
            ((MarkdownEditorAttachmentKind) -> Void)?
    ) {
        self.webView = webView
        self.session = session
        self.isDarkMode = isDarkMode
        self.readingPreferences = readingPreferences
        self.onAttachmentRequested = onAttachmentRequested
        webView.uiDelegate = self
        session.attach(self)
        observeLifecycle()
    }

    func update(
        session: MarkdownEditorSession,
        isDarkMode: Bool,
        readingPreferences: ReadingPreferences,
        onAttachmentRequested:
            ((MarkdownEditorAttachmentKind) -> Void)?
    ) {
        if self.session !== session {
            self.session = session
            session.attach(self)
        }
        self.onAttachmentRequested = onAttachmentRequested
        self.readingPreferences = readingPreferences
        if self.isDarkMode != isDarkMode {
            self.isDarkMode = isDarkMode
            applyAppearance()
        } else {
            applyTypography()
        }
    }

    func load(
        resource: MarkdownEditorWebResource,
        in webView: WKWebView
    ) {
        self.resource = resource
        webView.loadFileURL(
            resource.htmlURL,
            allowingReadAccessTo: resource.baseURL
        )
    }

    func detach(webView: WKWebView) {
        webView.configuration.userContentController
            .removeScriptMessageHandler(
                forName: resource?.messageHandlerName
                    ?? MarkdownEditorResources.messageHandlerName
            )
        lifecycleObservers.forEach(
            NotificationCenter.default.removeObserver
        )
        lifecycleObservers = []
    }

    func loadMarkdownEditor(
        _ resource: MarkdownEditorWebResource
    ) throws {
        guard let webView else {
            return
        }
        load(resource: resource, in: webView)
    }

    func send(_ message: MarkdownEditorBridgeMessage) async throws {
        guard let webView else {
            return
        }
        let data = try JSONEncoder().encode(message)
        guard let json = String(data: data, encoding: .utf8) else {
            throw MarkdownEditorWebError.invalidMessage
        }
        let script = """
        (() => {
          const message = \(json);
          window.StudyNotesEditor?.receive(message);
          window.__StudyNotesDocumentRuntime?.receive(message);
        })();
        """
        _ = try await webView.evaluateJavaScript(script)
    }

    func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        applyAppearance()
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            await installDocumentRuntime()
            self.session?.editorRuntimeDidLoad()
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler:
            @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        if url.isFileURL || url.scheme == "about" {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
        }
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let session else {
            return
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: message.body)
            let bridgeMessage = try JSONDecoder().decode(
                MarkdownEditorBridgeMessage.self,
                from: data
            )
            if case let .attachRequested(kind) = bridgeMessage {
                onAttachmentRequested?(kind)
            } else {
                session.receive(bridgeMessage)
            }
        } catch {
            session.receive(.failed(
                reason: "编辑器消息无法解析：\(error.localizedDescription)"
            ))
        }
    }

    #if os(macOS)
    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler:
            @escaping @MainActor @Sendable (String?) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = prompt
        let field = NSTextField(
            frame: NSRect(x: 0, y: 0, width: 320, height: 24)
        )
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        completionHandler(
            alert.runModal() == .alertFirstButtonReturn
                ? field.stringValue
                : nil
        )
    }
    #elseif os(iOS)
    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler:
            @escaping @MainActor @Sendable (String?) -> Void
    ) {
        guard let presenter = webView.window?.rootViewController else {
            completionHandler(defaultText)
            return
        }
        let alert = UIAlertController(
            title: prompt,
            message: nil,
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.text = defaultText
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in
            completionHandler(nil)
        })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
            completionHandler(alert.textFields?.first?.text)
        })
        presenter.present(alert, animated: true)
    }
    #endif

    private func applyAppearance() {
        webView?.evaluateJavaScript(
            "window.StudyNotesEditor?.setTheme('\(isDarkMode ? "dark" : "light")');"
        )
        applyTypography()
    }

    private func installDocumentRuntime() async {
        guard let webView else {
            return
        }
        _ = try? await webView.evaluateJavaScript(
            Self.documentRuntimeJavaScript
        )
    }

    private func applyTypography() {
        let codeFontLiteral = (try? JSONEncoder().encode(
            readingPreferences.codeFont
        )).flatMap { String(data: $0, encoding: .utf8) }
            ?? "\"SFMono-Regular\""
        let script = """
        (() => {
          const editor = document.querySelector('.tiptap');
          const source = document.getElementById('source');
          for (const node of [editor, source]) {
            if (!node) continue;
            node.style.fontSize = '\(readingPreferences.fontSize)px';
            node.style.lineHeight = '\(readingPreferences.lineHeight)';
          }
          if (editor) {
            editor.style.maxWidth = '\(readingPreferences.lineWidth)px';
            editor.style.margin = '0 auto';
          }
          if (source) {
            source.style.fontFamily = \(codeFontLiteral);
          }
        })();
        """
        webView?.evaluateJavaScript(script)
    }

    private static let documentRuntimeJavaScript = #"""
    (() => {
      const editorRoot =
        document.querySelector('#editor .tiptap') ??
        document.querySelector('.tiptap');
      if (!editorRoot) return;
      if (window.__StudyNotesDocumentRuntime) {
        window.__StudyNotesDocumentRuntime.refresh();
        return;
      }

      const bridge = window.webkit?.messageHandlers?.markdownEditor;
      const editorHost = document.getElementById('editor-host');
      const titleInput = document.getElementById('title');
      const sourceText = document.getElementById('source');
      const sourceToggle = document.getElementById('source-toggle');
      const body = document.body;

      const style = document.createElement('style');
      style.id = 'studynotes-document-runtime-style';
      style.textContent = `
        body[data-document-mode="annotate"] #toolbar button[data-command],
        body[data-document-mode="annotate"] #toolbar .separator,
        body[data-document-mode="annotate"] #attach-image,
        body[data-document-mode="annotate"] #attach-file,
        body[data-document-mode="annotate"] #source-toggle,
        body[data-document-mode="annotate"] .drag-handle {
          display: none !important;
        }
        body[data-document-mode="annotate"] #title {
          pointer-events: none;
        }
        body[data-document-mode="annotate"] .tiptap {
          caret-color: transparent;
        }
        #studynotes-annotation-layer {
          position: fixed;
          inset: 0;
          z-index: 12;
          overflow: hidden;
          pointer-events: none;
        }
        .studynotes-annotation-overlay {
          position: absolute;
          border-radius: 3px;
          background: rgba(255, 225, 94, .3);
          box-shadow: inset 0 -2px 0 rgba(227, 181, 0, .85);
        }
        .studynotes-annotation-overlay.active {
          background: rgba(51, 112, 255, .2);
          outline: 2px solid rgba(47, 111, 237, .85);
          outline-offset: 1px;
        }
        .studynotes-annotation-overlay.unresolved {
          background: rgba(255, 159, 10, .14);
          outline: 1px dashed #d97706;
          box-shadow: none;
        }
      `;
      document.head.append(style);

      const annotationLayer = document.createElement('div');
      annotationLayer.id = 'studynotes-annotation-layer';
      body.append(annotationLayer);

      const state = {
        isLocked: false,
        mode: 'edit',
        annotations: [],
        activeAnnotationID: null
      };
      let hitRects = [];
      let refreshFrame = 0;
      let selectionTimer = 0;
      let savedDOMRange = null;
      let savedScrollTop = 0;
      let lastSelectionSignature = '';
      let lastUnresolvedSignature = '';
      let lastLayoutSignature = '';

      const post = message => bridge?.postMessage(message);
      const normalize = value =>
        String(value ?? '').replace(/\s+/g, ' ').trim();

      const blockFor = node => {
        let element = node?.nodeType === Node.ELEMENT_NODE
          ? node
          : node?.parentElement;
        while (element && element.parentElement !== editorRoot) {
          element = element.parentElement;
        }
        return element?.parentElement === editorRoot ? element : null;
      };

      const blockPathFor = block => {
        if (!block) return [];
        const index = Array.from(editorRoot.children).indexOf(block);
        return index >= 0 ? [index] : [];
      };

      const elementTypeFor = element => {
        if (!element) return null;
        if (element.matches('h1, h2, h3, h4, h5, h6')) return 'heading';
        if (element.matches('blockquote')) return 'blockquote';
        if (element.matches('li')) return 'listItem';
        if (element.matches('img')) return 'image';
        if (element.matches('table')) return 'table';
        if (element.matches('pre')) return 'codeBlock';
        if (element.matches('p')) return 'paragraph';
        return null;
      };

      const buildTextIndex = () => {
        const walker = document.createTreeWalker(
          editorRoot,
          NodeFilter.SHOW_TEXT,
          {
            acceptNode(node) {
              if (!node.nodeValue) return NodeFilter.FILTER_REJECT;
              if (node.parentElement?.closest('.compat-label')) {
                return NodeFilter.FILTER_REJECT;
              }
              return NodeFilter.FILTER_ACCEPT;
            }
          }
        );
        let text = '';
        const points = [];
        let previousBlock = null;
        let node;
        while ((node = walker.nextNode())) {
          const block = blockFor(node);
          if (previousBlock && block && block !== previousBlock
              && text && !text.endsWith(' ')) {
            text += ' ';
            points.push({ node, offset: 0 });
          }
          for (let index = 0; index < node.nodeValue.length; index += 1) {
            const character = node.nodeValue[index];
            if (/\s/.test(character)) {
              if (!text || !text.endsWith(' ')) {
                text += ' ';
                points.push({ node, offset: index });
              }
            } else {
              text += character;
              points.push({ node, offset: index });
            }
          }
          previousBlock = block ?? previousBlock;
        }
        return { text, points };
      };

      const rangeForOccurrence = (index, length) => {
        const start = index.points[index];
        const end = index.points[index + length - 1];
        if (!start || !end) return null;
        const range = document.createRange();
        try {
          range.setStart(start.node, start.offset);
          range.setEnd(end.node, end.offset + 1);
          return range;
        } catch {
          return null;
        }
      };

      const resolveTextRange = (annotation, index) => {
        const quote = normalize(annotation.quote);
        if (!quote) return null;
        const prefix = normalize(annotation.prefix);
        const suffix = normalize(annotation.suffix);
        const candidates = [];
        let position = index.text.indexOf(quote);
        while (position >= 0) {
          let score = 0;
          if (prefix && normalize(
            index.text.slice(Math.max(0, position - prefix.length), position)
          ).endsWith(prefix)) {
            score += 4;
          }
          if (suffix && normalize(
            index.text.slice(
              position + quote.length,
              position + quote.length + suffix.length
            )
          ).startsWith(suffix)) {
            score += 4;
          }
          const block = blockFor(index.points[position]?.node);
          const blockPath = blockPathFor(block);
          if (annotation.blockPath?.length
              && annotation.blockPath[0] === blockPath[0]) {
            score += 8;
          }
          if (Number.isFinite(annotation.offset)) {
            score -= Math.min(
              Math.abs(annotation.offset - position) / 1000,
              2
            );
          }
          candidates.push({ position, score });
          position = index.text.indexOf(
            quote,
            position + quote.length
          );
        }
        if (!candidates.length) return null;
        const bestScore = Math.max(...candidates.map(item => item.score));
        const best = candidates.filter(item => item.score === bestScore);
        if (best.length !== 1) return null;
        return rangeForOccurrence(index, best[0].position, quote.length);
      };

      const elementMatchesType = (element, elementType) =>
        !elementType || elementTypeFor(element) === elementType;

      const resolveElementRange = annotation => {
        const pathIndex = annotation.blockPath?.[0];
        let candidate = Number.isInteger(pathIndex)
          ? editorRoot.children[pathIndex]
          : null;
        if (!candidate || !elementMatchesType(
          candidate,
          annotation.elementType
        )) {
          candidate = null;
        }
        if (!candidate) {
          const selector = annotation.elementType === 'image'
            ? 'img'
            : annotation.elementType === 'table'
            ? 'table'
            : annotation.elementType === 'codeBlock'
            ? 'pre'
            : annotation.elementType === 'heading'
            ? 'h1, h2, h3, h4, h5, h6'
            : annotation.elementType === 'blockquote'
            ? 'blockquote'
            : annotation.elementType === 'listItem'
            ? 'li'
            : 'p';
          const quote = normalize(annotation.quote);
          const matches = Array.from(
            editorRoot.querySelectorAll(selector)
          ).filter(element => {
            const value = normalize(
              element.matches('img')
                ? element.getAttribute('alt')
                  || element.getAttribute('title')
                  || element.getAttribute('src')
                : element.innerText || element.textContent
            );
            return quote && value.includes(quote);
          });
          if (matches.length === 1) candidate = matches[0];
        }
        if (!candidate) return null;
        if (candidate.matches('img')) {
          return candidate.getBoundingClientRect();
        }
        const range = document.createRange();
        range.selectNodeContents(candidate);
        return range;
      };

      const appendOverlay = (rect, annotation) => {
        if (!rect || rect.width < 1 || rect.height < 1) return;
        const element = document.createElement('div');
        element.className = 'studynotes-annotation-overlay'
          + (annotation.unresolved ? ' unresolved' : '')
          + (annotation.id === state.activeAnnotationID ? ' active' : '');
        element.style.left = `${rect.left}px`;
        element.style.top = `${rect.top}px`;
        element.style.width = `${rect.width}px`;
        element.style.height = `${rect.height}px`;
        annotationLayer.append(element);
        hitRects.push({
          id: annotation.id,
          left: rect.left,
          top: rect.top,
          right: rect.right,
          bottom: rect.bottom
        });
      };

      const refreshAnnotations = () => {
        annotationLayer.replaceChildren();
        hitRects = [];
        const unresolved = [];
        const layout = {};
        const textIndex = buildTextIndex();
        for (const annotation of state.annotations) {
          const resolved = annotation.elementType
            ? resolveElementRange(annotation)
            : resolveTextRange(annotation, textIndex);
          if (!resolved || annotation.unresolved) {
            unresolved.push(annotation.id);
          }
          if (!resolved) continue;
          let firstTop = null;
          if (resolved instanceof Range) {
            for (const rect of resolved.getClientRects()) {
              appendOverlay(rect, annotation);
              firstTop ??= rect.top;
            }
          } else {
            appendOverlay(resolved, annotation);
            firstTop = resolved.top;
          }
          if (Number.isFinite(firstTop)) {
            layout[annotation.id] = firstTop;
          }
        }
        const unresolvedSignature = JSON.stringify(
          [...unresolved].sort()
        );
        if (unresolvedSignature !== lastUnresolvedSignature) {
          lastUnresolvedSignature = unresolvedSignature;
          post({
            type: 'unresolvedAnnotationIDsChanged',
            unresolvedAnnotationIDs: [...unresolved].sort()
          });
        }
        const layoutSignature = JSON.stringify(layout);
        if (layoutSignature !== lastLayoutSignature) {
          lastLayoutSignature = layoutSignature;
          post({ type: 'annotationLayoutChanged', annotationLayout: layout });
        }
      };

      const scheduleRefresh = () => {
        cancelAnimationFrame(refreshFrame);
        refreshFrame = requestAnimationFrame(refreshAnnotations);
      };

      const selectionPayload = () => {
        const selection = window.getSelection();
        if (!selection?.rangeCount || selection.isCollapsed) return null;
        const range = selection.getRangeAt(0);
        if (!editorRoot.contains(range.commonAncestorContainer)
            && !editorRoot.contains(range.startContainer)) {
          return null;
        }
        const quote = normalize(range.toString());
        if (!quote) return null;
        const block = blockFor(range.startContainer);
        const blockText = normalize(
          block?.innerText || block?.textContent || editorRoot.innerText
        );
        const localOffset = blockText.indexOf(quote);
        const offset = localOffset >= 0 ? localOffset : 0;
        const prefix = localOffset >= 0
          ? blockText.slice(Math.max(0, localOffset - 48), localOffset)
          : '';
        const suffix = localOffset >= 0
          ? blockText.slice(
              localOffset + quote.length,
              localOffset + quote.length + 48
            )
          : '';
        const rect = range.getBoundingClientRect();
        return {
          quote,
          prefix,
          suffix,
          offset,
          blockPath: blockPathFor(block),
          elementType: elementTypeFor(block),
          contentFingerprint: quote,
          viewportY: Number.isFinite(rect.top) ? rect.top : null
        };
      };

      const reportSelection = () => {
        if (state.mode !== 'annotate') return;
        const selection = selectionPayload();
        const signature = JSON.stringify(selection);
        if (signature === lastSelectionSignature) return;
        lastSelectionSignature = signature;
        post({ type: 'selectionChanged', selection });
      };

      const scheduleSelectionReport = () => {
        window.clearTimeout(selectionTimer);
        selectionTimer = window.setTimeout(reportSelection, 40);
      };

      const captureInteractionState = () => {
        savedScrollTop = editorHost?.scrollTop ?? 0;
        const selection = window.getSelection();
        savedDOMRange = selection?.rangeCount
          ? selection.getRangeAt(0).cloneRange()
          : null;
      };

      const restoreInteractionState = () => {
        requestAnimationFrame(() => {
          if (editorHost) editorHost.scrollTop = savedScrollTop;
          if (savedDOMRange) {
            const selection = window.getSelection();
            selection.removeAllRanges();
            try {
              selection.addRange(savedDOMRange);
            } catch {}
          }
          scheduleRefresh();
          scheduleSelectionReport();
        });
      };

      const applyRuntimeState = () => {
        captureInteractionState();
        const annotate = state.isLocked || state.mode === 'annotate';
        body.dataset.documentMode = annotate ? 'annotate' : 'edit';
        body.dataset.documentLocked = state.isLocked ? 'true' : 'false';
        window.StudyNotesEditor?.setEditable?.(!annotate);
        if (titleInput) titleInput.readOnly = annotate;
        if (annotate && sourceText && !sourceText.hidden) {
          sourceToggle?.click();
        }
        restoreInteractionState();
      };

      const handleRuntimeMessage = message => {
        switch (message.type) {
        case 'loadDocument':
          requestAnimationFrame(() => requestAnimationFrame(scheduleRefresh));
          break;
        case 'documentRuntimeChanged':
          state.isLocked = Boolean(message.isLocked);
          state.mode = state.isLocked
            ? 'annotate'
            : message.mode === 'annotate' ? 'annotate' : 'edit';
          applyRuntimeState();
          break;
        case 'annotationsChanged':
          state.annotations = Array.isArray(message.annotations)
            ? message.annotations
            : [];
          scheduleRefresh();
          break;
        case 'activeAnnotationChanged':
          state.activeAnnotationID = message.activeAnnotationID ?? null;
          scheduleRefresh();
          break;
        default:
          break;
        }
      };

      editorRoot.addEventListener('click', event => {
        if (typeof event.clientX !== 'number') return;
        const hit = hitRects.find(rect =>
          event.clientX >= rect.left &&
          event.clientX <= rect.right &&
          event.clientY >= rect.top &&
          event.clientY <= rect.bottom
        );
        if (!hit) return;
        event.preventDefault();
        event.stopPropagation();
        state.activeAnnotationID = hit.id;
        post({ type: 'annotationClicked', annotationID: hit.id });
        scheduleRefresh();
      }, true);

      editorRoot.addEventListener('keydown', event => {
        if (state.mode === 'edit') return;
        const commandKey = event.metaKey || event.ctrlKey;
        const blockedShortcut = commandKey
          && ['b', 'i', 'u', 'x', 'e', 'k', 'z', 'y', '\\']
            .includes(event.key.toLowerCase());
        if (!blockedShortcut && event.key !== '/') return;
        event.preventDefault();
        event.stopImmediatePropagation();
      }, true);

      document.addEventListener('selectionchange', () => {
        if (state.mode !== 'annotate') return;
        scheduleSelectionReport();
      });
      editorHost?.addEventListener('scroll', scheduleRefresh, {
        passive: true
      });
      window.addEventListener('resize', scheduleRefresh, { passive: true });
      new MutationObserver(scheduleRefresh).observe(editorRoot, {
        childList: true,
        characterData: true,
        subtree: true
      });

      window.__StudyNotesDocumentRuntime = {
        receive: handleRuntimeMessage,
        refresh: scheduleRefresh
      };
      window.studyNotesDocumentRuntimeRefresh = scheduleRefresh;
      applyRuntimeState();
      scheduleRefresh();
    })();
    """#

    private func observeLifecycle() {
        guard lifecycleObservers.isEmpty else {
            return
        }
        let center = NotificationCenter.default
        #if os(macOS)
        lifecycleObservers.append(
            center.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    await self?.session?.flush(.windowBlur)
                }
            }
        )
        #elseif os(iOS)
        lifecycleObservers.append(
            center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    await self?.session?.flush(.appBackground)
                }
            }
        )
        #endif
    }
}

private enum MarkdownEditorWebError: Error {
    case invalidMessage
}

@MainActor
private final class MarkdownMediaSchemeHandler:
    NSObject,
    WKURLSchemeHandler
{
    private let coordinator: NoteMediaCoordinator

    init(coordinator: NoteMediaCoordinator) {
        self.coordinator = coordinator
    }

    func webView(
        _ webView: WKWebView,
        start urlSchemeTask: any WKURLSchemeTask
    ) {
        guard let url = urlSchemeTask.request.url,
              let reference = try? NoteMediaReference(
                  string: url.absoluteString
              ) else {
            urlSchemeTask.didFailWithError(
                MarkdownEditorWebError.invalidMessage
            )
            return
        }
        Task { @MainActor in
            guard let fileURL = await coordinator.previewFileURL(
                for: reference
            ), let data = try? Data(contentsOf: fileURL) else {
                urlSchemeTask.didFailWithError(
                    MarkdownEditorWebError.invalidMessage
                )
                return
            }
            let contentType = NoteMediaPolicy.contentType(
                forFileExtension: fileURL.pathExtension
            ) ?? "application/octet-stream"
            let response = HTTPURLResponse(
                url: url,
                mimeType: contentType,
                expectedContentLength: data.count,
                textEncodingName: nil
            )
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        }
    }

    func webView(
        _ webView: WKWebView,
        stop urlSchemeTask: any WKURLSchemeTask
    ) {}
}
#endif
