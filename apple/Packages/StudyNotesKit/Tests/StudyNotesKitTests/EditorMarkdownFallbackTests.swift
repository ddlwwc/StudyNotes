import Foundation
import Testing
@testable import StudyNotesKit

@Suite("Editor Markdown fallback")
struct EditorMarkdownFallbackTests {
    @Test("readable Markdown replaces complex blocks and keeps block order")
    func readableExport() throws {
        let id = UUID()
        let block = EditorBlockEnvelope(
            id: id,
            type: .flowchart,
            fallback: "flowchart LR\n  A --> B",
            data: .object(["nodes": .array([])])
        )
        let markdown = """
        # Before

        <!-- studynotes:block id="\(id.uuidString)" type="flowchart" version="1" -->
        flowchart LR
          A --> B
        <!-- /studynotes:block -->

        # After
        """

        let readable = try EditorMarkdownFallback().readableMarkdown(
            markdown,
            blocks: [block]
        )

        #expect(!readable.contains("studynotes:block"))
        #expect(readable.contains("flowchart LR"))
        #expect(readable.range(of: "# Before")!.lowerBound
            < readable.range(of: "flowchart LR")!.lowerBound)
        #expect(readable.range(of: "flowchart LR")!.lowerBound
            < readable.range(of: "# After")!.lowerBound)
    }

    @Test("missing bypass data blocks complete export")
    func missingBypassData() {
        let id = UUID()
        let markdown = """
        <!-- studynotes:block id="\(id.uuidString)" type="data-table" version="1" -->
        fallback
        <!-- /studynotes:block -->
        """

        #expect(throws: EditorMarkdownFallbackError.self) {
            try EditorMarkdownFallback().readableMarkdown(
                markdown,
                blocks: []
            )
        }
    }

    @Test("package export includes authoritative and readable content")
    func packageExport() throws {
        let id = UUID()
        let block = EditorBlockEnvelope(
            id: id,
            type: .formula,
            fallback: "E = mc^2",
            data: .object(["latex": .string(#"E = mc^2"#)])
        )
        let files = try EditorMarkdownFallback().packageFiles(
            markdown: "before",
            blocks: [block],
            annotationsJSON: Data("[]".utf8),
            conversationsJSON: nil
        )

        #expect(Set(files.keys) == [
            "annotations.json", "blocks.json", "document.md", "readable.md"
        ])
        #expect(String(data: files["document.md"]!, encoding: .utf8) == "before")
    }
}
