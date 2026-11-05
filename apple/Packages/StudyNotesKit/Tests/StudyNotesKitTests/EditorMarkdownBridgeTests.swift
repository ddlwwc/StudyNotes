import Foundation
import Testing
@testable import StudyNotesKit

@Suite("Markdown editor bridge")
struct MarkdownEditorBridgeTests {
    @Test("bridge messages round-trip through Codable")
    func messageCodable() throws {
        let annotationID = UUID()
        let block = EditorDocumentBlockEnvelope(
            id: UUID(),
            type: "formula",
            fallback: "> **公式**\n> $$E = mc^2$$",
            data: .object([
                "latex": .string("E = mc^2"),
                "sourceOnly": .bool(true)
            ])
        )
        let selection = MarkdownEditorSelection(
            quote: "正文",
            prefix: "标题\n\n",
            suffix: "\n\n结尾",
            offset: 4,
            blockPath: [1],
            elementType: .paragraph,
            contentFingerprint: "正文",
            viewportY: 120
        )
        let annotation = MaterialAnnotation(
            id: annotationID,
            materialID: UUID(),
            anchor: AnnotationAnchor(
                kind: .text,
                excerpt: "正文",
                prefix: "标题\n\n",
                suffix: "\n\n结尾",
                offset: 4,
                blockPath: [1]
            ),
            quote: "正文",
            note: "批注"
        )
        let messages: [MarkdownEditorBridgeMessage] = [
            .ready,
            .loadDocument(
                markdown: "# 标题\n\n正文",
                title: "标题",
                compatibilityBlocks: [
                    MarkdownCompatibilityBlock(
                        kind: .rawHTML,
                        source: "<aside>保留</aside>",
                        startLine: 3,
                        endLine: 3
                    )
                ],
                blocks: [block]
            ),
            .blockInsertRequested(block, anchorText: "段落"),
            .blockUpdateRequested(block),
            .blockRemoveRequested(block.id),
            .markdownChanged("# 新标题\n\n正文"),
            .titleChanged("新标题"),
            .sourceChanged("# 新标题\n\n源文本"),
            .sourceModeChanged(true),
            .command(.save),
            .saveRequested,
            .attachRequested(.image),
            .documentRuntimeChanged(
                isLocked: false,
                mode: .annotate
            ),
            .annotationsChanged([
                MarkdownEditorAnnotationPayload(annotation: annotation)
            ]),
            .activeAnnotationChanged(annotationID),
            .selectionChanged(selection),
            .selectionChanged(nil),
            .annotationRequested(selection),
            .annotationClicked(annotationID),
            .unresolvedAnnotationIDsChanged([annotationID]),
            .annotationLayoutChanged([
                annotationID.uuidString: 144
            ]),
            .failed(reason: "序列化失败")
        ]

        for message in messages {
            let data = try JSONEncoder().encode(message)
            #expect(
                try JSONDecoder().decode(
                    MarkdownEditorBridgeMessage.self,
                    from: data
                ) == message
            )
        }
    }

    @Test("SwiftPM bundles the local editor document and assets")
    func resourceContract() {
        let resource = MarkdownEditorResources.webResource

        #expect(resource.htmlURL.lastPathComponent == "editor.html")
        #expect(resource.baseURL.hasDirectoryPath)
        #expect(resource.messageHandlerName == "markdownEditor")
        #expect(
            FileManager.default.fileExists(
                atPath: resource.baseURL
                    .appending(path: "editor.js").path
            )
        )
        #expect(
            FileManager.default.fileExists(
                atPath: resource.baseURL
                    .appending(path: "editor.css").path
            )
        )
        for relativePath in [
            "vendor/katex/katex.min.js",
            "vendor/katex/katex.min.css",
            "vendor/mermaid/mermaid.min.js"
        ] {
            #expect(
                FileManager.default.fileExists(
                    atPath: resource.baseURL.appending(path: relativePath).path
                )
            )
        }
        let html = try? String(
            contentsOf: resource.htmlURL,
            encoding: .utf8
        )
        #expect(html?.contains("https://") == false)
    }
}
