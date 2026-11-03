import Foundation
import Testing
import StudyNotesKit

@Suite("Media upload queue", .serialized)
struct MediaUploadQueueTests {
    @Test("enqueue copies the file and deduplicates equal content")
    func enqueueAndDeduplicate() async throws {
        let directory = try MediaTestDirectory()
        defer { directory.remove() }
        let source = directory.url.appending(path: "source.png")
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x01])
        try bytes.write(to: source)
        let queue = try NoteMediaUploadQueue(
            applicationSupportRoot: directory.url
        )

        let first = try await queue.enqueue(
            fileAt: source,
            contentType: "image/png"
        )
        let second = try await queue.enqueue(
            fileAt: source,
            contentType: "image/png"
        )

        #expect(first.id == second.id)
        #expect(first.state == .waiting)
        #expect(first.contentHash == "sha256:\(ContentFingerprint.sha256(bytes))")
        #expect(first.reference.objectKey.hasPrefix("library-media/"))
        let items = await queue.items()
        #expect(items.count == 1)
        let copiedURL = try #require(await queue.localFileURL(for: first.id))
        #expect(copiedURL != source)
        #expect(try Data(contentsOf: copiedURL) == bytes)
    }

    @Test("queue state survives a new instance")
    func reloadAfterRestart() async throws {
        let directory = try MediaTestDirectory()
        defer { directory.remove() }
        let source = directory.url.appending(path: "note.pdf")
        try Data("pdf".utf8).write(to: source)
        let firstQueue = try NoteMediaUploadQueue(
            applicationSupportRoot: directory.url
        )
        let item = try await firstQueue.enqueue(
            fileAt: source,
            contentType: "application/pdf"
        )
        try await firstQueue.updateProgress(id: item.id, progress: 0.4)
        try await firstQueue.markFailed(id: item.id, message: "offline")

        let reloadedQueue = try NoteMediaUploadQueue(
            applicationSupportRoot: directory.url
        )
        let reloaded = try #require(
            await reloadedQueue.item(id: item.id)
        )

        #expect(reloaded.reference == item.reference)
        #expect(reloaded.state == .failed(message: "offline"))
        #expect(await reloadedQueue.localFileURL(for: item.id) != nil)
    }

    @Test("equal bytes with a conflicting content type are not silently reused")
    func contentTypeConflict() async throws {
        let directory = try MediaTestDirectory()
        defer { directory.remove() }
        let source = directory.url.appending(path: "shared.bin")
        try Data("shared".utf8).write(to: source)
        let queue = try NoteMediaUploadQueue(
            applicationSupportRoot: directory.url
        )
        _ = try await queue.enqueue(
            fileAt: source,
            contentType: "text/plain"
        )

        await #expect(throws: NoteMediaUploadQueueError.contentTypeMismatch) {
            _ = try await queue.enqueue(
                fileAt: source,
                contentType: "image/png"
            )
        }
        #expect(await queue.items().count == 1)
    }

    @Test("an interrupted upload returns to waiting after restart")
    func interruptedUploadReturnsToWaiting() async throws {
        let directory = try MediaTestDirectory()
        defer { directory.remove() }
        let source = directory.url.appending(path: "interrupted.png")
        try Data("interrupted".utf8).write(to: source)
        let firstQueue = try NoteMediaUploadQueue(
            applicationSupportRoot: directory.url
        )
        let item = try await firstQueue.enqueue(
            fileAt: source,
            contentType: "image/png"
        )
        try await firstQueue.updateProgress(id: item.id, progress: 0.6)

        let reloadedQueue = try NoteMediaUploadQueue(
            applicationSupportRoot: directory.url
        )

        #expect(await reloadedQueue.item(id: item.id)?.state == .waiting)
    }

    @Test("retry, cancel, and upload transitions are persisted")
    func lifecycleTransitions() async throws {
        let directory = try MediaTestDirectory()
        defer { directory.remove() }
        let source = directory.url.appending(path: "note.txt")
        try Data("hello".utf8).write(to: source)
        let queue = try NoteMediaUploadQueue(
            applicationSupportRoot: directory.url
        )
        let item = try await queue.enqueue(
            fileAt: source,
            contentType: "text/plain"
        )

        try await queue.updateProgress(id: item.id, progress: 0.75)
        #expect(
            await queue.item(id: item.id)?.state
                == .uploading(progress: 0.75)
        )
        try await queue.markFailed(id: item.id, message: "network")
        try await queue.retry(id: item.id)
        #expect(await queue.item(id: item.id)?.state == .waiting)
        try await queue.cancel(id: item.id)
        #expect(await queue.item(id: item.id)?.state == .cancelled)
        try await queue.retry(id: item.id)
        try await queue.markUploaded(id: item.id)
        #expect(await queue.item(id: item.id)?.state == .uploaded)
    }

    @Test("reselecting a missing queued file repairs the same item")
    func reselectRepairsMissingFile() async throws {
        let directory = try MediaTestDirectory()
        defer { directory.remove() }
        let source = directory.url.appending(path: "repair.png")
        try Data("repair".utf8).write(to: source)
        let queue = try NoteMediaUploadQueue(
            applicationSupportRoot: directory.url
        )
        let item = try await queue.enqueue(
            fileAt: source,
            contentType: "image/png"
        )
        try await queue.markFailed(id: item.id, message: "missing")
        let queuedURL = try #require(
            await queue.localFileURL(for: item.id)
        )
        try FileManager.default.removeItem(at: queuedURL)

        let repaired = try await queue.enqueue(
            fileAt: source,
            contentType: "image/png"
        )

        #expect(repaired.id == item.id)
        #expect(repaired.state == .waiting)
        #expect(await queue.localFileURL(for: item.id) != nil)

        let repairedURL = try #require(
            await queue.localFileURL(for: item.id)
        )
        try Data("broken".utf8).write(to: repairedURL)
        _ = try await queue.enqueue(
            fileAt: source,
            contentType: "image/png"
        )
        #expect(try Data(contentsOf: repairedURL) == Data("repair".utf8))
    }
}
