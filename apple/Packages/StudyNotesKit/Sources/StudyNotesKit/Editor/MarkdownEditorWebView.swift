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
        #if os(macOS)
        hideWebScrollbars(in: webView)
        #endif
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
        #if os(macOS)
        hideWebScrollbars(in: webView)
        #endif
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

#if os(macOS)
@MainActor
private func hideWebScrollbars(in view: NSView) {
    if let scrollView = view as? NSScrollView {
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
    }
    for subview in view.subviews {
        hideWebScrollbars(in: subview)
    }
}
#endif

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
        #if os(macOS)
        hideWebScrollbars(in: webView)
        #endif
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

    fileprivate static let documentRuntimeJavaScript = #"""
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
      const editor = editorRoot.editor;

      document.getElementById("attach-audio")?.addEventListener("click", () => {
        bridge?.postMessage({
          type: "attachRequested",
          attachmentKind: "audio"
        });
      });
      document.getElementById("attach-video")?.addEventListener("click", () => {
        bridge?.postMessage({
          type: "attachRequested",
          attachmentKind: "video"
        });
      });

      const style = document.createElement('style');
      style.id = 'studynotes-document-runtime-style';
      style.textContent = `
        body[data-document-mode="annotate"] #toolbar button[data-command],
        body[data-document-mode="annotate"] #toolbar .separator,
        body[data-document-mode="annotate"] #attach-image,
        body[data-document-mode="annotate"] #attach-file,
        body[data-document-mode="annotate"] #attach-audio,
        body[data-document-mode="annotate"] #attach-video,
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
        activeAnnotationID: null,
        blocks: []
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

      const fingerprintText = async text => {
        const bytes = new TextEncoder().encode(text);
        const digest = await crypto.subtle.digest("SHA-256", bytes);
        return Array.from(new Uint8Array(digest))
          .map(value => value.toString(16).padStart(2, "0"))
          .join("");
      };

      const selectionPayload = async () => {
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
        const selectionElementType = block?.matches("img")
          ? "image"
          : block?.matches("table")
          ? "table"
          : null;
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
          elementType: selectionElementType,
          contentFingerprint: await fingerprintText(blockText),
          viewportY: Number.isFinite(rect.top) ? rect.top : null
        };
      };

      const reportSelection = async () => {
        if (state.mode !== 'annotate') return;
        const selection = await selectionPayload();
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
          state.blocks = Array.isArray(message.blocks)
            ? message.blocks
            : [];
          requestAnimationFrame(() => requestAnimationFrame(scheduleRefresh));
          scheduleAdvancedBlockRender();
          break;
        case 'documentRuntimeChanged':
          state.isLocked = Boolean(message.isLocked);
          state.mode = state.isLocked
            ? 'annotate'
            : message.mode === 'annotate' ? 'annotate' : 'edit';
          applyRuntimeState();
          applyAdvancedBlockReadOnlyState();
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

      const escapeHTML = value => String(value ?? "")
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;")
        .replaceAll('"', "&quot;");
      const uuid = () => {
        if (crypto?.randomUUID) return crypto.randomUUID();
        return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(
          /[xy]/g,
          character => {
            const random = Math.random() * 16 | 0;
            const value = character === "x" ? random : random & 3 | 8;
            return value.toString(16);
          }
        );
      };
      const clamp = (value, minimum, maximum) =>
        Math.max(minimum, Math.min(maximum, value));
      const normalizeStyleCSS = value => String(value ?? "")
        .split(";")
        .map(rule => rule.trim())
        .filter(Boolean)
        .map(rule => {
          const separator = rule.indexOf(":");
          if (separator < 0) return "";
          const property = rule.slice(0, separator).trim().toLowerCase();
          const propertyValue = rule.slice(separator + 1).trim();
          const allowed = new Set([
            "color",
            "background-color",
            "font-size",
            "line-height",
            "text-align",
            "display",
            "padding-left",
            "text-indent"
          ]);
          return allowed.has(property) && propertyValue
            ? `${property}: ${propertyValue}`
            : "";
        })
        .filter(Boolean)
        .join("; ");
      const parseStyleCSS = value => {
        const result = {};
        for (const rule of normalizeStyleCSS(value).split(";")) {
          const separator = rule.indexOf(":");
          if (separator < 0) continue;
          result[rule.slice(0, separator).trim()] =
            rule.slice(separator + 1).trim();
        }
        return result;
      };
      const mergeStyleCSS = (base, updates) => {
        const next = { ...parseStyleCSS(base) };
        for (const [property, value] of Object.entries(updates ?? {})) {
          if (value === null || value === undefined || value === "") {
            delete next[property];
          } else {
            next[property] = String(value);
          }
        }
        return Object.entries(next)
          .map(([property, value]) => `${property}: ${value}`)
          .join("; ");
      };

      const sanitizePastedHTML = html => {
        const parsed = new DOMParser().parseFromString(html, "text/html");
        const blocked = new Set([
          "script", "style", "iframe", "object", "embed", "link", "meta",
          "base", "form", "template", "svg"
        ]);
        const allowed = new Set([
          "a", "b", "blockquote", "br", "code", "del", "div", "em", "h1",
          "h2", "h3", "h4", "h5", "h6", "hr", "i", "img", "li", "ol",
          "p", "pre", "s", "span", "strong", "table", "tbody", "td", "th",
          "thead", "tr", "u", "ul"
        ]);
        for (const element of Array.from(
          parsed.body.querySelectorAll("*")
        ).reverse()) {
          const tag = element.tagName.toLowerCase();
          if (blocked.has(tag)) {
            element.remove();
            continue;
          }
          if (!allowed.has(tag)) {
            element.replaceWith(...Array.from(element.childNodes));
            continue;
          }
          for (const attribute of Array.from(element.attributes)) {
            const name = attribute.name.toLowerCase();
            const value = attribute.value.trim();
            if (name.startsWith("on")) {
              element.removeAttribute(attribute.name);
              continue;
            }
            if (["href", "src"].includes(name)) {
              const lower = value.toLowerCase();
              if (![
                "https://",
                "http://",
                "mailto:",
                "media://qiniu/",
                "data:image/"
              ].some(prefix => lower.startsWith(prefix))) {
                element.removeAttribute(attribute.name);
              }
              continue;
            }
            if (name === "style") {
              const css = normalizeStyleCSS(value);
              if (css) {
                element.setAttribute("style", css);
              } else {
                element.removeAttribute("style");
              }
              continue;
            }
            if (![
              "alt", "colspan", "height", "rowspan", "title", "width"
            ].includes(name)) {
              element.removeAttribute(attribute.name);
            }
          }
          if (tag === "a" && element.getAttribute("href")) {
            element.setAttribute("rel", "noopener noreferrer");
            element.setAttribute("target", "_blank");
          }
        }
        return parsed.body.innerHTML;
      };

      editorRoot.addEventListener("paste", event => {
        if (state.isLocked || state.mode !== "edit") return;
        const html = event.clipboardData?.getData("text/html") || "";
        if (!html.trim()) return;
        const sanitized = sanitizePastedHTML(html);
        if (!sanitized.trim()) return;
        event.preventDefault();
        event.stopImmediatePropagation();
        editor?.chain().focus().insertContent(sanitized).run();
      }, true);

      let inlineStyleMark = null;
      let underlineMark = null;
      if (editor?.schema) {
        const MarkType = editor.schema.marks.bold?.constructor;
        const registerMark = (name, spec) => {
          if (editor.schema.marks[name]) return editor.schema.marks[name];
          if (!MarkType) return null;
          const mark = new MarkType(name, 120, editor.schema, spec);
          mark.excluded = [];
          editor.schema.marks[name] = mark;
          if (editor.schema.cached) {
            editor.schema.cached.domParser = null;
            editor.schema.cached.wrappings = undefined;
          }
          return mark;
        };
        underlineMark = editor.schema.marks.underline ??
          registerMark("studynotesUnderline", {
            parseDOM: [{ tag: "u" }],
            toDOM: () => ["u", 0]
          });
        inlineStyleMark = registerMark("studynotesInlineStyle", {
          attrs: {
            css: { default: null }
          },
          parseDOM: [{
            tag: "span",
            getAttrs: element => {
              const css = normalizeStyleCSS(
                element.getAttribute("style") || ""
              );
              return css ? { css } : false;
            }
          }],
          toDOM: mark => [
            "span",
            { style: normalizeStyleCSS(mark.attrs.css) },
            0
          ]
        });
      }

      let advancedBlockPlugin = null;
      let advancedBlockDecorations = null;
      let AdvancedDecoration = null;
      let AdvancedDecorationSet = null;
      if (editor) {
        const placeholderPlugin = editor.state.plugins.find(plugin =>
          String(plugin.key).includes("placeholder")
        );
        const placeholderDecorations =
          placeholderPlugin?.props?.decorations?.(editor.state);
        const sampleDecoration =
          placeholderDecorations?.find?.()?.[0];
        AdvancedDecoration = sampleDecoration?.constructor ?? null;
        AdvancedDecorationSet =
          placeholderDecorations?.constructor ?? null;
        const Plugin = editor.state.plugins[0]?.constructor;
        if (AdvancedDecoration && AdvancedDecorationSet && Plugin) {
          advancedBlockPlugin = new Plugin({
            state: {
              init: () => AdvancedDecorationSet.empty,
              apply(transaction, previous) {
                const next = transaction.getMeta(advancedBlockPlugin);
                return next ||
                  previous.map(transaction.mapping, transaction.doc);
              }
            },
            props: {
              decorations(state) {
                return advancedBlockPlugin.getState(state);
              }
            }
          });
          editor.registerPlugin(advancedBlockPlugin);
          advancedBlockDecorations = AdvancedDecorationSet.empty;
        }
      }

      const selectedBlock = () => {
        const selection = window.getSelection();
        let element = blockFor(selection?.anchorNode);
        if (!element && editor) {
          const at = editor.view.domAtPos(editor.state.selection.from).node;
          element = blockFor(at);
        }
        return element;
      };

      const nodeInfoForElement = element => {
        if (!editor || !element) return null;
        let result = null;
        editor.state.doc.descendants((node, position) => {
          if (editor.view.nodeDOM(position) === element) {
            result = { node, position };
            return false;
          }
          return true;
        });
        return result;
      };

      const textRangeForBlock = element => {
        const info = nodeInfoForElement(element);
        if (!info) return null;
        const from = info.position + 1;
        const to = from + info.node.content.size;
        return to > from ? { from, to } : null;
      };

      const currentTextRange = expandToBlock => {
        if (!editor) return null;
        const selection = editor.state.selection;
        if (!selection.empty && !expandToBlock) {
          return { from: selection.from, to: selection.to };
        }
        return textRangeForBlock(selectedBlock());
      };

      const currentInlineCSS = () => {
        if (!editor || !inlineStyleMark) return "";
        const attributes = editor.getAttributes(inlineStyleMark.name);
        return normalizeStyleCSS(attributes?.css);
      };

      const applyInlineStyle = (updates, expandToBlock = false) => {
        if (!editor || !inlineStyleMark) return false;
        const range = currentTextRange(expandToBlock);
        if (!range) {
          showEditorStatus("请先选择一个文本块。");
          return false;
        }
        const css = mergeStyleCSS(currentInlineCSS(), updates);
        const transaction = editor.state.tr;
        transaction.removeMark(range.from, range.to, inlineStyleMark);
        if (css) {
          transaction.addMark(
            range.from,
            range.to,
            inlineStyleMark.create({ css })
          );
        }
        editor.view.dispatch(transaction);
        updateToolbarState();
        return true;
      };

      const clearFormatting = () => {
        if (!editor) return;
        const range = currentTextRange(false);
        if (!range) return;
        const transaction = editor.state.tr;
        for (const mark of editor.schema.marks
          ? Object.values(editor.schema.marks)
          : []) {
          transaction.removeMark(range.from, range.to, mark);
        }
        editor.view.dispatch(transaction);
        editor.commands.focus();
        updateToolbarState();
      };

      const toggleUnderline = () => {
        if (!editor || !underlineMark) return false;
        if (typeof editor.commands.toggleUnderline === "function") {
          editor.chain().focus().toggleUnderline().run();
        } else {
          editor.chain().focus().toggleMark(underlineMark.name).run();
        }
        updateToolbarState();
        return true;
      };

      const promptLink = () => {
        if (!editor) return;
        if (editor.isActive("link")) {
          editor.chain().focus().unsetLink().run();
          return;
        }
        const href = window.prompt("链接地址", "https://");
        if (href?.trim()) {
          editor.chain()
            .focus()
            .extendMarkRange("link")
            .setLink({ href: href.trim() })
            .run();
        }
      };

      const toggleFindPanel = show => {
        const panel = document.getElementById("find-panel");
        const input = document.getElementById("find-query");
        if (!panel || !input) return;
        const next = show ?? panel.hidden;
        panel.hidden = !next;
        if (next) {
          input.focus();
          input.select();
        } else {
          input.value = "";
          input.dispatchEvent(new Event("input", { bubbles: true }));
        }
      };

      let copiedFormat = null;
      const copyCurrentFormat = () => {
        if (!editor) return;
        copiedFormat = {
          css: currentInlineCSS(),
          underline: underlineMark
            ? editor.isActive(underlineMark.name)
            : false,
          bold: editor.isActive("bold"),
          italic: editor.isActive("italic"),
          strike: editor.isActive("strike"),
          code: editor.isActive("code")
        };
        document.querySelector('[data-command="formatPainter"]')
          ?.classList.add("active");
        showEditorStatus("格式已复制，请选择目标文本。");
      };
      const applyCopiedFormat = () => {
        if (!copiedFormat || !editor) return;
        const range = currentTextRange(false);
        if (!range) return;
        applyInlineStyle(parseStyleCSS(copiedFormat.css || ""));
        const chain = editor.chain().focus();
        for (const name of ["bold", "italic", "strike", "code"]) {
          if (copiedFormat[name]) chain.setMark(name);
          else chain.unsetMark(name);
        }
        if (copiedFormat.underline) chain.setMark(underlineMark.name);
        else chain.unsetMark(underlineMark.name);
        chain.run();
        copiedFormat = null;
        document.querySelector('[data-command="formatPainter"]')
          ?.classList.remove("active");
        updateToolbarState();
      };

      const updateParagraphLabel = () => {
        const button = document.getElementById("paragraph-style");
        if (!button || !editor) return;
        let label = "正文";
        for (let level = 1; level <= 6; level += 1) {
          if (editor.isActive("heading", { level })) {
            label = `标题 ${level}`;
            break;
          }
        }
        button.firstChild.textContent = `${label} `;
      };

      const updateToolbarState = () => {
        if (!editor) return;
        const active = {
          bold: editor.isActive("bold"),
          italic: editor.isActive("italic"),
          underline: underlineMark
            ? editor.isActive(underlineMark.name)
            : false,
          strike: editor.isActive("strike"),
          code: editor.isActive("code"),
          link: editor.isActive("link"),
          quote: editor.isActive("blockquote"),
          bulletList: editor.isActive("bulletList"),
          orderedList: editor.isActive("orderedList"),
          taskList: editor.isActive("taskList"),
          codeBlock: editor.isActive("codeBlock")
        };
        for (const [name, enabled] of Object.entries(active)) {
          document.querySelector(`[data-command="${name}"]`)
            ?.classList.toggle("active", enabled);
        }
        const attributes = editor.getAttributes(
          inlineStyleMark?.name ?? ""
        );
        const css = parseStyleCSS(attributes?.css);
        const fontSize = document.getElementById("font-size");
        const lineHeight = document.getElementById("line-height");
        if (fontSize && css["font-size"]) fontSize.value = css["font-size"];
        if (lineHeight && css["line-height"]) {
          lineHeight.value = css["line-height"];
        }
        for (const name of ["alignLeft", "alignCenter", "alignRight"]) {
          document.querySelector(`[data-command="${name}"]`)
            ?.classList.toggle(
              "active",
              name === "alignLeft" &&
                (!css["text-align"] || css["text-align"] === "left") ||
              name === "alignCenter" && css["text-align"] === "center" ||
              name === "alignRight" && css["text-align"] === "right"
            );
        }
        updateParagraphLabel();
      };

      const hasTextEditorFocus = () =>
        document.activeElement === editorRoot ||
        editorRoot.contains(document.activeElement);

      const runRichCommand = command => {
        if (!editor || state.isLocked || state.mode !== "edit") return;
        const chain = editor.chain().focus();
        switch (command) {
        case "undo":
          chain.undo().run();
          break;
        case "redo":
          chain.redo().run();
          break;
        case "clearFormat":
          clearFormatting();
          break;
        case "formatPainter":
          copyCurrentFormat();
          break;
        case "paragraph":
          chain.setParagraph().run();
          break;
        case "heading1":
        case "heading2":
        case "heading3":
        case "heading4":
        case "heading5":
        case "heading6":
          chain.toggleHeading({
            level: Number(command.slice(-1))
          }).run();
          break;
        case "bold":
          chain.toggleBold().run();
          break;
        case "italic":
          chain.toggleItalic().run();
          break;
        case "underline":
          toggleUnderline();
          break;
        case "strike":
          chain.toggleStrike().run();
          break;
        case "code":
          chain.toggleCode().run();
          break;
        case "link":
          promptLink();
          break;
        case "alignLeft":
          applyInlineStyle({
            display: "block",
            "text-align": "left"
          }, true);
          break;
        case "alignCenter":
          applyInlineStyle({
            display: "block",
            "text-align": "center"
          }, true);
          break;
        case "alignRight":
          applyInlineStyle({
            display: "block",
            "text-align": "right"
          }, true);
          break;
        case "indent":
          if (!chain.sinkListItem("listItem").run()) {
            const css = parseStyleCSS(currentInlineCSS());
            const current = Number.parseFloat(
              css["padding-left"] || css["text-indent"] || "0"
            ) || 0;
            applyInlineStyle({
              display: "block",
              "padding-left": `${Math.min(current + 2, 12)}em`
            }, true);
          }
          break;
        case "outdent":
          if (!chain.liftListItem("listItem").run()) {
            const css = parseStyleCSS(currentInlineCSS());
            const current = Number.parseFloat(
              css["padding-left"] || css["text-indent"] || "0"
            ) || 0;
            applyInlineStyle({
              display: "block",
              "padding-left": current > 2
                ? `${Math.max(current - 2, 0)}em`
                : null
            }, true);
          }
          break;
        case "bulletList":
          chain.toggleBulletList().run();
          break;
        case "orderedList":
          chain.toggleOrderedList().run();
          break;
        case "taskList":
          chain.toggleTaskList().run();
          break;
        case "quote":
          chain.toggleBlockquote().run();
          break;
        case "codeBlock":
          chain.toggleCodeBlock().run();
          break;
        case "horizontalRule":
          chain.setHorizontalRule().run();
          break;
        case "table":
          chain.insertTable({
            rows: 3,
            cols: 3,
            withHeaderRow: true
          }).run();
          break;
        case "find":
          toggleFindPanel();
          break;
        default:
          break;
        }
        updateToolbarState();
      };

      const showEditorStatus = message => {
        const banner = document.getElementById("status-banner");
        if (!banner) return;
        banner.textContent = message;
        banner.hidden = !message;
        if (message) {
          window.clearTimeout(showEditorStatus.timer);
          showEditorStatus.timer = window.setTimeout(() => {
            banner.hidden = true;
          }, 5000);
        }
      };

      const copyText = async text => {
        try {
          if (navigator.clipboard?.writeText) {
            await navigator.clipboard.writeText(text);
            return true;
          }
        } catch {}
        const textarea = document.createElement("textarea");
        textarea.value = text;
        textarea.setAttribute("readonly", "");
        textarea.style.position = "fixed";
        textarea.style.opacity = "0";
        document.body.append(textarea);
        textarea.select();
        const copied = document.execCommand("copy");
        textarea.remove();
        return copied;
      };

      const positionPopover = (popover, anchor) => {
        if (!popover || !anchor) return;
        const rect = anchor.getBoundingClientRect();
        popover.style.left = `${Math.max(
          8,
          Math.min(rect.left, window.innerWidth - popover.offsetWidth - 8)
        )}px`;
        popover.style.top = `${rect.bottom + 6}px`;
      };

      const closeToolbarPopovers = except => {
        for (const id of [
          "paragraph-popover",
          "color-popover",
          "highlight-popover"
        ]) {
          const popover = document.getElementById(id);
          if (!popover || popover === except) continue;
          popover.hidden = true;
        }
        for (const id of [
          "paragraph-style",
          "color-toggle",
          "highlight-toggle"
        ]) {
          document.getElementById(id)?.setAttribute(
            "aria-expanded",
            "false"
          );
        }
      };

      const toggleToolbarPopover = (id, anchor) => {
        const popover = document.getElementById(id);
        if (!popover || !anchor) return;
        const next = popover.hidden;
        closeToolbarPopovers(popover);
        popover.hidden = !next;
        anchor.setAttribute("aria-expanded", String(next));
        if (next) positionPopover(popover, anchor);
      };

      const headingItems = () => {
        const headings = [];
        if (!editor) return headings;
        editor.state.doc.descendants((node, position) => {
          if (node.type.name === "heading") {
            headings.push({
              level: node.attrs.level,
              text: node.textContent || "无标题",
              position
            });
          }
          return true;
        });
        return headings;
      };

      const blockFactories = {
        code: {
          label: "代码块",
          data: () => ({
            language: "swift",
            source: "// 在此输入代码",
            title: "",
            lineNumbers: true,
            wrap: true,
            theme: "system"
          })
        },
        formula: {
          label: "公式",
          data: () => ({
            latex: "E = mc^2",
            display: "block",
            renderMode: "source"
          })
        },
        mermaid: {
          label: "Mermaid",
          data: () => ({
            source: "graph TD\n  A[开始] --> B[结束]",
            renderMode: "source"
          })
        },
        callout: {
          label: "高亮块",
          data: () => ({
            tone: "info",
            text: "在这里输入高亮内容。"
          })
        },
        status: {
          label: "状态块",
          data: () => ({
            state: "草稿",
            text: "状态说明"
          })
        },
        "table-of-contents": {
          label: "目录",
          data: () => ({
            headings: headingItems().map(item => ({
              level: item.level,
              text: item.text
            }))
          })
        },
        columns: {
          label: "分栏",
          data: () => ({
            columns: 2,
            labels: ["左栏", "右栏"]
          })
        },
        toggle: {
          label: "折叠块",
          data: () => ({
            title: "折叠标题",
            collapsed: false,
            source: "折叠内容"
          })
        },
        "data-table": {
          label: "数据表",
          data: () => ({
            schema: {
              fields: [
                { id: "name", name: "名称", type: "text" },
                { id: "status", name: "状态", type: "text" }
              ]
            },
            views: [],
            records: []
          })
        },
        whiteboard: {
          label: "画板",
          data: () => ({ nodes: [], edges: [] })
        },
        "mind-map": {
          label: "思维导图",
          data: () => ({ nodes: [], edges: [] })
        },
        flowchart: {
          label: "流程图",
          data: () => ({ nodes: [], edges: [] })
        },
        "document-card": {
          label: "文档卡片",
          data: () => ({
            materialID: "",
            title: "未解析文档"
          })
        }
      };

      const fallbackForBlock = (type, data) => {
        switch (type) {
        case "code":
          return `\`\`\`${data.language || "text"}\n${data.source || "// 空代码"}\n\`\`\``;
        case "formula":
          return `> **公式（源码）**\n> $$ ${data.latex || "E = mc^2"} $$`;
        case "mermaid":
          return `> **Mermaid（源码）**\n> ${String(
            data.source || "graph TD"
          ).split("\n").join("\n> ")}`;
        case "callout":
          return `> **高亮块**\n> ${data.text || "高亮内容"}`;
        case "status":
          return `> **状态块 · ${data.state || "草稿"}**\n> ${data.text || "状态说明"}`;
        case "table-of-contents": {
          const items = Array.isArray(data.headings) ? data.headings : [];
          return items.length
            ? `> **目录**\n${items.map(item =>
                `> ${"  ".repeat(Math.max(item.level - 1, 0))}- ${item.text}`
              ).join("\n")}`
            : "> **目录**\n> 当前文档没有标题";
        }
        case "columns":
          return "> **分栏**\n> 左栏\n>\n> 右栏";
        case "toggle":
          return `> **折叠块 · ${data.title || "折叠标题"}**\n> ${data.source || "折叠内容"}`;
        case "data-table":
          return "> **数据表（旁路源码）**\n> 字段与记录保存在复杂块旁路数据中。";
        case "whiteboard":
          return "> **画板（旁路源码）**\n> 画布场景保存在复杂块旁路数据中。";
        case "mind-map":
          return "> **思维导图（旁路源码）**\n> 节点与连线保存在复杂块旁路数据中。";
        case "flowchart":
          return "> **流程图（旁路源码）**\n> 节点与连线保存在复杂块旁路数据中。";
        case "document-card":
          return `> **文档卡片 · ${data.title || "未解析文档"}**\n> 文档 UUID：${data.materialID || "未解析"}`;
        default:
          return `> **${type}**`;
        }
      };

      const insertStructuredBlock = type => {
        const factory = blockFactories[type];
        if (!factory) return;
        const data = factory.data();
        const block = {
          id: uuid(),
          type,
          version: 1,
          fallback: fallbackForBlock(type, data),
          data
        };
        const anchorNode = editor?.view.domAtPos(
          slashPosition ?? editor?.state.selection.from ?? 0
        ).node;
        const anchorElement = blockFor(anchorNode);
        const anchorText = normalize(
          anchorElement?.innerText || anchorElement?.textContent || ""
        );
        post({
          type: "blockInsertRequested",
          block,
          anchorText: anchorText || null
        });
        showEditorStatus(`${factory.label}已插入，正在保存到旁路数据。`);
      };

      const slashItems = [
        ["paragraph", "¶", "正文", "基础", "native"],
        ["heading1", "H1", "标题 1", "基础", "native"],
        ["heading2", "H2", "标题 2", "基础", "native"],
        ["heading3", "H3", "标题 3", "基础", "native"],
        ["heading4", "H4", "标题 4", "基础", "native"],
        ["heading5", "H5", "标题 5", "基础", "native"],
        ["heading6", "H6", "标题 6", "基础", "native"],
        ["bulletList", "•", "无序列表", "基础", "native"],
        ["orderedList", "1.", "有序列表", "基础", "native"],
        ["taskList", "☑", "任务列表", "基础", "native"],
        ["quote", "❝", "引用", "基础", "native"],
        ["horizontalRule", "—", "分割线", "基础", "native"],
        ["code", "{}", "代码块", "智能", "structured"],
        ["formula", "∑", "公式", "智能", "structured"],
        ["mermaid", "◇", "Mermaid", "智能", "structured"],
        ["callout", "▣", "高亮块", "智能", "structured"],
        ["status", "●", "状态块", "智能", "structured"],
        ["table-of-contents", "☷", "目录", "智能", "structured"],
        ["columns", "▥", "分栏", "智能", "structured"],
        ["toggle", "▸", "折叠块", "智能", "structured"],
        ["data-table", "▦", "数据表", "智能", "structured"],
        ["document-card", "▤", "文档卡片", "智能", "structured"],
        ["whiteboard", "✎", "画板", "画板", "structured"],
        ["mind-map", "⌘", "思维导图", "画板", "structured"],
        ["flowchart", "⇄", "流程图", "画板", "structured"],
        ["image", "Img", "图片占位", "基础", "attach"],
        ["file", "File", "附件占位", "基础", "attach"]
      ];

      let slashPosition = null;
      let slashQuery = "";
      let slashSelectedIndex = 0;

      const renderSlashMenu = () => {
        const menu = document.getElementById("slash-menu");
        if (!menu) return;
        menu.replaceChildren();
        const search = document.createElement("input");
        search.className = "slash-search";
        search.type = "search";
        search.placeholder = "搜索块";
        search.value = slashQuery;
        search.setAttribute("aria-label", "搜索插入块");
        search.addEventListener("input", () => {
          slashQuery = search.value;
          slashSelectedIndex = 0;
          renderSlashMenu();
          const nextSearch = menu.querySelector(".slash-search");
          nextSearch?.focus();
          nextSearch?.setSelectionRange(
            nextSearch.value.length,
            nextSearch.value.length
          );
        });
        menu.append(search);
        const normalizedQuery = slashQuery.trim().toLocaleLowerCase();
        const filtered = slashItems.filter(([, , label, group]) =>
          !normalizedQuery ||
          `${label} ${group}`.toLocaleLowerCase().includes(normalizedQuery)
        );
        if (!filtered.length) {
          const empty = document.createElement("div");
          empty.className = "slash-empty";
          empty.textContent = "没有匹配的块";
          menu.append(empty);
          return;
        }
        let index = 0;
        for (const group of ["基础", "智能", "画板"]) {
          const items = filtered.filter(item => item[3] === group);
          if (!items.length) continue;
          const title = document.createElement("div");
          title.className = "slash-section-title";
          title.textContent = group;
          menu.append(title);
          for (const [id, icon, label, , kind] of items) {
            const button = document.createElement("button");
            button.type = "button";
            button.dataset.block = id;
            button.dataset.kind = kind;
            button.dataset.slashIndex = String(index);
            if (index === slashSelectedIndex) button.classList.add("active");
            const iconNode = document.createElement("span");
            iconNode.className = "slash-icon";
            iconNode.textContent = icon;
            const labelNode = document.createElement("span");
            labelNode.textContent = label;
            const hintNode = document.createElement("span");
            hintNode.className = "slash-hint";
            hintNode.textContent = kind === "structured" ? "旁路" : "";
            button.append(iconNode, labelNode, hintNode);
            button.addEventListener("click", () => applySlashItem(id, kind));
            menu.append(button);
            index += 1;
          }
        }
      };

      const openSlashMenu = () => {
        if (!editor || state.isLocked || state.mode !== "edit") return;
        const menu = document.getElementById("slash-menu");
        if (!menu) return;
        slashPosition = editor.state.selection.from;
        slashQuery = "";
        slashSelectedIndex = 0;
        renderSlashMenu();
        menu.hidden = false;
        const position = editor.view.coordsAtPos(slashPosition);
        menu.style.left = `${Math.max(
          12,
          Math.min(position.left, window.innerWidth - 352)
        )}px`;
        menu.style.top = `${Math.min(
          position.bottom + 6,
          window.innerHeight - 430
        )}px`;
        menu.querySelector(".slash-search")?.focus();
      };

      const closeSlashMenu = () => {
        const menu = document.getElementById("slash-menu");
        if (menu) menu.hidden = true;
        slashPosition = null;
        slashQuery = "";
      };

      const applySlashItem = (id, kind) => {
        const position = slashPosition;
        closeSlashMenu();
        if (kind === "attach") {
          post({ type: "attachRequested", attachmentKind: id });
          return;
        }
        if (kind === "structured") {
          insertStructuredBlock(id);
          return;
        }
        if (position !== null) editor.commands.setTextSelection(position);
        runRichCommand(id);
      };

      let advancedRenderFrame = 0;
      let renderedBlockSignature = "";
      const scheduleAdvancedBlockRender = () => {
        cancelAnimationFrame(advancedRenderFrame);
        advancedRenderFrame = requestAnimationFrame(() => {
          advancedRenderFrame = requestAnimationFrame(renderAdvancedBlocks);
        });
      };

      const plainFallbackLines = fallback => String(fallback ?? "")
        .replaceAll("\r\n", "\n")
        .split("\n")
        .map(line => line
          .replace(/^```[A-Za-z0-9_+-]*\s*/, "")
          .replace(/^>\s?/, "")
          .replace(/^#+\s*/, "")
          .replace(/\*\*/g, "")
          .replace(/`/g, "")
          .trim())
        .filter(line => line && !line.startsWith("<!--"));

      const blockFallbackScore = (element, block) => {
        const text = blockTextNormalized(element);
        if (!text) return 0;
        let score = 0;
        for (const line of plainFallbackLines(block.fallback).slice(0, 4)) {
          const normalized = line.replace(/\s+/g, " ").trim()
            .toLocaleLowerCase();
          if (normalized.length >= 2 && text.includes(normalized)) {
            score += Math.min(normalized.length, 60);
          }
        }
        if (block.type === "code" || block.type === "mermaid") {
          const source = block.type === "code"
            ? block.data?.source
            : block.data?.source;
          const firstLine = String(source || "").trim().split("\n")[0];
          if (firstLine && text.includes(firstLine.toLocaleLowerCase())) {
            score += 20;
          }
        }
        return score;
      };

      const blockTextNormalized = element => normalize(
        element?.innerText || element?.textContent || ""
      ).toLocaleLowerCase();

      const findFallbackElement = (block, used) => {
        let best = null;
        let bestScore = 0;
        for (const element of editorRoot.children) {
          if (element.classList.contains("sn-advanced-block")) continue;
          if (used.has(element)) continue;
          const score = blockFallbackScore(element, block);
          if (score > bestScore) {
            best = element;
            bestScore = score;
          }
        }
        return bestScore > 0 ? best : null;
      };

      const sendBlockUpdate = (block, data, fallback) => {
        post({
          type: "blockUpdateRequested",
          block: {
            ...block,
            data,
            fallback
          }
        });
      };

      const currentBlockByID = id =>
        state.blocks.find(block => block.id === id) ?? null;

      const blockData = block => {
        if (block.data && typeof block.data === "object") return block.data;
        return {};
      };

      const blockKindLabel = type => blockFactories[type]?.label ?? type;

      const createButton = (label, title, action) => {
        const button = document.createElement("button");
        button.type = "button";
        button.textContent = label;
        button.title = title;
        button.addEventListener("click", action);
        return button;
      };

      const addBlockHeader = (card, block, fallbackElement) => {
        const header = document.createElement("div");
        header.className = "sn-block-header";
        const title = document.createElement("span");
        title.className = "sn-block-title";
        title.textContent = blockKindLabel(block.type);
        const kind = document.createElement("span");
        kind.className = "sn-block-kind";
        kind.textContent = block.type;
        const note = document.createElement("span");
        note.className = "sn-render-note";
        note.textContent = ["data-table", "whiteboard", "mind-map", "flowchart", "document-card"]
          .includes(block.type)
          ? "离线源码"
          : "源码降级";
        const actions = document.createElement("div");
        actions.className = "sn-block-actions";
        const copy = createButton("⧉", "复制块正文", async () => {
          const copied = await copyText(block.fallback || "");
          showEditorStatus(copied ? "块正文已复制。" : "复制失败。");
        });
        copy.setAttribute("aria-label", "复制块正文");
        const menu = createButton("⋯", "块菜单", event => {
          openBlockMenu({
            kind: "custom",
            block,
            card,
            fallbackElement
          }, event);
        });
        menu.className = "sn-block-menu";
        menu.setAttribute("aria-label", "块菜单");
        actions.append(copy, menu);
        header.append(title, kind, note, actions);
        card.append(header);
      };

      const applyBlockButtons = ({ action, textarea, parseData }) => {
        const row = document.createElement("div");
        row.className = "sn-block-config";
        const apply = document.createElement("button");
        apply.type = "button";
        apply.className = "sn-block-command";
        apply.textContent = "应用";
        apply.dataset.requiresEdit = "true";
        const error = document.createElement("div");
        error.className = "sn-block-error";
        error.hidden = true;
        apply.addEventListener("click", () => {
          try {
            const data = parseData();
            error.hidden = true;
            action(data);
          } catch (failure) {
            error.textContent = failure.message || String(failure);
            error.hidden = false;
          }
        });
        row.append(apply);
        return { row, error };
      };

      const highlightCode = (source, language, lineNumbers, wrap) => {
        const pre = document.createElement("pre");
        pre.className = "sn-code-block";
        if (!wrap) pre.classList.add("sn-nowrap");
        const lines = String(source || "").split("\n");
        const keywords = new Set([
          "as", "async", "await", "break", "case", "catch", "class",
          "const", "continue", "default", "defer", "do", "else", "enum",
          "export", "extension", "false", "for", "func", "guard", "if",
          "import", "in", "init", "let", "nil", "private", "protocol",
          "public", "return", "self", "static", "struct", "switch",
          "throw", "throws", "true", "try", "var", "while", "with"
        ]);
        const html = lines.map((line, index) => {
          const escaped = escapeHTML(line)
            .replace(/(\/\/.*|#.*)$/g, '<span class="sn-code-comment">$1</span>')
            .replace(/(&quot;.*?&quot;|'.*?')/g, '<span class="sn-code-string">$1</span>')
            .replace(/\b(\d+(?:\.\d+)?)\b/g, '<span class="sn-code-number">$1</span>')
            .replace(/\b([A-Za-z_][A-Za-z0-9_]*)\b/g, word =>
              keywords.has(word)
                ? `<span class="sn-code-keyword">${word}</span>`
                : word
            );
          return lineNumbers
            ? `<span class="sn-code-line" data-line="${index + 1}">${escaped || " "}</span>`
            : escaped || " ";
        }).join(lineNumbers ? "" : "\n");
        pre.innerHTML = html;
        pre.dataset.language = language || "text";
        return pre;
      };

      const createCodeCard = (block, fallbackElement) => {
        const card = document.createElement("section");
        card.className = "sn-advanced-block sn-code-block-card";
        addBlockHeader(card, block, fallbackElement);
        const data = blockData(block);
        const body = document.createElement("div");
        body.className = "sn-block-body";
        const preview = document.createElement("div");
        preview.className = "sn-code-block";
        preview.append(highlightCode(
          data.source,
          data.language,
          data.lineNumbers !== false,
          data.wrap !== false
        ));
        const config = document.createElement("div");
        config.className = "sn-block-config";
        const titleInput = document.createElement("input");
        titleInput.type = "text";
        titleInput.placeholder = "代码标题";
        titleInput.value = data.title || "";
        titleInput.dataset.requiresEdit = "true";
        const language = document.createElement("select");
        language.dataset.requiresEdit = "true";
        for (const option of [
          "swift", "javascript", "typescript", "python", "java",
          "json", "html", "css", "shell", "sql", "text"
        ]) {
          const item = document.createElement("option");
          item.value = option;
          item.textContent = option;
          language.append(item);
        }
        language.value = data.language || "text";
        const theme = document.createElement("select");
        theme.dataset.requiresEdit = "true";
        for (const option of ["system", "light", "dark"]) {
          const item = document.createElement("option");
          item.value = option;
          item.textContent = option === "system" ? "跟随外观" : option;
          theme.append(item);
        }
        theme.value = data.theme || "system";
        const linesLabel = document.createElement("label");
        linesLabel.textContent = "行号";
        const lineNumbers = document.createElement("input");
        lineNumbers.type = "checkbox";
        lineNumbers.checked = data.lineNumbers !== false;
        lineNumbers.dataset.requiresEdit = "true";
        linesLabel.append(lineNumbers);
        const wrapLabel = document.createElement("label");
        wrapLabel.textContent = "软换行";
        const wrap = document.createElement("input");
        wrap.type = "checkbox";
        wrap.checked = data.wrap !== false;
        wrap.dataset.requiresEdit = "true";
        wrapLabel.append(wrap);
        config.append(titleInput, language, theme, linesLabel, wrapLabel);
        const textarea = document.createElement("textarea");
        textarea.value = data.source || "";
        textarea.dataset.requiresEdit = "true";
        textarea.setAttribute("aria-label", "代码源码");
        textarea.spellcheck = false;
        const controls = applyBlockButtons({
          textarea,
          parseData: () => ({
            source: textarea.value,
            title: titleInput.value,
            language: language.value,
            theme: theme.value,
            lineNumbers: lineNumbers.checked,
            wrap: wrap.checked
          }),
          action: next => {
            sendBlockUpdate(
              block,
              next,
              fallbackForBlock("code", next)
            );
          }
        });
        body.append(preview, config, textarea, controls.row, controls.error);
        card.append(body);
        return card;
      };

      const formulaError = source => {
        const stack = [];
        let line = 1;
        let column = 1;
        for (const character of String(source ?? "")) {
          if (character === "\n") {
            line += 1;
            column = 1;
            continue;
          }
          if (character === "{") stack.push({ line, column });
          if (character === "}") {
            if (!stack.pop()) {
              return `第 ${line} 行第 ${column} 列存在多余的 }。`;
            }
          }
          column += 1;
        }
        if (stack.length) {
          const first = stack[0];
          return `第 ${first.line} 行第 ${first.column} 列的 { 没有闭合。`;
        }
        return "";
      };

      const createFormulaCard = (block, fallbackElement) => {
        const card = document.createElement("section");
        card.className = "sn-advanced-block sn-formula-block";
        addBlockHeader(card, block, fallbackElement);
        const data = blockData(block);
        const body = document.createElement("div");
        body.className = "sn-block-body";
        const source = data.latex || "";
        const preview = document.createElement("div");
        preview.className = "sn-formula-source";
        const error = document.createElement("div");
        error.className = "sn-formula-error";
        const message = formulaError(source);
        if (!message && window.katex?.render) {
          try {
            window.katex.render(source, preview, {
              displayMode: true,
              throwOnError: true,
              strict: "ignore",
              trust: false
            });
          } catch (renderError) {
            preview.textContent = `$$\n${source}\n$$`;
            error.hidden = false;
            error.textContent = renderError?.message ?? "公式渲染失败。";
          }
        } else {
          preview.textContent = `$$\n${source}\n$$`;
          error.hidden = !message;
          error.textContent = message;
        }
        const textarea = document.createElement("textarea");
        textarea.value = source;
        textarea.dataset.requiresEdit = "true";
        textarea.setAttribute("aria-label", "LaTeX 源码");
        const controls = applyBlockButtons({
          textarea,
          parseData: () => ({ latex: textarea.value, display: "block", renderMode: "source" }),
          action: next => sendBlockUpdate(
            block,
            next,
            fallbackForBlock("formula", next)
          )
        });
        body.append(preview, error, textarea, controls.row, controls.error);
        card.append(body);
        return card;
      };

      const mermaidError = source => {
        const lines = String(source ?? "").split("\n");
        const first = lines.find(line => line.trim())?.trim() || "";
        if (!first) return "Mermaid 源码为空。";
        const allowed = /^(graph|flowchart|sequenceDiagram|classDiagram|stateDiagram|erDiagram|gantt|pie|journey|mindmap|timeline)\b/;
        if (!allowed.test(first)) {
          return `第 1 行无法识别图表类型：${first}`;
        }
        const stack = [];
        let line = 1;
        let column = 1;
        for (const character of String(source ?? "")) {
          if (character === "\n") {
            line += 1;
            column = 1;
            continue;
          }
          if ("[({".includes(character)) stack.push({ char: character, line, column });
          if ("])}".includes(character)) {
            const opening = stack.pop();
            const pair = { "]": "[", ")": "(", "}": "{" };
            if (!opening || opening.char !== pair[character]) {
              return `第 ${line} 行第 ${column} 列的 ${character} 没有匹配的括号。`;
            }
          }
          column += 1;
        }
        if (stack.length) {
          const firstOpen = stack[0];
          return `第 ${firstOpen.line} 行第 ${firstOpen.column} 列的 ${firstOpen.char} 没有闭合。`;
        }
        return "";
      };

      const createMermaidCard = (block, fallbackElement) => {
        const card = document.createElement("section");
        card.className = "sn-advanced-block sn-mermaid-block";
        addBlockHeader(card, block, fallbackElement);
        const data = blockData(block);
        const body = document.createElement("div");
        body.className = "sn-block-body";
        const preview = document.createElement("pre");
        preview.className = "sn-mermaid-source";
        preview.textContent = data.source || "";
        const error = document.createElement("div");
        error.className = "sn-mermaid-error";
        const message = mermaidError(data.source);
        error.hidden = !message;
        error.textContent = message;
        const diagram = document.createElement("div");
        diagram.className = "sn-mermaid-preview";
        if (!message && window.mermaid?.render) {
          const renderID = `sn-mermaid-${uuid()}`;
          Promise.resolve(window.mermaid.render(renderID, data.source || ""))
            .then(result => {
              if (!diagram.isConnected) return;
              diagram.innerHTML = result.svg;
              preview.hidden = true;
            })
            .catch(renderError => {
              error.hidden = false;
              error.textContent = renderError?.message ?? "Mermaid 渲染失败。";
            });
        } else {
          diagram.hidden = true;
        }
        const textarea = document.createElement("textarea");
        textarea.value = data.source || "";
        textarea.dataset.requiresEdit = "true";
        textarea.setAttribute("aria-label", "Mermaid 源码");
        const controls = applyBlockButtons({
          textarea,
          parseData: () => ({
            source: textarea.value,
            renderMode: "source"
          }),
          action: next => sendBlockUpdate(
            block,
            next,
            fallbackForBlock("mermaid", next)
          )
        });
        body.append(
          preview,
          diagram,
          error,
          textarea,
          controls.row,
          controls.error
        );
        card.append(body);
        return card;
      };

      const createCalloutCard = (block, fallbackElement) => {
        const card = document.createElement("section");
        card.className = "sn-advanced-block";
        addBlockHeader(card, block, fallbackElement);
        const data = blockData(block);
        const body = document.createElement("div");
        body.className = "sn-block-body sn-block-editor";
        const tone = document.createElement("select");
        tone.dataset.requiresEdit = "true";
        for (const [value, label] of [
          ["info", "提示"],
          ["warning", "注意"],
          ["danger", "风险"],
          ["success", "成功"]
        ]) {
          const item = document.createElement("option");
          item.value = value;
          item.textContent = label;
          tone.append(item);
        }
        tone.value = data.tone || "info";
        const textarea = document.createElement("textarea");
        textarea.value = data.text || "";
        textarea.dataset.requiresEdit = "true";
        const controls = applyBlockButtons({
          textarea,
          parseData: () => ({
            tone: tone.value,
            text: textarea.value
          }),
          action: next => sendBlockUpdate(
            block,
            next,
            fallbackForBlock("callout", next)
          )
        });
        body.append(tone, textarea, controls.row, controls.error);
        card.append(body);
        return card;
      };

      const createStatusCard = (block, fallbackElement) => {
        const card = document.createElement("section");
        card.className = "sn-advanced-block";
        addBlockHeader(card, block, fallbackElement);
        const data = blockData(block);
        const body = document.createElement("div");
        body.className = "sn-block-body sn-block-editor";
        const stateSelect = document.createElement("select");
        stateSelect.dataset.requiresEdit = "true";
        for (const value of ["草稿", "进行中", "已完成", "已暂停"]) {
          const item = document.createElement("option");
          item.value = value;
          item.textContent = value;
          stateSelect.append(item);
        }
        stateSelect.value = data.state || "草稿";
        const textarea = document.createElement("textarea");
        textarea.value = data.text || "";
        textarea.dataset.requiresEdit = "true";
        const controls = applyBlockButtons({
          textarea,
          parseData: () => ({
            state: stateSelect.value,
            text: textarea.value
          }),
          action: next => sendBlockUpdate(
            block,
            next,
            fallbackForBlock("status", next)
          )
        });
        body.append(stateSelect, textarea, controls.row, controls.error);
        card.append(body);
        return card;
      };

      const createTOCBlock = (block, fallbackElement) => {
        const card = document.createElement("section");
        card.className = "sn-advanced-block";
        addBlockHeader(card, block, fallbackElement);
        const body = document.createElement("div");
        body.className = "sn-block-body";
        const list = document.createElement("ul");
        list.className = "sn-toc-list";
        const headings = headingItems();
        if (!headings.length) {
          const empty = document.createElement("div");
          empty.className = "sn-block-placeholder";
          empty.textContent = "当前文档没有标题。";
          body.append(empty);
        } else {
          headings.forEach(heading => {
            const item = document.createElement("li");
            const button = document.createElement("button");
            button.type = "button";
            button.textContent = heading.text;
            button.style.paddingLeft = `${6 + (heading.level - 1) * 14}px`;
            button.addEventListener("click", () => {
              editor.commands.setTextSelection(heading.position + 1);
              editor.commands.focus();
              editor.view.nodeDOM(heading.position)?.scrollIntoView({
                block: "start",
                behavior: "smooth"
              });
            });
            item.append(button);
            list.append(item);
          });
          body.append(list);
        }
        card.append(body);
        return card;
      };

      const createColumnsCard = (block, fallbackElement) => {
        const card = document.createElement("section");
        card.className = "sn-advanced-block";
        addBlockHeader(card, block, fallbackElement);
        const data = blockData(block);
        const body = document.createElement("div");
        body.className = "sn-block-body sn-block-editor";
        const preview = document.createElement("div");
        preview.className = "sn-columns-preview";
        for (const label of data.labels || ["左栏", "右栏"]) {
          const column = document.createElement("div");
          column.textContent = label;
          preview.append(column);
        }
        const textarea = document.createElement("textarea");
        textarea.value = JSON.stringify(data, null, 2);
        textarea.dataset.requiresEdit = "true";
        const controls = applyBlockButtons({
          textarea,
          parseData: () => JSON.parse(textarea.value || "{}"),
          action: next => sendBlockUpdate(
            block,
            next,
            fallbackForBlock("columns", next)
          )
        });
        body.append(preview, textarea, controls.row, controls.error);
        card.append(body);
        return card;
      };

      const createToggleCard = (block, fallbackElement) => {
        const card = document.createElement("section");
        card.className = "sn-advanced-block";
        addBlockHeader(card, block, fallbackElement);
        const data = blockData(block);
        const body = document.createElement("div");
        body.className = "sn-block-body sn-block-editor";
        const title = document.createElement("input");
        title.type = "text";
        title.value = data.title || "";
        title.placeholder = "折叠标题";
        title.dataset.requiresEdit = "true";
        const textarea = document.createElement("textarea");
        textarea.value = data.source || "";
        textarea.dataset.requiresEdit = "true";
        const controls = applyBlockButtons({
          textarea,
          parseData: () => ({
            title: title.value,
            collapsed: Boolean(data.collapsed),
            source: textarea.value
          }),
          action: next => sendBlockUpdate(
            block,
            next,
            fallbackForBlock("toggle", next)
          )
        });
        body.append(title, textarea, controls.row, controls.error);
        card.append(body);
        return card;
      };

      const createJSONBlockCard = (block, fallbackElement) => {
        const card = document.createElement("section");
        card.className = "sn-advanced-block";
        addBlockHeader(card, block, fallbackElement);
        const data = blockData(block);
        const body = document.createElement("div");
        body.className = "sn-block-body sn-block-editor";
        const note = document.createElement("div");
        note.className = "sn-block-placeholder";
        note.textContent = block.type === "data-table"
          ? "当前版本保留表格旁路源码；完整表格视图由后续数据表 ticket 实现。"
          : "当前版本保留图形旁路源码；可视化画布由后续画板 ticket 实现。";
        const textarea = document.createElement("textarea");
        textarea.value = JSON.stringify(data, null, 2);
        textarea.dataset.requiresEdit = "true";
        const controls = applyBlockButtons({
          textarea,
          parseData: () => JSON.parse(textarea.value || "{}"),
          action: next => sendBlockUpdate(
            block,
            next,
            fallbackForBlock(block.type, next)
          )
        });
        body.append(note, textarea, controls.row, controls.error);
        card.append(body);
        return card;
      };

      const createDocumentCard = (block, fallbackElement) => {
        const card = document.createElement("section");
        card.className = "sn-advanced-block";
        addBlockHeader(card, block, fallbackElement);
        const data = blockData(block);
        const body = document.createElement("div");
        body.className = "sn-block-body sn-block-editor";
        const title = document.createElement("input");
        title.type = "text";
        title.value = data.title || "未解析文档";
        title.placeholder = "文档标题";
        title.dataset.requiresEdit = "true";
        const materialID = document.createElement("input");
        materialID.type = "text";
        materialID.value = data.materialID || "";
        materialID.placeholder = "稳定文档 UUID";
        materialID.dataset.requiresEdit = "true";
        const note = document.createElement("div");
        note.className = "sn-block-placeholder";
        note.textContent = data.materialID
          ? "离线显示文档卡片；目标文档缺失时保留未解析引用。"
          : "未绑定文档 UUID，当前显示未解析卡片。";
        const controls = applyBlockButtons({
          textarea: title,
          parseData: () => ({
            materialID: materialID.value.trim(),
            title: title.value.trim() || "未解析文档"
          }),
          action: next => sendBlockUpdate(
            block,
            next,
            fallbackForBlock("document-card", next)
          )
        });
        body.append(title, materialID, note, controls.row, controls.error);
        card.append(body);
        return card;
      };

      const cardForBlock = (block, fallbackElement) => {
        switch (block.type) {
        case "code":
          return createCodeCard(block, fallbackElement);
        case "formula":
          return createFormulaCard(block, fallbackElement);
        case "mermaid":
          return createMermaidCard(block, fallbackElement);
        case "callout":
          return createCalloutCard(block, fallbackElement);
        case "status":
          return createStatusCard(block, fallbackElement);
        case "table-of-contents":
          return createTOCBlock(block, fallbackElement);
        case "columns":
          return createColumnsCard(block, fallbackElement);
        case "toggle":
          return createToggleCard(block, fallbackElement);
        case "document-card":
          return createDocumentCard(block, fallbackElement);
        case "data-table":
        case "whiteboard":
        case "mind-map":
        case "flowchart":
          return createJSONBlockCard(block, fallbackElement);
        default:
          return null;
        }
      };

      const renderAdvancedBlocks = () => {
        if (!editor || !editorRoot) return;
        const signature = JSON.stringify(state.blocks);
        if (!advancedBlockPlugin || !AdvancedDecoration ||
            !AdvancedDecorationSet) {
          return;
        }
        const decorations = [];
        const used = new Set();
        for (const block of state.blocks) {
          const fallbackElement = findFallbackElement(block, used);
          if (fallbackElement) used.add(fallbackElement);
          const info = nodeInfoForElement(fallbackElement);
          const position = info?.position ?? editor.state.doc.content.size;
          const makeCard = () => {
            const card = cardForBlock(block, fallbackElement);
            if (!card) return document.createTextNode("");
            card.dataset.blockID = block.id;
            card.contentEditable = "false";
            card.snFallbackElement = fallbackElement;
            return card;
          };
          decorations.push(AdvancedDecoration.widget(
            position,
            makeCard,
            {
              key: `studynotes-block-${block.id}`,
              side: -1
            }
          ));
          if (fallbackElement) {
            decorations.push(AdvancedDecoration.node(
              position,
              position + info.node.nodeSize,
              { class: "sn-fallback-hidden" }
            ));
          }
        }
        const next = AdvancedDecorationSet.create(
          editor.state.doc,
          decorations
        );
        advancedBlockDecorations = next;
        editor.view.dispatch(
          editor.state.tr.setMeta(advancedBlockPlugin, next)
        );
        renderedBlockSignature = signature;
        applyAdvancedBlockReadOnlyState();
      };

      const applyAdvancedBlockReadOnlyState = () => {
        const readOnly = state.isLocked || state.mode !== "edit";
        document.querySelectorAll(
          ".sn-advanced-block textarea, .sn-advanced-block input, " +
          ".sn-advanced-block select, .sn-advanced-block [data-requires-edit]"
        ).forEach(control => {
          control.disabled = readOnly;
        });
        if (readOnly) closeBlockMenu();
      };

      let blockMenuTarget = null;
      const closeBlockMenu = () => {
        const menu = document.getElementById("block-menu");
        if (menu) menu.hidden = true;
        blockMenuTarget = null;
      };

      const blockMenuReason = () => {
        if (!blockMenuTarget) return "";
        if (blockMenuTarget.kind === "custom") {
          return "复杂块支持复制、剪切、删除和下方添加；嵌套结构由后续结构块能力处理。";
        }
        return "";
      };

      const menuButton = (label, action, disabled, reason = "") => {
        const button = document.createElement("button");
        button.type = "button";
        button.textContent = label;
        button.disabled = disabled;
        if (reason) button.title = reason;
        button.addEventListener("click", action);
        return button;
      };

      const deleteNativeBlock = element => {
        const info = nodeInfoForElement(element);
        if (!info) return;
        editor.chain()
          .focus()
          .setNodeSelection(info.position)
          .deleteSelection()
          .run();
      };

      const addBelowNativeBlock = element => {
        const info = nodeInfoForElement(element);
        if (!info) return;
        editor.chain().focus().insertContentAt(
          info.position + info.node.nodeSize,
          { type: "paragraph" }
        ).run();
      };

      const convertNativeBlock = (element, value) => {
        const info = nodeInfoForElement(element);
        if (!info || !editor.schema) return;
        const transaction = editor.state.tr;
        if (/^heading[1-6]$/.test(value)) {
          transaction.setNodeMarkup(
            info.position,
            editor.schema.nodes.heading,
            { level: Number(value.slice(-1)) }
          );
        } else {
          transaction.setNodeMarkup(
            info.position,
            editor.schema.nodes.paragraph
          );
        }
        editor.view.dispatch(transaction);
        closeBlockMenu();
      };

      const indentNativeBlock = element => {
        const info = nodeInfoForElement(element);
        if (!info) return;
        editor.commands.setTextSelection(info.position + 1);
        const chain = editor.chain().focus();
        if (!chain.sinkListItem("listItem").run()) {
          runRichCommand("indent");
        }
      };

      const outdentNativeBlock = element => {
        const info = nodeInfoForElement(element);
        if (!info) return;
        editor.commands.setTextSelection(info.position + 1);
        const chain = editor.chain().focus();
        if (!chain.liftListItem("listItem").run()) {
          runRichCommand("outdent");
        }
      };

      const openBlockMenu = (target, event) => {
        if (!editor || state.isLocked || state.mode !== "edit") return;
        const menu = document.getElementById("block-menu");
        if (!menu) return;
        event?.preventDefault();
        event?.stopPropagation();
        blockMenuTarget = target;
        menu.replaceChildren();
        const title = document.createElement("div");
        title.className = "block-menu-title";
        title.textContent = target.kind === "custom"
          ? blockKindLabel(target.block.type)
          : "块操作";
        menu.append(title);
        if (target.kind === "native") {
          const convertRow = document.createElement("div");
          convertRow.className = "sn-block-config";
          const select = document.createElement("select");
          for (const [value, label] of [
            ["paragraph", "正文"],
            ["heading1", "标题 1"],
            ["heading2", "标题 2"],
            ["heading3", "标题 3"]
          ]) {
            const option = document.createElement("option");
            option.value = value;
            option.textContent = label;
            select.append(option);
          }
          convertRow.append(select);
          menu.append(convertRow);
          menu.append(menuButton(
            "转换",
            () => convertNativeBlock(target.element, select.value),
            false
          ));
        }
        menu.append(menuButton(
          "复制",
          async () => {
            const text = target.kind === "custom"
              ? target.block.fallback
              : target.element.innerText;
            const copied = await copyText(text || "");
            showEditorStatus(copied ? "块已复制。" : "复制失败。");
            closeBlockMenu();
          },
          false
        ));
        menu.append(menuButton(
          "剪切",
          async () => {
            const text = target.kind === "custom"
              ? target.block.fallback
              : target.element.innerText;
            const copied = await copyText(text || "");
            if (!copied) {
              showEditorStatus("复制失败，未执行剪切。");
              return;
            }
            if (target.kind === "custom") {
              post({
                type: "blockRemoveRequested",
                blockID: target.block.id
              });
            } else {
              deleteNativeBlock(target.element);
            }
            closeBlockMenu();
          },
          false
        ));
        menu.append(menuButton(
          "删除",
          () => {
            if (target.kind === "custom") {
              post({
                type: "blockRemoveRequested",
                blockID: target.block.id
              });
            } else {
              deleteNativeBlock(target.element);
            }
            closeBlockMenu();
          },
          false
        ));
        const divider = document.createElement("div");
        divider.className = "block-menu-divider";
        menu.append(divider);
        menu.append(menuButton(
          "增加缩进",
          () => {
            if (target.kind === "native") indentNativeBlock(target.element);
            closeBlockMenu();
          },
          target.kind === "custom",
          "复杂块暂不支持嵌套缩进。"
        ));
        menu.append(menuButton(
          "减少缩进",
          () => {
            if (target.kind === "native") outdentNativeBlock(target.element);
            closeBlockMenu();
          },
          target.kind === "custom",
          "复杂块暂不支持嵌套缩进。"
        ));
        menu.append(menuButton(
          "下方添加段落",
          () => {
            if (target.kind === "custom") {
              if (target.fallbackElement) {
                addBelowNativeBlock(target.fallbackElement);
              } else {
                editor.chain().focus("end").createParagraphNear().run();
              }
            } else {
              addBelowNativeBlock(target.element);
            }
            closeBlockMenu();
          },
          false
        ));
        const reason = blockMenuReason();
        if (reason) {
          const note = document.createElement("div");
          note.className = "block-menu-reason";
          note.textContent = reason;
          menu.append(note);
        }
        const rect = event?.clientX !== undefined
          ? { left: event.clientX, top: event.clientY }
          : target.element?.getBoundingClientRect?.() ?? {
              left: 24,
              top: 96
            };
        menu.hidden = false;
        menu.style.left = `${Math.max(
          8,
          Math.min(rect.left, window.innerWidth - 222)
        )}px`;
        menu.style.top = `${Math.max(
          48,
          Math.min(rect.top + 8, window.innerHeight - 430)
        )}px`;
      };

      document.addEventListener("click", event => {
        const command = event.target.closest(
          "#toolbar button[data-command], .toolbar-popover button[data-command]"
        );
        if (!command) return;
        event.preventDefault();
        event.stopImmediatePropagation();
        runRichCommand(command.dataset.command);
      }, true);

      document.getElementById("paragraph-style")?.addEventListener(
        "click",
        event => {
          event.preventDefault();
          event.stopPropagation();
          toggleToolbarPopover(
            "paragraph-popover",
            event.currentTarget
          );
        }
      );
      document.getElementById("color-toggle")?.addEventListener(
        "click",
        event => {
          event.preventDefault();
          event.stopPropagation();
          toggleToolbarPopover("color-popover", event.currentTarget);
        }
      );
      document.getElementById("highlight-toggle")?.addEventListener(
        "click",
        event => {
          event.preventDefault();
          event.stopPropagation();
          toggleToolbarPopover(
            "highlight-popover",
            event.currentTarget
          );
        }
      );
      document.getElementById("insert-block")?.addEventListener(
        "click",
        event => {
          event.preventDefault();
          editor.commands.focus();
          openSlashMenu();
        }
      );
      document.getElementById("font-size")?.addEventListener(
        "change",
        event => applyInlineStyle({
          "font-size": event.target.value
        })
      );
      document.getElementById("line-height")?.addEventListener(
        "change",
        event => applyInlineStyle({
          "line-height": event.target.value
        })
      );
      document.getElementById("color-popover")?.addEventListener(
        "click",
        event => {
          const swatch = event.target.closest("[data-color]");
          if (!swatch) return;
          applyInlineStyle({ color: swatch.dataset.color });
          closeToolbarPopovers();
        }
      );
      document.getElementById("highlight-popover")?.addEventListener(
        "click",
        event => {
          const swatch = event.target.closest("[data-highlight]");
          if (!swatch) return;
          const highlight = swatch.dataset.highlight;
          applyInlineStyle({
            "background-color": highlight === "transparent"
              ? null
              : highlight
          });
          closeToolbarPopovers();
        }
      );
      document.addEventListener("pointerdown", event => {
        if (!event.target.closest(
          "#paragraph-popover, #color-popover, #highlight-popover, " +
          "#paragraph-style, #color-toggle, #highlight-toggle"
        )) {
          closeToolbarPopovers();
        }
        if (!event.target.closest("#slash-menu, #insert-block")) {
          closeSlashMenu();
        }
        if (!event.target.closest("#block-menu, .drag-handle, .sn-block-menu")) {
          closeBlockMenu();
        }
      });
      document.addEventListener("click", event => {
        const handle = event.target.closest(".drag-handle");
        if (handle) {
          const block = selectedBlock();
          if (block) {
            openBlockMenu({ kind: "native", element: block }, event);
          }
        }
      }, true);

      document.addEventListener("keydown", event => {
        if (event.isComposing) return;
        const targetInEditor =
          document.activeElement === editorRoot ||
          editorRoot.contains(document.activeElement);
        const commandKey = event.metaKey || event.ctrlKey;
        const slashMenu = document.getElementById("slash-menu");
        if (!slashMenu?.hidden) {
          const buttons = Array.from(
            slashMenu.querySelectorAll("button[data-block]")
          );
          if (event.key === "ArrowDown" || event.key === "ArrowUp") {
            event.preventDefault();
            event.stopImmediatePropagation();
            if (!buttons.length) return;
            slashSelectedIndex = (
              slashSelectedIndex +
              (event.key === "ArrowDown" ? 1 : -1) +
              buttons.length
            ) % buttons.length;
            buttons.forEach((button, index) => {
              button.classList.toggle("active", index === slashSelectedIndex);
            });
            buttons[slashSelectedIndex].scrollIntoView({
              block: "nearest"
            });
            return;
          }
          if (event.key === "Enter") {
            event.preventDefault();
            event.stopImmediatePropagation();
            buttons[slashSelectedIndex]?.click();
            return;
          }
          if (event.key === "Escape") {
            event.preventDefault();
            event.stopImmediatePropagation();
            closeSlashMenu();
            return;
          }
        }
        if (targetInEditor && event.key === "/" &&
            !event.shiftKey && !commandKey && !event.altKey) {
          event.preventDefault();
          event.stopImmediatePropagation();
          openSlashMenu();
          return;
        }
        if (!targetInEditor || !commandKey) {
          if (targetInEditor && event.key === "Tab") {
            event.preventDefault();
            event.stopImmediatePropagation();
            runRichCommand(event.shiftKey ? "outdent" : "indent");
          }
          if (event.key === "Escape") {
            closeSlashMenu();
            closeBlockMenu();
            closeToolbarPopovers();
          }
          return;
        }
        const key = event.key.toLocaleLowerCase();
        const command = {
          b: "bold",
          i: "italic",
          u: "underline",
          x: event.shiftKey ? "strike" : "",
          e: "code",
          k: "link",
          "\\": "clearFormat",
          f: "find"
        }[key];
        if (event.shiftKey && commandKey) {
          const alignment = {
            l: "alignLeft",
            e: "alignCenter",
            r: "alignRight"
          }[key];
          if (alignment) {
            event.preventDefault();
            event.stopImmediatePropagation();
            runRichCommand(alignment);
            return;
          }
        }
        if (command) {
          event.preventDefault();
          event.stopImmediatePropagation();
          runRichCommand(command);
          return;
        }
        if (event.altKey && /^[1-6]$/.test(event.key)) {
          event.preventDefault();
          event.stopImmediatePropagation();
          runRichCommand(`heading${event.key}`);
          return;
        }
        if (event.altKey && ["7", "8", "9"].includes(event.key)) {
          event.preventDefault();
          event.stopImmediatePropagation();
          runRichCommand({
            "7": "orderedList",
            "8": "bulletList",
            "9": "taskList"
          }[event.key]);
          return;
        }
        if (event.altKey && key === "q") {
          event.preventDefault();
          event.stopImmediatePropagation();
          runRichCommand("quote");
        }
      }, true);

      editor?.on("selectionUpdate", updateToolbarState);
      editor?.on("transaction", updateToolbarState);
      editor?.on("update", updateToolbarState);
      document.addEventListener("mouseup", event => {
        if (!copiedFormat || !editorRoot.contains(event.target)) return;
        window.setTimeout(() => {
          if (!editor.state.selection.empty) applyCopiedFormat();
        }, 0);
      });

      const configureMermaid = () => {
        window.mermaid?.initialize?.({
          startOnLoad: false,
          securityLevel: "strict",
          theme: document.documentElement.dataset.theme === "dark"
            ? "dark"
            : "default",
          fontFamily:
            '-apple-system, BlinkMacSystemFont, "PingFang SC", sans-serif'
        });
      };
      configureMermaid();
      const originalSetTheme = window.StudyNotesEditor?.setTheme;
      if (window.StudyNotesEditor && originalSetTheme) {
        window.StudyNotesEditor.setTheme = theme => {
          originalSetTheme.call(window.StudyNotesEditor, theme);
          configureMermaid();
          scheduleAdvancedBlockRender();
        };
      }

      window.__StudyNotesDocumentRuntime = {
        receive: handleRuntimeMessage,
        refresh: () => {
          scheduleRefresh();
          scheduleAdvancedBlockRender();
        },
        renderNow: renderAdvancedBlocks,
        debugState: () => ({
          blocks: state.blocks.length,
          hasAdvancedPlugin: Boolean(advancedBlockPlugin),
          advancedDecorations:
            advancedBlockDecorations?.find?.().length ?? 0
        })
      };
      window.studyNotesDocumentRuntimeRefresh = scheduleRefresh;
      applyRuntimeState();
      updateToolbarState();
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

#if DEBUG
@MainActor
enum MarkdownEditorRuntimeVerification {
    static var javaScript: String {
        MarkdownEditorWebCoordinator.documentRuntimeJavaScript
    }
}
#endif

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
