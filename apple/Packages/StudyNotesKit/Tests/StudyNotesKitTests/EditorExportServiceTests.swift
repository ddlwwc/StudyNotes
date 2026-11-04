import Foundation
import Testing
@testable import StudyNotesKit

@Suite("Editor export service")
struct EditorExportServiceTests {
    @Test("readable Markdown and complete package are written locally")
    func exportFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let id = UUID()
        let block = EditorBlockEnvelope(
            id: id,
            type: .dataTable,
            fallback: "| Name |\n| --- |\n| Ada |",
            data: .object(["records": .array([])])
        )
        let markdown = """
        <!-- studynotes:block id="\(id.uuidString)" type="data-table" version="1" -->
        | Name |
        | --- |
        | Ada |
        <!-- /studynotes:block -->
        """
        let service = EditorExportService()
        let readableURL = root.appending(path: "readable.md")
        try service.writeReadableMarkdown(
            markdown: markdown,
            blocks: [block],
            destinationURL: readableURL
        )
        let packageURL = root.appending(
            path: "document.studynotes",
            directoryHint: .isDirectory
        )
        try service.writePackage(
            markdown: markdown,
            blocks: [block],
            annotationsJSON: Data("[]".utf8),
            conversationsJSON: nil,
            destinationURL: packageURL
        )

        let readable = try String(
            contentsOf: readableURL,
            encoding: .utf8
        )
        #expect(readable == "| Name |\n| --- |\n| Ada |\n")
        #expect(
            FileManager.default.fileExists(
                atPath: packageURL.appending(path: "document.md").path
            )
        )
        #expect(
            FileManager.default.fileExists(
                atPath: packageURL.appending(path: "blocks.json").path
            )
        )
    }
}
