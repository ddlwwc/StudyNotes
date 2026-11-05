import Foundation
import Testing
@testable import StudyNotesKit

@Suite("Markdown rich text resource contract")
struct MarkdownRichTextResourceContractTests {
    @Test("toolbar exposes every Mac rich text command family")
    func toolbarCommands() throws {
        let html = try resources()
            .appending(path: "editor.html")
            .pipe { try String(contentsOf: $0, encoding: .utf8) }

        let commands = [
            "undo", "redo", "clearFormat",
            "heading1", "heading2", "heading3",
            "heading4", "heading5", "heading6",
            "bold", "italic", "underline", "strike", "code", "link",
            "alignLeft", "alignCenter", "alignRight",
            "indent", "outdent",
            "bulletList", "orderedList", "taskList",
            "quote", "horizontalRule", "find"
        ]
        for command in commands {
            #expect(
                html.contains("data-command=\"\(command)\""),
                "Missing toolbar command \(command)"
            )
        }
        #expect(html.contains("id=\"font-size\""))
        #expect(html.contains("id=\"line-height\""))
        #expect(html.contains("id=\"color-popover\""))
        #expect(html.contains("id=\"highlight-popover\""))
        #expect(html.contains("id=\"insert-block\""))
    }

    @Test("advanced block styles keep source-only fallback visible")
    func advancedBlockStyles() throws {
        let css = try resources()
            .appending(path: "editor.css")
            .pipe { try String(contentsOf: $0, encoding: .utf8) }

        for selector in [
            ".sn-advanced-block",
            ".sn-code-block",
            ".sn-formula-block",
            ".sn-mermaid-block",
            ".sn-fallback-hidden",
            ".sn-block-menu"
        ] {
            #expect(css.contains(selector), "Missing \(selector)")
        }
    }

    private func resources() throws -> URL {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return repository
            .appending(path: "Sources", directoryHint: .isDirectory)
            .appending(path: "StudyNotesKit", directoryHint: .isDirectory)
            .appending(path: "Editor", directoryHint: .isDirectory)
            .appending(path: "Resources", directoryHint: .isDirectory)
    }
}

private extension URL {
    func pipe<T>(_ transform: (URL) throws -> T) rethrows -> T {
        try transform(self)
    }
}
