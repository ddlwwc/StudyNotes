import Foundation
import Testing
import StudyNotesKit

@Suite("Media cache", .serialized)
struct MediaCacheTests {
    @Test("content-addressed cache reads, measures, and clears")
    func readMeasureAndClear() async throws {
        let directory = try MediaTestDirectory()
        defer { directory.remove() }
        let data = Data("cached image".utf8)
        let reference = try NoteMediaReference.make(
            data: data,
            fileExtension: "png"
        )
        let cache = try NoteMediaCache(
            applicationSupportRoot: directory.url
        )

        try await cache.write(data, for: reference)

        #expect(try await cache.data(for: reference) == data)
        #expect(try await cache.size() == data.count)
        try await cache.clear()
        #expect(try await cache.data(for: reference) == nil)
        #expect(try await cache.size() == 0)
    }

    @Test("cache rejects bytes that do not match the object key")
    func rejectsMismatchedContent() async throws {
        let directory = try MediaTestDirectory()
        defer { directory.remove() }
        let reference = try NoteMediaReference.make(
            data: Data("expected".utf8),
            fileExtension: "txt"
        )
        let cache = try NoteMediaCache(
            applicationSupportRoot: directory.url
        )

        await #expect(throws: NoteMediaCacheError.self) {
            try await cache.write(Data("different".utf8), for: reference)
        }
    }
}
