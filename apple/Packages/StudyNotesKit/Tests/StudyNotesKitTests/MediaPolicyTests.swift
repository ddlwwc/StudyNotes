import Testing
import StudyNotesKit

@Suite("Media policy")
struct MediaPolicyTests {
    @Test("uploads accept 1 byte through 50MB")
    func sizeBoundaries() throws {
        try NoteMediaPolicy.validate(byteCount: 1)
        try NoteMediaPolicy.validate(
            byteCount: NoteMediaPolicy.maximumByteCount
        )

        #expect(throws: NoteMediaPolicyError.self) {
            try NoteMediaPolicy.validate(byteCount: 0)
        }
        #expect(throws: NoteMediaPolicyError.self) {
            try NoteMediaPolicy.validate(
                byteCount: NoteMediaPolicy.maximumByteCount + 1
            )
        }
    }

    @Test("only cellular uploads above 10MB require confirmation")
    func cellularConfirmation() throws {
        #expect(
            try !NoteMediaPolicy.requiresCellularConfirmation(
                byteCount: NoteMediaPolicy.cellularConfirmationByteCount,
                connection: .cellular
            )
        )
        #expect(
            try NoteMediaPolicy.requiresCellularConfirmation(
                byteCount: NoteMediaPolicy.cellularConfirmationByteCount + 1,
                connection: .cellular
            )
        )
        #expect(
            try !NoteMediaPolicy.requiresCellularConfirmation(
                byteCount: NoteMediaPolicy.cellularConfirmationByteCount + 1,
                connection: .wifi
            )
        )
    }

    @Test("basic content type mapping is symmetric and case insensitive")
    func contentTypeMapping() {
        #expect(NoteMediaPolicy.contentType(forFileExtension: "PNG") == "image/png")
        #expect(NoteMediaPolicy.contentType(forFileExtension: ".jpeg") == "image/jpeg")
        #expect(NoteMediaPolicy.fileExtension(forContentType: "IMAGE/JPEG") == "jpg")
        #expect(NoteMediaPolicy.fileExtension(forContentType: "application/pdf") == "pdf")
        #expect(NoteMediaPolicy.fileExtension(forContentType: "unknown/type") == nil)
        #expect(
            NoteMediaPolicy.objectKeyFileExtension(
                forContentType: "text/csv"
            ) == "bin"
        )
        #expect(
            NoteMediaPolicy.objectKeyFileExtension(
                forContentType: "video/mp4"
            ) == "bin"
        )
    }
}
