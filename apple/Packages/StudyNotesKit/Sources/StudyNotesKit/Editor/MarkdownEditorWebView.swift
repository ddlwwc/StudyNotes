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
    @Environment(\.colorScheme) private var colorScheme

    public init(
        session: MarkdownEditorSession,
        readingPreferences: ReadingPreferences = .init(),
        mediaCoordinator: NoteMediaCoordinator? = nil,
        onAttachmentRequested:
            ((MarkdownEditorAttachmentKind) -> Void)? = nil
    ) {
        _session = Bindable(session)
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
        window.StudyNotesEditor?.receive(\(json));
        """
        _ = try await webView.evaluateJavaScript(script)
    }

    func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        applyAppearance()
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
