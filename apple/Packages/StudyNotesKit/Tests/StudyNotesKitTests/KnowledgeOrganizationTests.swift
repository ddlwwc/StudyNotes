import Foundation
import Testing
@testable import StudyNotesKit

@Suite("Knowledge organization")
struct KnowledgeOrganizationTests {
    @Test("knowledge bases can be renamed and deleted without losing their materials")
    func knowledgeBasesCanBeRenamedAndDeleted() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        let store = StudyNotesStore(rootURL: directory.url)
        let algorithms = try await store.createKnowledgeBase(named: "算法")
        let reading = try await store.createKnowledgeBase(named: "阅读")
        let note = try await store.createMarkdownNote(
            title: "图论入门",
            in: algorithms.id,
            markdown: "# 图论"
        )

        let renamed = try await store.renameKnowledgeBase(
            id: algorithms.id,
            to: "算法与数据结构"
        )
        #expect(renamed.name == "算法与数据结构")

        let recycledIDs = try await store.deleteKnowledgeBase(id: algorithms.id)
        #expect(recycledIDs == [note.summary.id])

        let rebuiltStore = StudyNotesStore(rootURL: directory.url)
        let index = try await rebuiltStore.loadIndex()

        #expect(index.knowledgeBases.map(\.id) == [reading.id])
        #expect(index.materials.isEmpty)
        #expect(index.recycledMaterials.map(\.id) == [note.summary.id])
        #expect(index.recycledMaterials.first?.deletedAt != nil)
    }

    @Test("nested folders support CRUD and batch archiving from inbox")
    func nestedFoldersSupportCRUDAndBatchArchiving() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        let store = StudyNotesStore(rootURL: directory.url)
        let source = try await store.createKnowledgeBase(named: "算法")
        let target = try await store.createKnowledgeBase(named: "考试")
        _ = try await store.createFolder(named: "基础", in: source.id)
        _ = try await store.createFolder(
            named: "图论",
            in: source.id,
            parentPath: "基础"
        )
        _ = try await store.createFolder(named: "归档", in: source.id)
        _ = try await store.createFolder(named: "重点", in: target.id)

        let renamed = try await store.renameFolder(
            at: "基础",
            in: source.id,
            to: "核心"
        )
        #expect(renamed.path == "核心")

        let moved = try await store.moveFolder(
            at: "核心",
            in: source.id,
            toParentPath: "归档"
        )
        #expect(moved.path == "归档/核心")

        let note = try await store.createMarkdownNote(
            title: "最短路径",
            in: source.id,
            markdown: "# Dijkstra",
            folderPath: "归档/核心/图论"
        )
        let inboxNote = try await store.createInboxMarkdownNote(
            title: "待整理",
            markdown: "# Inbox"
        )

        let movedIDs = try await store.moveMaterials(
            ids: [note.summary.id, inboxNote.summary.id],
            toKnowledgeBaseID: target.id,
            folderPath: "重点"
        )
        #expect(Set(movedIDs) == Set([note.summary.id, inboxNote.summary.id]))

        _ = try await store.deleteFolder(at: "归档/核心/图论", in: source.id)
        _ = try await store.deleteFolder(at: "归档/核心", in: source.id)

        let rebuiltStore = StudyNotesStore(rootURL: directory.url)
        let index = try await rebuiltStore.loadIndex()

        #expect(index.inboxMaterials.isEmpty)
        #expect(index.materials.count == 2)
        #expect(index.materials.allSatisfy { $0.knowledgeBaseID == target.id })
        #expect(index.materials.allSatisfy { $0.folderPath == "重点" })
        #expect(index.folders.contains { $0.path == "归档" && $0.knowledgeBaseID == source.id })
        #expect(!index.folders.contains { $0.path == "归档/核心" })
        #expect(index.folders.contains { $0.path == "重点" && $0.knowledgeBaseID == target.id })
    }

    @Test("tags aggregate across knowledge bases without changing source or content bytes")
    func tagsAggregateWithoutChangingMaterialBytes() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        let store = StudyNotesStore(rootURL: directory.url)
        let swift = try await store.createKnowledgeBase(named: "Swift")
        let database = try await store.createKnowledgeBase(named: "数据库")
        _ = try await store.createFolder(named: "整理后", in: database.id)

        let first = try await store.createMarkdownNote(
            title: "并发模型",
            in: swift.id,
            markdown: "# Actor",
            tags: ["Swift", "并发"]
        )
        let second = try await store.createMarkdownNote(
            title: "索引",
            in: database.id,
            markdown: "# B-Tree",
            tags: ["Swift", "数据库"]
        )
        let inbox = try await store.createInboxMarkdownNote(
            title: "稍后阅读",
            markdown: "# Inbox",
            tags: ["Swift"]
        )

        let sourceData = Data([0x00, 0x01, 0x7F, 0xFF])
        let packageURL = try materialPackageURL(
            id: first.summary.id,
            in: swift.id,
            rootURL: directory.url
        )
        let sourceURL = packageURL
            .appending(path: "source", directoryHint: .isDirectory)
            .appending(path: "original.bin")
        try FileManager.default.createDirectory(
            at: sourceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try sourceData.write(to: sourceURL)
        let contentURL = packageURL
            .appending(path: "content", directoryHint: .isDirectory)
            .appending(path: "note.md")
        let originalContent = try Data(contentsOf: contentURL)

        _ = try await store.setTags(["算法"], onMaterialIDs: [first.summary.id])
        _ = try await store.addTags(["Swift", "图论"], toMaterialIDs: [first.summary.id])
        let updated = try await store.removeTags(
            ["算法"],
            fromMaterialIDs: [first.summary.id]
        )
        #expect(updated.first?.tags == ["Swift", "图论"])

        _ = try await store.moveMaterials(
            ids: [first.summary.id],
            toKnowledgeBaseID: database.id,
            folderPath: "整理后"
        )

        let movedPackageURL = try materialPackageURL(
            id: first.summary.id,
            in: database.id,
            folderPath: "整理后",
            rootURL: directory.url
        )
        #expect(
            try Data(
                contentsOf: movedPackageURL
                    .appending(path: "source")
                    .appending(path: "original.bin")
            ) == sourceData
        )
        #expect(
            try Data(
                contentsOf: movedPackageURL
                    .appending(path: "content")
                    .appending(path: "note.md")
            ) == originalContent
        )

        let rebuiltStore = StudyNotesStore(rootURL: directory.url)
        let index = try await rebuiltStore.loadIndex()
        #expect(Set(index.tags) == Set(["Swift", "数据库", "图论"]))
        #expect(index.materials.filter { $0.tags.contains("Swift") }.count == 2)
        #expect(index.inboxMaterials.first?.id == inbox.summary.id)
        #expect(index.materials.first { $0.id == second.summary.id }?.tags == ["Swift", "数据库"])
    }

    @Test("recycle bin restores original locations and purges only after thirty days")
    func recycleBinRestoresAndPurgesExpiredMaterials() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        let store = StudyNotesStore(rootURL: directory.url)
        let knowledgeBase = try await store.createKnowledgeBase(named: "算法")
        _ = try await store.createFolder(named: "临时", in: knowledgeBase.id)
        _ = try await store.createFolder(named: "保留", in: knowledgeBase.id)

        let missingFolderNote = try await store.createMarkdownNote(
            title: "缺失目录",
            in: knowledgeBase.id,
            markdown: "# 根目录",
            folderPath: "临时"
        )
        let retainedFolderNote = try await store.createMarkdownNote(
            title: "保留目录",
            in: knowledgeBase.id,
            markdown: "# 保留",
            folderPath: "保留"
        )
        let recycledAt = Date(timeIntervalSince1970: 1_800_000_000)
        _ = try await store.moveMaterialsToRecycleBin(
            ids: [missingFolderNote.summary.id, retainedFolderNote.summary.id],
            now: recycledAt
        )

        let recycledIndex = try await store.loadIndex()
        #expect(recycledIndex.materials.isEmpty)
        #expect(recycledIndex.recycledMaterials.count == 2)
        #expect(
            recycledIndex.recycledMaterials.first {
                $0.id == missingFolderNote.summary.id
            }?.folderPath == "临时"
        )
        #expect(recycledIndex.recycledMaterials.allSatisfy {
            $0.deletedAt == recycledAt && $0.knowledgeBaseID == knowledgeBase.id
        })

        _ = try await store.deleteFolder(at: "临时", in: knowledgeBase.id)
        _ = try await store.restoreMaterials(ids: [
            missingFolderNote.summary.id,
            retainedFolderNote.summary.id
        ])

        let restoredStore = StudyNotesStore(rootURL: directory.url)
        let restoredIndex = try await restoredStore.loadIndex()
        #expect(restoredIndex.recycledMaterials.isEmpty)
        #expect(
            restoredIndex.materials.first {
                $0.id == missingFolderNote.summary.id
            }?.folderPath == ""
        )
        #expect(
            restoredIndex.materials.first {
                $0.id == retainedFolderNote.summary.id
            }?.folderPath == "保留"
        )

        _ = try await restoredStore.moveMaterialsToRecycleBin(
            ids: [missingFolderNote.summary.id],
            now: recycledAt
        )
        let exactlyThirtyDays = recycledAt.addingTimeInterval(30 * 24 * 60 * 60)
        #expect(try await restoredStore.purgeExpiredRecycleBin(now: exactlyThirtyDays).isEmpty)
        #expect(
            try await restoredStore.purgeExpiredRecycleBin(
                now: exactlyThirtyDays.addingTimeInterval(1)
            ) == [missingFolderNote.summary.id]
        )

        let rebuiltStore = StudyNotesStore(rootURL: directory.url)
        let finalIndex = try await rebuiltStore.loadIndex()
        #expect(finalIndex.recycledMaterials.isEmpty)
    }

    @Test("deleting a nested folder recycles every contained material")
    func deletingNestedFolderRecyclesContainedMaterials() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        let store = StudyNotesStore(rootURL: directory.url)
        let knowledgeBase = try await store.createKnowledgeBase(named: "算法")
        _ = try await store.createFolder(named: "外层", in: knowledgeBase.id)
        _ = try await store.createFolder(
            named: "内层",
            in: knowledgeBase.id,
            parentPath: "外层"
        )
        let note = try await store.createMarkdownNote(
            title: "嵌套材料",
            in: knowledgeBase.id,
            markdown: "# 嵌套",
            folderPath: "外层/内层"
        )

        let recycledIDs = try await store.deleteFolder(
            at: "外层",
            in: knowledgeBase.id
        )
        #expect(recycledIDs == [note.summary.id])

        let rebuiltStore = StudyNotesStore(rootURL: directory.url)
        let index = try await rebuiltStore.loadIndex()
        #expect(index.materials.isEmpty)
        #expect(index.folders.isEmpty)
        let recycled = try #require(index.recycledMaterials.first)
        #expect(recycled.id == note.summary.id)
        #expect(recycled.knowledgeBaseID == knowledgeBase.id)
        #expect(recycled.folderPath == "外层/内层")
        #expect(recycled.deletedAt != nil)
    }

    @Test("invalid paths, duplicate folders, and descendant moves are rejected")
    func invalidOrganizationOperationsAreRejected() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        let store = StudyNotesStore(rootURL: directory.url)
        let knowledgeBase = try await store.createKnowledgeBase(named: "算法")
        _ = try await store.createFolder(named: "A", in: knowledgeBase.id)
        _ = try await store.createFolder(named: "B", in: knowledgeBase.id, parentPath: "A")
        _ = try await store.createFolder(named: "C", in: knowledgeBase.id)
        let note = try await store.createMarkdownNote(
            title: "图论",
            in: knowledgeBase.id,
            markdown: "# 图论"
        )

        await expectStoreError(.folderAlreadyExists) {
            _ = try await store.createFolder(named: "A", in: knowledgeBase.id)
        }
        await expectStoreError(.folderAlreadyExists) {
            _ = try await store.renameFolder(at: "C", in: knowledgeBase.id, to: "A")
        }
        await expectStoreError(.invalidFolderMove) {
            _ = try await store.moveFolder(
                at: "A",
                in: knowledgeBase.id,
                toParentPath: "A/B"
            )
        }
        await expectStoreError(.folderNotFound) {
            _ = try await store.moveFolder(
                at: "A",
                in: knowledgeBase.id,
                toParentPath: "Missing"
            )
        }
        await expectStoreError(.invalidFolderPath) {
            _ = try await store.createFolder(
                named: "Escape",
                in: knowledgeBase.id,
                parentPath: "../outside"
            )
        }
        await expectStoreError(.invalidFolderName) {
            _ = try await store.createFolder(named: "bad/name", in: knowledgeBase.id)
        }
        let outsideURL = directory.url
            .appending(path: "Outside", directoryHint: .isDirectory)
        let knowledgeBaseURL = directory.url
            .appending(path: "Libraries", directoryHint: .isDirectory)
            .appending(path: knowledgeBase.id.uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: outsideURL, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: knowledgeBaseURL.appending(path: "Linked"),
            withDestinationURL: outsideURL
        )
        await expectStoreError(.invalidFolderPath) {
            _ = try await store.createFolder(
                named: "Escaped",
                in: knowledgeBase.id,
                parentPath: "Linked"
            )
        }
        await expectStoreError(.invalidFolderPath) {
            _ = try await store.moveMaterials(
                ids: [note.summary.id],
                toKnowledgeBaseID: knowledgeBase.id,
                folderPath: "A/../../outside"
            )
        }
        await expectStoreError(.folderNotFound) {
            _ = try await store.moveMaterials(
                ids: [note.summary.id],
                toKnowledgeBaseID: knowledgeBase.id,
                folderPath: "Missing"
            )
        }

        #expect(
            !FileManager.default.fileExists(
                atPath: directory.url.deletingLastPathComponent()
                    .appending(path: "outside")
                    .path
            )
        )
        let index = try await store.loadIndex()
        #expect(index.folders.map(\.path).sorted() == ["A", "A/B", "C"])
        #expect(index.materials.first?.folderPath == "")
    }

    @Test("a failed batch move rolls back every material and manifest")
    func failedBatchMoveRollsBack() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        let store = StudyNotesStore(rootURL: directory.url)
        let source = try await store.createKnowledgeBase(named: "来源")
        let target = try await store.createKnowledgeBase(named: "目标")
        let first = try await store.createMarkdownNote(
            title: "第一篇",
            in: source.id,
            markdown: "# 1"
        )
        let second = try await store.createMarkdownNote(
            title: "第二篇",
            in: source.id,
            markdown: "# 2"
        )

        let fileManager = ControllableMoveFileManager(failOnMove: 2)
        let failingStore = StudyNotesStore(rootURL: directory.url, fileManager: fileManager)
        do {
            _ = try await failingStore.moveMaterials(
                ids: [first.summary.id, second.summary.id],
                toKnowledgeBaseID: target.id
            )
            Issue.record("Expected the batch move to fail")
        } catch is InjectedMoveFailure {
        }

        let index = try await store.loadIndex()
        #expect(index.materials.count == 2)
        #expect(index.materials.allSatisfy { $0.knowledgeBaseID == source.id })
        #expect(index.materials.allSatisfy { $0.folderPath.isEmpty })
    }

    @Test("moving a material carries its sibling conflict copies")
    func movingMaterialCarriesConflictCopies() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        let store = StudyNotesStore(rootURL: directory.url)
        let source = try await store.createKnowledgeBase(named: "来源")
        let target = try await store.createKnowledgeBase(named: "目标")
        _ = try await store.createFolder(named: "重点", in: target.id)
        let note = try await store.createMarkdownNote(
            title: "图论",
            in: source.id,
            markdown: "# 图论"
        )
        let sourcePackage = try materialPackageURL(
            id: note.summary.id,
            in: source.id,
            rootURL: directory.url
        )
        let conflictName = "\(note.summary.id.uuidString) (conflicted copy).studyitem"
        let sourceConflict = sourcePackage
            .deletingLastPathComponent()
            .appending(path: conflictName, directoryHint: .isDirectory)
        try FileManager.default.copyItem(at: sourcePackage, to: sourceConflict)

        _ = try await store.moveMaterials(
            ids: [note.summary.id],
            toKnowledgeBaseID: target.id,
            folderPath: "重点"
        )

        let targetPackage = try materialPackageURL(
            id: note.summary.id,
            in: target.id,
            folderPath: "重点",
            rootURL: directory.url
        )
        let targetConflict = targetPackage
            .deletingLastPathComponent()
            .appending(path: conflictName, directoryHint: .isDirectory)
        #expect(!FileManager.default.fileExists(atPath: sourceConflict.path))
        #expect(FileManager.default.fileExists(atPath: targetConflict.path))

        let index = try await store.loadIndex()
        let moved = try #require(index.materials.first { $0.id == note.summary.id })
        #expect(moved.conflictCopies.map(\.relativePath) == [conflictName])
    }

    @Test("base containers cannot escape through symbolic links")
    func baseContainerSymlinksAreRejected() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        let outside = directory.url.appending(path: "Outside", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: directory.url.appending(path: "Libraries"),
            withDestinationURL: outside
        )

        let store = StudyNotesStore(rootURL: directory.url)
        do {
            _ = try await store.loadIndex()
            Issue.record("Expected a symbolic-link base container to be rejected")
        } catch let error as StudyNotesError {
            #expect(error == .invalidFolderPath)
        }
    }

    @Test("a failed folder rename restores the original folder and manifest paths")
    func failedFolderRenameRestoresManifestPaths() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        let setupStore = StudyNotesStore(rootURL: directory.url)
        let knowledgeBase = try await setupStore.createKnowledgeBase(named: "算法")
        _ = try await setupStore.createFolder(named: "A", in: knowledgeBase.id)
        let note = try await setupStore.createMarkdownNote(
            title: "图论",
            in: knowledgeBase.id,
            markdown: "# 图论",
            folderPath: "A"
        )

        let fileManager = ControllableMoveFileManager(failOnMove: 1)
        let failingStore = StudyNotesStore(
            rootURL: directory.url,
            fileManager: fileManager
        )
        do {
            _ = try await failingStore.renameFolder(
                at: "A",
                in: knowledgeBase.id,
                to: "B"
            )
            Issue.record("Expected the folder rename to fail")
        } catch is InjectedMoveFailure {
        }

        let rebuiltIndex = try await StudyNotesStore(
            rootURL: directory.url
        ).loadIndex()
        #expect(rebuiltIndex.folders.map(\.path) == ["A"])
        #expect(
            rebuiltIndex.materials.first { $0.id == note.summary.id }?.folderPath == "A"
        )
    }

    @Test("permanent purge removes sibling conflict copies with the material")
    func permanentPurgeRemovesConflictCopies() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        let store = StudyNotesStore(rootURL: directory.url)
        let knowledgeBase = try await store.createKnowledgeBase(named: "算法")
        let note = try await store.createMarkdownNote(
            title: "图论",
            in: knowledgeBase.id,
            markdown: "# 图论"
        )
        let packageURL = try materialPackageURL(
            id: note.summary.id,
            in: knowledgeBase.id,
            rootURL: directory.url
        )
        let conflictName = "\(note.summary.id.uuidString) (conflicted copy).studyitem"
        let conflictURL = packageURL
            .deletingLastPathComponent()
            .appending(path: conflictName, directoryHint: .isDirectory)
        try FileManager.default.copyItem(at: packageURL, to: conflictURL)

        let recycledAt = Date(timeIntervalSince1970: 1_800_000_000)
        _ = try await store.moveMaterialsToRecycleBin(
            ids: [note.summary.id],
            now: recycledAt
        )
        let recycledPackage = directory.url
            .appending(path: "RecycleBin", directoryHint: .isDirectory)
            .appending(
                path: "\(note.summary.id.uuidString).studyitem",
                directoryHint: .isDirectory
            )
        let recycledConflict = recycledPackage
            .deletingLastPathComponent()
            .appending(path: conflictName, directoryHint: .isDirectory)
        #expect(FileManager.default.fileExists(atPath: recycledConflict.path))

        let purged = try await store.purgeExpiredRecycleBin(
            now: recycledAt.addingTimeInterval(31 * 24 * 60 * 60)
        )
        #expect(purged == [note.summary.id])
        #expect(!FileManager.default.fileExists(atPath: recycledPackage.path))
        #expect(!FileManager.default.fileExists(atPath: recycledConflict.path))
    }
}

