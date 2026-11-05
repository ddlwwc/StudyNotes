import Foundation
import Testing
@testable import StudyNotesKit

@Suite("Editor performance baseline")
struct EditorPerformanceTests {
    @Test("large documents save and reopen without truncation")
    func largeDocumentRoundTrip() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let store = StudyNotesStore(rootURL: root)
        let knowledgeBase = try await store.createKnowledgeBase(named: "性能")
        let note = try await store.createMarkdownNote(
            title: "大文档",
            in: knowledgeBase.id,
            markdown: "# 大文档"
        )
        let initial = try await store.loadEditorDocument(id: note.summary.id)
        var markdown = "# 大文档\n\n"
        var blocks: [EditorDocumentBlockEnvelope] = []
        for index in 0..<2_000 {
            markdown += "第 \(index) 段正文，用于验证大量块滚动和保存。\n\n"
        }
        for index in 0..<20 {
            let id = UUID()
            let fallback = "数据表 \(index)"
            markdown += """
            <!-- studynotes:block id="\(id.uuidString)" type="data-table" version="1" -->
            \(fallback)
            <!-- /studynotes:block -->

            """
            blocks.append(
                EditorDocumentBlockEnvelope(
                    id: id,
                    type: "data-table",
                    fallback: fallback,
                    data: .object([
                        "schema": .object(["fields": .array([])]),
                        "records": .array([])
                    ])
                )
            )
        }
        let clock = ContinuousClock()
        let start = clock.now
        let saved = try await store.saveEditorDocument(
            EditorDocumentSaveRequest(
                materialID: note.summary.id,
                title: "大文档",
                markdown: markdown,
                blocks: blocks,
                expectedContentFingerprint: initial.contentFingerprint
            )
        )
        let loaded = try await store.loadEditorDocument(id: note.summary.id)
        let elapsed = start.duration(to: clock.now)

        #expect(saved.currentGenerationID != nil)
        #expect(loaded.markdown == markdown)
        #expect(loaded.blocks.count == 20)
        #expect(elapsed < .seconds(15))
    }
}
