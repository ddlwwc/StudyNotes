import Foundation
import Testing
import StudyNotesKit

@Suite("Media reference")
struct MediaReferenceTests {
    @Test("same content and extension produce one stable library-media reference")
    func stableContentAddress() throws {
        let data = Data("hello".utf8)

        let first = try NoteMediaReference.make(
            data: data,
            fileExtension: "TXT"
        )
        let second = try NoteMediaReference.make(
            data: data,
            fileExtension: ".txt"
        )

        #expect(first == second)
        #expect(
            first.stringValue
                == "media://qiniu/library-media/"
                    + "2cf24dba5fb0a30e26e83b2ac5b9e29e"
                    + "1b161e5c1fa7425e73043362938b9824.txt"
        )
        #expect(try NoteMediaReference(string: first.stringValue) == first)
    }

    @Test(
        "reference parsing rejects encoding, URL components, traversal, and foreign prefixes",
        arguments: [
            "media://qiniu/library-media%2Fabc.txt",
            "media://qiniu/library-media/abc.txt?token=1",
            "media://qiniu/library-media/abc.txt#fragment",
            "media://qiniu/library-media/../abc.txt",
            "media://qiniu/materials/abc.txt",
            "https://qiniu/library-media/abc.txt"
        ]
    )
    func rejectsUnsafeReferences(value: String) {
        #expect(throws: NoteMediaReferenceError.self) {
            _ = try NoteMediaReference(string: value)
        }
    }

    @Test("generic attachments use the server object-key extension")
    func genericAttachmentExtension() throws {
        let reference = try NoteMediaReference.make(
            data: Data("a,b".utf8),
            contentType: "text/csv"
        )

        #expect(reference.objectKey.hasSuffix(".bin"))
    }
}