private func expectStoreError(
    _ expected: StudyNotesError,
    operation: () async throws -> Void
) async {
    do {
        try await operation()
        Issue.record("Expected \(expected)")
    } catch let error as StudyNotesError {
        #expect(error == expected)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

private func materialPackageURL(
    id: UUID,
    in knowledgeBaseID: UUID,
    folderPath: String = "",
    rootURL: URL
) throws -> URL {
    var directoryURL = rootURL
        .appending(path: "Libraries", directoryHint: .isDirectory)
        .appending(path: knowledgeBaseID.uuidString, directoryHint: .isDirectory)
    if !folderPath.isEmpty {
        directoryURL.append(path: folderPath, directoryHint: .isDirectory)
    }

    let packageURL = directoryURL.appending(
        path: "\(id.uuidString).studyitem",
        directoryHint: .isDirectory
    )
    guard FileManager.default.fileExists(atPath: packageURL.path) else {
        throw MissingPackage()
    }
    return packageURL
}

private struct MissingPackage: Error {}

private struct InjectedMoveFailure: Error {}

private final class ControllableMoveFileManager: FileManager, @unchecked Sendable {
    private var remainingMovesBeforeFailure: Int

    init(failOnMove: Int) {
        remainingMovesBeforeFailure = failOnMove
        super.init()
    }

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        if remainingMovesBeforeFailure == 1 {
            remainingMovesBeforeFailure = .max
            throw InjectedMoveFailure()
        }
        if remainingMovesBeforeFailure > 1 {
            remainingMovesBeforeFailure -= 1
        }
        try super.moveItem(at: srcURL, to: dstURL)
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
