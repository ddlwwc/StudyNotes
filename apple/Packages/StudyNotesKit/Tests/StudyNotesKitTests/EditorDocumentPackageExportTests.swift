import Foundation
import Testing
@testable import StudyNotesKit

@Suite("Editor document package export")
struct EditorDocumentPackageExportTests {
    @Test("Markdown and complete package exports use committed content")
    func exportsCommittedContent() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let store = StudyNotesStore(rootURL: root)
        let knowledgeBase = try await store.createKnowledgeBase(named: "导出")
        let note = try await store.createMarkdownNote(
            title: "导出笔记",
            in: knowledgeBase.id,
            markdown: "# 导出笔记"
        )
        let initial = try await store.loadEditorDocument(id: note.summary.id)
        let blockID = UUID()
        let block = EditorDocumentBlockEnvelope(
            id: blockID,
            type: "data-table",
            fallback: "可读表格",
            data: .object(["records": .array([])])
        )
        let markdown = """
        # 导出笔记

        <!-- studynotes:block id="\(blockID.uuidString)" type="data-table" version="1" -->
        可读表格
        <!-- /studynotes:block -->
        """
        _ = try await store.saveEditorDocument(
            EditorDocumentSaveRequest(
                materialID: note.summary.id,
                title: "导出笔记",
                markdown: markdown,
                blocks: [block],
                expectedContentFingerprint: initial.contentFingerprint
            )
        )
        let markdownURL = root.appending(path: "readable.md")
        let packageURL = root.appending(
            path: "note.studynotes",
            directoryHint: .isDirectory
        )

        try await store.exportEditorDocumentMarkdown(
            id: note.summary.id,
            to: markdownURL
        )
        try await store.exportEditorDocumentPackage(
            id: note.summary.id,
            to: packageURL
        )

        let readable = try String(
            contentsOf: markdownURL,
            encoding: .utf8
        )
        #expect(!readable.contains("studynotes:block"))
        #expect(readable.contains("可读表格"))
        #expect(
            FileManager.default.fileExists(
                atPath: packageURL.appending(path: "manifest.json").path
            )
        )
        #expect(
            FileManager.default.fileExists(
                atPath: packageURL.appending(path: "readable.md").path
            )
        )
        #expect(
            !FileManager.default.fileExists(
                atPath: packageURL
                    .appending(path: "content")
                    .appending(path: "transactions")
                    .path
            )
        )
    }
}
