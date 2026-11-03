import Foundation
import Testing
@testable import StudyNotesKit

@Suite("Apple local material seam")
struct StudyNotesStoreTests {
    @Test("created knowledge base and note are readable after rebuilding the index")
    func createdMaterialsSurviveRebuild() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        let store = StudyNotesStore(rootURL: directory.url)
        let knowledgeBase = try await store.createKnowledgeBase(named: "算法")
        let note = try await store.createMarkdownNote(
            title: "图论入门",
            in: knowledgeBase.id,
            markdown: "# 图论\n\n节点与边"
        )

        #expect(note.summary.title == "图论入门")

        let rebuiltStore = StudyNotesStore(rootURL: directory.url)
        let index = try await rebuiltStore.loadIndex()

        #expect(index.knowledgeBases.map(\.name) == ["算法"])
        #expect(index.materials.map(\.title) == ["图论入门"])

        let materialID = try #require(index.materials.first?.id)
        let loadedNote = try await rebuiltStore.loadMarkdownNote(id: materialID)

        #expect(loadedNote.summary.knowledgeBaseID == knowledgeBase.id)
        #expect(loadedNote.summary.title == "图论入门")
        #expect(loadedNote.markdown == "# 图论\n\n节点与边")
        #expect(loadedNote.summary.conflictCopies.isEmpty)
    }

    @Test("successful package writes leave no temporary directories")
    func successfulWritesLeaveNoTemporaryDirectories() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        let store = StudyNotesStore(rootURL: directory.url)
        let knowledgeBase = try await store.createKnowledgeBase(named: "算法")
        _ = try await store.createMarkdownNote(
            title: "图论入门",
            in: knowledgeBase.id,
            markdown: "# 图论"
        )

        let knowledgeBaseURL = directory.url
            .appending(path: "Libraries", directoryHint: .isDirectory)
            .appending(path: knowledgeBase.id.uuidString, directoryHint: .isDirectory)
        let names = try FileManager.default.contentsOfDirectory(
            atPath: knowledgeBaseURL.path
        )

        #expect(!names.contains { $0.hasPrefix(".tmp-") })
    }

    @Test("failed package writes remove the temporary directory")
    func failedWritesRemoveTemporaryDirectories() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        let setupStore = StudyNotesStore(rootURL: directory.url)
        let knowledgeBase = try await setupStore.createKnowledgeBase(named: "算法")
        let failingStore = StudyNotesStore(
            rootURL: directory.url,
            fileManager: FailingMoveFileManager()
        )

        do {
            _ = try await failingStore.createMarkdownNote(
                title: "图论入门",
                in: knowledgeBase.id,
                markdown: "# 图论"
            )
            Issue.record("Expected package move to fail")
        } catch is MoveFailure {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let knowledgeBaseURL = directory.url
            .appending(path: "Libraries", directoryHint: .isDirectory)
            .appending(path: knowledgeBase.id.uuidString, directoryHint: .isDirectory)
        let names = try FileManager.default.contentsOfDirectory(
            atPath: knowledgeBaseURL.path
        )

        #expect(!names.contains { $0.hasPrefix(".tmp-") })
    }

    @Test("unknown material schema versions are rejected")
    func unknownMaterialSchemaVersionsAreRejected() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        let store = StudyNotesStore(rootURL: directory.url)
        let knowledgeBase = try await store.createKnowledgeBase(named: "算法")
        let note = try await store.createMarkdownNote(
            title: "图论入门",
            in: knowledgeBase.id,
            markdown: "# 图论"
        )
        let knowledgeBaseURL = directory.url
            .appending(path: "Libraries", directoryHint: .isDirectory)
            .appending(path: knowledgeBase.id.uuidString, directoryHint: .isDirectory)
        let manifestURL = knowledgeBaseURL
            .appending(path: "\(note.summary.id.uuidString).studyitem", directoryHint: .isDirectory)
            .appending(path: "manifest.json")
        var manifest = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL))
                as? [String: Any]
        )
        manifest["schemaVersion"] = 99
        let updatedData = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        )
        try updatedData.write(to: manifestURL, options: .atomic)

        do {
            _ = try await store.loadIndex()
            Issue.record("Expected an unsupported schema version error")
        } catch let error as StudyNotesError {
            #expect(error == .unsupportedSchemaVersion(99))
        }
    }

    @Test("conflict copies inside a material package are preserved")
    func nestedConflictCopiesArePresented() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        let store = StudyNotesStore(rootURL: directory.url)
        let knowledgeBase = try await store.createKnowledgeBase(named: "算法")
        let note = try await store.createMarkdownNote(
            title: "图论入门",
            in: knowledgeBase.id,
            markdown: "# 图论"
        )
        let knowledgeBaseURL = directory.url
            .appending(path: "Libraries", directoryHint: .isDirectory)
            .appending(path: knowledgeBase.id.uuidString, directoryHint: .isDirectory)
        let packageURL = knowledgeBaseURL
            .appending(path: "\(note.summary.id.uuidString).studyitem", directoryHint: .isDirectory)
        let annotationConflictURL = packageURL
            .appending(path: "annotations", directoryHint: .isDirectory)
            .appending(path: "annotation (conflicted copy).json")

        try FileManager.default.createDirectory(
            at: annotationConflictURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("private".utf8).write(to: annotationConflictURL)

        let index = try await store.loadIndex()
        let summary = try #require(index.materials.first)

        #expect(
            summary.conflictCopies.map(\.relativePath)
                == ["annotations/annotation (conflicted copy).json"]
        )
    }

    @Test("conflict copies are attached to the authoritative material only")
    func conflictCopiesArePresentedWithoutBecomingMaterials() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        let store = StudyNotesStore(rootURL: directory.url)
        let knowledgeBase = try await store.createKnowledgeBase(named: "算法")
        let note = try await store.createMarkdownNote(
            title: "图论入门",
            in: knowledgeBase.id,
            markdown: "# 图论\n\n当前版本"
        )
        let knowledgeBaseURL = directory.url
            .appending(path: "Libraries", directoryHint: .isDirectory)
            .appending(path: knowledgeBase.id.uuidString, directoryHint: .isDirectory)
        let packageURL = try #require(
            FileManager.default.contentsOfDirectory(
                at: knowledgeBaseURL,
                includingPropertiesForKeys: nil
            ).first { $0.pathExtension == "studyitem" }
        )
        let conflictedCopyName = "\(note.summary.id.uuidString) (Alice's conflicted copy 2026-11-03).studyitem"
        let secondaryConflictName = "\(note.summary.id.uuidString) conflict.studyitem"
        let conflictedCopyURL = knowledgeBaseURL.appending(path: conflictedCopyName)
        let secondaryConflictURL = knowledgeBaseURL.appending(path: secondaryConflictName)

        try FileManager.default.copyItem(at: packageURL, to: conflictedCopyURL)
        try FileManager.default.copyItem(at: packageURL, to: secondaryConflictURL)

        let rebuiltStore = StudyNotesStore(rootURL: directory.url)
        let index = try await rebuiltStore.loadIndex()

        #expect(index.materials.count == 1)
        let summary = try #require(index.materials.first)
        #expect(summary.id == note.summary.id)
        #expect(
            summary.conflictCopies.map(\.relativePath)
                == [secondaryConflictName, conflictedCopyName].sorted()
        )

        let loaded = try await rebuiltStore.loadMarkdownNote(id: note.summary.id)
        #expect(loaded.markdown == "# 图论\n\n当前版本")
        #expect(loaded.summary.conflictCopies == summary.conflictCopies)
    }
}

private struct TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "StudyNotesTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

private struct MoveFailure: Error {}

private final class FailingMoveFileManager: FileManager, @unchecked Sendable {
    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        throw MoveFailure()
    }
}
