import Foundation
import Testing
import StudyNotesKit

@Suite("Media reference scanner")
struct MediaReferenceScannerTests {
    @Test("historical versions protect media after removal from current body")
    func historicalReferencesProtectMedia() throws {
        let current = try NoteMediaReference.make(
            data: Data("current".utf8),
            fileExtension: "png"
        )
        let historical = try NoteMediaReference.make(
            data: Data("historical".utf8),
            fileExtension: "pdf"
        )
        let orphan = try NoteMediaReference.make(
            data: Data("orphan".utf8),
            fileExtension: "txt"
        )

        let result = NoteMediaReferenceScanner.scan(
            currentMarkdown: "![current](\(current.stringValue))",
            historicalMarkdowns: [
                "旧版本仍包含 [附件](\(historical.stringValue))"
            ],
            knownObjectKeys: [
                current.objectKey,
                historical.objectKey,
                orphan.objectKey
            ]
        )

        #expect(result.currentObjectKeys == [current.objectKey])
        #expect(result.historicalObjectKeys == [historical.objectKey])
        #expect(result.unreferencedObjectKeys == [orphan.objectKey])
    }

    @Test("deleting current body does not create an immediate cleanup candidate")
    func deletionDoesNotImmediatelyClean() throws {
        let reference = try NoteMediaReference.make(
            data: Data("still historical".utf8),
            fileExtension: "txt"
        )

        let result = NoteMediaReferenceScanner.scan(
            currentMarkdown: "",
            historicalMarkdowns: [reference.stringValue],
            knownObjectKeys: [reference.objectKey]
        )

        #expect(result.unreferencedObjectKeys.isEmpty)
    }

    @Test("unsafe and foreign references are ignored")
    func ignoresUnsafeReferences() {
        let markdown = """
        media://qiniu/library-media%2Fabc.txt
        media://qiniu/library-media/../abc.txt
        media://qiniu/materials/abc.txt
        """

        let result = NoteMediaReferenceScanner.scan(
            currentMarkdown: markdown,
            historicalMarkdowns: []
        )

        #expect(result.referencedObjectKeys.isEmpty)
    }
}
