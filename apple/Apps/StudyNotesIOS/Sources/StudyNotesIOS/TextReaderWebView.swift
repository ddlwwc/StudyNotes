#if os(iOS)
import SwiftUI
import UIKit
import WebKit
import StudyNotesIOSCore

struct TextReaderWebView: UIViewRepresentable {
    let html: String
    let annotations: [StudyAnnotation]
    let focusBlockPath: String?
    let onSelection: (TextAnchor) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelection: onSelection)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(
            context.coordinator,
            name: "selection"
        )
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .white
        webView.scrollView.backgroundColor = .white
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        webView.loadHTMLString(html, baseURL: nil)
        context.coordinator.loadedHTML = html
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.loadedHTML != html {
            context.coordinator.loadedHTML = html
            webView.loadHTMLString(html, baseURL: nil)
            return
        }
        context.coordinator.applyAnnotations(annotations, to: webView)
        if let focusBlockPath,
           context.coordinator.lastFocusedBlock != focusBlockPath {
            context.coordinator.lastFocusedBlock = focusBlockPath
            let quoted = context.coordinator.jsonString(focusBlockPath)
            webView.evaluateJavaScript(
                "window.scrollToAnnotation && window.scrollToAnnotation(\(quoted));"
            )
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: "selection"
        )
        webView.stopLoading()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let onSelection: (TextAnchor) -> Void
        var loadedHTML = ""
        var lastFocusedBlock: String?
        private var lastAnnotationJSON = ""

        init(onSelection: @escaping (TextAnchor) -> Void) {
            self.onSelection = onSelection
        }

        func webView(
            _ webView: WKWebView,
            didFinish navigation: WKNavigation!
        ) {
            lastAnnotationJSON = ""
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "selection",
                  let object = message.body as? [String: Any],
                  let quote = object["quote"] as? String,
                  !quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            let anchor = TextAnchor(
                quote: quote,
                prefix: object["prefix"] as? String ?? "",
                suffix: object["suffix"] as? String ?? "",
                startOffset: object["startOffset"] as? Int ?? 0,
                endOffset: object["endOffset"] as? Int ?? quote.count,
                blockPath: object["blockPath"] as? String ?? "block-0"
            )
            onSelection(anchor)
        }

        func applyAnnotations(
            _ annotations: [StudyAnnotation],
            to webView: WKWebView
        ) {
            let payload = annotations.compactMap { annotation -> [String: Any]? in
                guard annotation.resolution == .resolved,
                      case let .text(anchor) = annotation.anchor else {
                    return nil
                }
                return [
                    "id": annotation.id.uuidString,
                    "quote": anchor.quote,
                    "startOffset": anchor.startOffset,
                    "endOffset": anchor.endOffset,
                    "blockPath": anchor.blockPath
                ]
            }
            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                  let json = String(data: data, encoding: .utf8),
                  json != lastAnnotationJSON else {
                return
            }
            lastAnnotationJSON = json
            webView.evaluateJavaScript(
                "window.highlightAnnotations && window.highlightAnnotations(\(json));"
            )
        }

        func jsonString(_ value: String) -> String {
            guard let data = try? JSONSerialization.data(
                withJSONObject: [value]
            ), let json = String(data: data, encoding: .utf8) else {
                return "\"\""
            }
            return String(json.dropFirst().dropLast())
        }
    }
}
#endif
