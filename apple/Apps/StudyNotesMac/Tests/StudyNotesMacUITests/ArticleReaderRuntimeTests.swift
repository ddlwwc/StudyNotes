#if canImport(WebKit)
import AppKit
import Foundation
import Testing
import WebKit
@testable import StudyNotesMacUI

@Suite("Article reader runtime")
@MainActor
struct ArticleReaderRuntimeTests {
    @Test("image preview opens on click and zooms with the wheel")
    func imagePreviewZoom() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let handler = ArticleRuntimeMessageHandler()
        for name in [
            "selectionChanged",
            "annotationClick",
            "annotationLayout",
            "elementAnnotationRequest",
            "readerScrollChanged"
        ] {
            configuration.userContentController.add(handler, name: name)
        }
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            configuration: configuration
        )
        let navigator = ArticleRuntimeNavigator()
        webView.navigationDelegate = navigator
        webView.loadHTMLString(
            """
            <!doctype html>
            <html>
              <body>
                <article>
                  <p>正文</p>
                  <img alt="示例图片" src="data:image/png;base64,iVBORw0KGgo=">
                </article>
              </body>
            </html>
            """,
            baseURL: nil
        )
        try await navigator.finished()
        _ = try await webView.evaluateJavaScript(
            ArticleWebView.Coordinator.runtimeJavaScript
        )

        let openedResult = try await webView.evaluateJavaScript(
            """
            (() => {
              const image = document.querySelector('article img');
              image.dispatchEvent(new MouseEvent('click', {
                bubbles: true,
                cancelable: true,
                clientX: 400,
                clientY: 300
              }));
              return Boolean(
                document.getElementById('studynotes-image-preview')
              );
            })();
            """
        )
        let opened = try #require(openedResult as? Bool)
        #expect(opened)

        let zoomedResult = try await webView.evaluateJavaScript(
            """
            (() => {
              const overlay = document.getElementById(
                'studynotes-image-preview'
              );
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
              return !document.getElementById(
                'studynotes-image-preview'
              );
            })();
            """
        )
        let closed = try #require(closedResult as? Bool)
        #expect(closed)
    }

    @Test("reader helper disables nested AppKit scrollbars")
    func nestedScrollbarHidden() {
        let outer = NSScrollView()
        let inner = NSScrollView()
        outer.documentView = inner
        outer.hasVerticalScroller = true
        outer.hasHorizontalScroller = true
        inner.hasVerticalScroller = true
        inner.hasHorizontalScroller = true

        ArticleWebView.hideScrollbars(in: outer)

        #expect(!outer.hasVerticalScroller)
        #expect(!outer.hasHorizontalScroller)
        #expect(!inner.hasVerticalScroller)
        #expect(!inner.hasHorizontalScroller)
    }
}

@MainActor
private final class ArticleRuntimeNavigator: NSObject, WKNavigationDelegate {
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
private final class ArticleRuntimeMessageHandler: NSObject, WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {}
}
#endif
