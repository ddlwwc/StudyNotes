#if canImport(WebKit)
import Foundation
import Testing
import WebKit
@testable import StudyNotesKit

@Suite("Mac editor WKWebView runtime")
struct EditorRuntimeTests {
    @Test("block images keep the following fence on its own line")
    @MainActor
    func blockImageFenceRoundTrips() async throws {
        let resource = MarkdownEditorResources.webResource
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let handler = RuntimeMessageHandler()
        configuration.userContentController.add(
            handler,
            name: resource.messageHandlerName
        )
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 760, height: 900),
            configuration: configuration
        )
        let navigator = RuntimeNavigator()
        webView.navigationDelegate = navigator
        webView.loadFileURL(
            resource.htmlURL,
            allowingReadAccessTo: resource.baseURL
        )
        try await navigator.finished()
        try await Task.sleep(for: .milliseconds(300))

        let markdown = """
        # 标题

        ![示意图](https://example.com/image.png)

        ```
        第一行
        第二行
        ```
        """
        let payload = try JSONSerialization.data(
            withJSONObject: [
                "type": "loadDocument",
                "title": "标题",
                "markdown": markdown,
                "compatibilityBlocks": [],
                "blocks": []
            ]
        )
        let payloadJSON = try #require(
            String(data: payload, encoding: .utf8)
        )
        _ = try await webView.evaluateJavaScript(
            """
            window.StudyNotesEditor.receive(\(payloadJSON));
            document.getElementById("title").value = "标题更新";
            document.getElementById("title").dispatchEvent(
              new Event("input", { bubbles: true })
            );
            """
        )
        try await Task.sleep(for: .milliseconds(300))
        let serialized = try #require(
            handler.messages.last(where: {
                $0["type"] as? String == "markdownChanged"
            })?["markdown"] as? String
        )
        _ = try MarkdownEditorCodec().decode(serialized)
        #expect(
            serialized.contains(
                ")\n\n```\n第一行\n第二行\n```"
            )
        )
    }

    @Test("editor images open a zoomable preview on click")
    @MainActor
    func imagePreviewZoom() async throws {
        let resource = MarkdownEditorResources.webResource
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let handler = RuntimeMessageHandler()
        configuration.userContentController.add(
            handler,
            name: resource.messageHandlerName
        )
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 760, height: 900),
            configuration: configuration
        )
        let navigator = RuntimeNavigator()
        webView.navigationDelegate = navigator
        webView.loadFileURL(
            resource.htmlURL,
            allowingReadAccessTo: resource.baseURL
        )
        try await navigator.finished()
        try await Task.sleep(for: .milliseconds(300))

        let payload = try JSONSerialization.data(
            withJSONObject: [
                "type": "loadDocument",
                "title": "图片预览",
                "markdown": """
                # 图片预览

                ![示意图](https://example.com/image.png)
                """,
                "compatibilityBlocks": [],
                "blocks": []
            ]
        )
        let payloadJSON = try #require(
            String(data: payload, encoding: .utf8)
        )
        _ = try await webView.evaluateJavaScript(
            """
            window.StudyNotesEditor.receive(\(payloadJSON));
            const image = document.querySelector('#editor img');
            image.dispatchEvent(new MouseEvent('click', {
              bubbles: true,
              cancelable: true,
              clientX: 400,
              clientY: 300
            }));
            """
        )

        let openedResult = try await webView.evaluateJavaScript(
            "Boolean(document.querySelector('.sn-image-preview'));"
        )
        #expect(try #require(openedResult as? Bool))

        let zoomedResult = try await webView.evaluateJavaScript(
            """
            (() => {
              const overlay = document.querySelector('.sn-image-preview');
              overlay.dispatchEvent(new WheelEvent('wheel', {
                bubbles: true,
                cancelable: true,
                clientX: 400,
                clientY: 300,
                deltaY: -120
              }));
              return overlay.querySelector('img').style.transform;
            })();
            """
        )
        let zoomed = try #require(zoomedResult as? String)
        #expect(zoomed.contains("scale("))
        #expect(!zoomed.contains("scale(1)"))

        let closedResult = try await webView.evaluateJavaScript(
            """
            (() => {
              document.dispatchEvent(new KeyboardEvent('keydown', {
                key: 'Escape',
                bubbles: true,
                cancelable: true
              }));
              return !document.querySelector('.sn-image-preview');
            })();
            """
        )
        #expect(try #require(closedResult as? Bool))
    }

    @Test("vendor rendering and advanced blocks load offline")
    @MainActor
    func runtimeRendersOfflineBlocks() async throws {
        let resource = MarkdownEditorResources.webResource
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let handler = RuntimeMessageHandler()
        configuration.userContentController.add(
            handler,
            name: resource.messageHandlerName
        )
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 760, height: 900),
            configuration: configuration
        )
        let navigator = RuntimeNavigator()
        webView.navigationDelegate = navigator
        webView.loadFileURL(
            resource.htmlURL,
            allowingReadAccessTo: resource.baseURL
        )
        try await navigator.finished()
        try await Task.sleep(for: .milliseconds(300))
        _ = try await webView.evaluateJavaScript(
            MarkdownEditorRuntimeVerification.javaScript
        )

        let blockID = UUID()
        let mermaidID = UUID()
        let document = """
        const documentMessage = {
          type: "loadDocument",
          title: "Runtime",
          markdown: "# Runtime\\n\\n<!-- studynotes:block id=\\"\(blockID.uuidString)\\" type=\\"formula\\" version=\\"1\\" -->\\nE = mc^2\\n<!-- /studynotes:block -->\\n\\n<!-- studynotes:block id=\\"\(mermaidID.uuidString)\\" type=\\"mermaid\\" version=\\"1\\" -->\\nflowchart LR\\nA --> B\\n<!-- /studynotes:block -->\\n\\nbody",
          compatibilityBlocks: [],
          blocks: [{
            id: "\(blockID.uuidString)",
            type: "formula",
            version: 1,
            fallback: "E = mc^2",
            data: { latex: "E = mc^2", display: "block", renderMode: "rendered" }
          }, {
            id: "\(mermaidID.uuidString)",
            type: "mermaid",
            version: 1,
            fallback: "flowchart LR\\nA --> B",
            data: { source: "flowchart LR\\nA --> B", renderMode: "rendered" }
          }]
        };
        window.StudyNotesEditor.receive(documentMessage);
        window.__StudyNotesDocumentRuntime.receive(documentMessage);
        """
        _ = try await webView.evaluateJavaScript(document)
        _ = try await webView.evaluateJavaScript(
            "window.__StudyNotesDocumentRuntime.renderNow();"
        )
        try await Task.sleep(for: .milliseconds(500))

        let result = try await webView.evaluateJavaScript(
            """
            (() => ({
              katexLoaded: Boolean(window.katex?.render),
              mermaidLoaded: Boolean(window.mermaid?.render),
              toolbarButtons: document.querySelectorAll(
                "#toolbar button"
              ).length,
              formulaCards: document.querySelectorAll(
                ".sn-formula-block"
              ).length,
              katexRendered: Boolean(document.querySelector(
                ".sn-formula-block .katex"
              )),
              mermaidCards: document.querySelectorAll(
                ".sn-mermaid-block"
              ).length,
              mermaidRendered: Boolean(document.querySelector(
                ".sn-mermaid-preview svg"
              )),
              runtimeDebug:
                window.__StudyNotesDocumentRuntime?.debugState?.() ?? {},
              viewportFits:
                document.documentElement.scrollWidth <= window.innerWidth + 1,
              unnamedButtons: Array.from(
                document.querySelectorAll("#toolbar button")
              ).filter(button => !(
                button.getAttribute("aria-label") ||
                button.textContent.trim() ||
                button.getAttribute("title")
              )).length,
              editorText: document.querySelector("#editor")?.innerText || "",
              editorHTML: document.querySelector("#editor")?.innerHTML || ""
            }))()
            """
        )
        let values = try #require(result as? [String: Any])
        #expect(values["katexLoaded"] as? Bool == true)
        #expect(values["mermaidLoaded"] as? Bool == true)
        #expect((values["toolbarButtons"] as? Int ?? 0) >= 25)
        #expect(values["formulaCards"] as? Int == 1)
        #expect(values["katexRendered"] as? Bool == true)
        #expect(values["mermaidCards"] as? Int == 1)
        #expect(values["mermaidRendered"] as? Bool == true)
        #expect((values["editorText"] as? String ?? "").contains("公式"))
        let debug = values["runtimeDebug"] as? [String: Any] ?? [:]
        #expect(debug["blocks"] as? Int == 2)
        #expect(debug["hasAdvancedPlugin"] as? Bool == true)
        #expect((debug["advancedDecorations"] as? Int ?? 0) >= 2)
        #expect(values["viewportFits"] as? Bool == true)
        #expect(values["unnamedButtons"] as? Int == 0)
        let css = try String(
            contentsOf: resource.baseURL.appending(path: "editor.css"),
            encoding: .utf8
        )
        #expect(css.contains("prefers-reduced-motion"))
        #expect(css.contains("prefers-contrast"))
        #expect(css.contains("forced-colors"))
        #expect(!handler.failures.contains { $0.contains("https://") })
    }
}

@MainActor
private final class RuntimeNavigator: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func finished() async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        continuation?.resume()
        continuation = nil
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: any Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

@MainActor
private final class RuntimeMessageHandler: NSObject, WKScriptMessageHandler {
    private(set) var messages: [[String: Any]] = []
    private(set) var failures: [String] = []

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let dictionary = message.body as? [String: Any] else {
            return
        }
        messages.append(dictionary)
        if dictionary["type"] as? String == "failed" {
            failures.append(dictionary["reason"] as? String ?? "")
        }
    }
}
#endif
