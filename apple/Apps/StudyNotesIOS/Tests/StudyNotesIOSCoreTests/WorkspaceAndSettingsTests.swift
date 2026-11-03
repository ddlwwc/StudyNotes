import Foundation
import XCTest
@testable import StudyNotesIOSCore
import StudyNotesKit

final class WorkspaceAndSettingsTests: XCTestCase {
    func testLayoutSwitchPreservesWorkspaceSelectionAndEditing() {
        let knowledgeBaseID = UUID()
        let materialID = UUID()
        var state = IOSWorkspaceState(
            layout: .compact,
            knowledgeBaseID: knowledgeBaseID,
            folderPath: "学习科学/记忆",
            materialID: materialID,
            isEditing: true
        )

        state.updateLayout(.regular)

        XCTAssertEqual(state.layout, .regular)
        XCTAssertEqual(state.knowledgeBaseID, knowledgeBaseID)
        XCTAssertEqual(state.folderPath, "学习科学/记忆")
        XCTAssertEqual(state.materialID, materialID)
        XCTAssertTrue(state.isEditing)
    }

    func testNavigateBackReturnsThroughMaterialFolderAndKnowledgeBase() {
        let knowledgeBaseID = UUID()
        let materialID = UUID()
        var state = IOSWorkspaceState(
            knowledgeBaseID: knowledgeBaseID,
            folderPath: "学习科学/记忆",
            materialID: materialID,
            isEditing: true
        )

        state.navigateBack()
        XCTAssertEqual(state.folderPath, "学习科学/记忆")
        XCTAssertNil(state.materialID)
        XCTAssertFalse(state.isEditing)

        state.navigateBack()
        XCTAssertEqual(state.knowledgeBaseID, knowledgeBaseID)
        XCTAssertEqual(state.folderPath, "学习科学")

        state.navigateBack()
        XCTAssertEqual(state.knowledgeBaseID, knowledgeBaseID)
        XCTAssertEqual(state.folderPath, "")

        state.navigateBack()
        XCTAssertNil(state.knowledgeBaseID)
    }

    func testReconcileFallsBackToValidFolderAndPreservesValidEditing() {
        let knowledgeBaseID = UUID()
        let materialID = UUID()
        var state = IOSWorkspaceState(
            knowledgeBaseID: knowledgeBaseID,
            folderPath: "学习科学/记忆/工作记忆",
            materialID: materialID,
            isEditing: true
        )

        state.reconcile(
            validKnowledgeBaseIDs: [knowledgeBaseID],
            folderPaths: ["学习科学"],
            materialIDs: [materialID]
        )

        XCTAssertEqual(state.knowledgeBaseID, knowledgeBaseID)
        XCTAssertEqual(state.folderPath, "学习科学")
        XCTAssertEqual(state.materialID, materialID)
        XCTAssertTrue(state.isEditing)

        state.reconcile(
            validKnowledgeBaseIDs: [knowledgeBaseID],
            folderPaths: ["学习科学"],
            materialIDs: []
        )

        XCTAssertEqual(state.knowledgeBaseID, knowledgeBaseID)
        XCTAssertEqual(state.folderPath, "学习科学")
        XCTAssertNil(state.materialID)
        XCTAssertFalse(state.isEditing)

        state.reconcile(
            validKnowledgeBaseIDs: [],
            folderPaths: ["学习科学"],
            materialIDs: []
        )

        XCTAssertNil(state.knowledgeBaseID)
        XCTAssertEqual(state.folderPath, "")
        XCTAssertNil(state.materialID)
        XCTAssertFalse(state.isEditing)
    }

    func testFolderRebasePreservesSelectedMaterialAndEditing() {
        let knowledgeBaseID = UUID()
        let materialID = UUID()
        var state = IOSWorkspaceState(
            knowledgeBaseID: knowledgeBaseID,
            folderPath: "学习科学/记忆/工作记忆",
            materialID: materialID,
            isEditing: true
        )

        state.rebaseFolderPath(
            from: "学习科学/记忆",
            to: "学习科学/核心记忆"
        )

        XCTAssertEqual(
            state.folderPath,
            "学习科学/核心记忆/工作记忆"
        )
        XCTAssertEqual(state.materialID, materialID)
        XCTAssertTrue(state.isEditing)
    }

    func testInvalidFolderMovesRejectSelfAndDescendants() async throws {
        XCTAssertFalse(
            IOSWorkspaceState.isValidFolderMove(
                sourcePath: "",
                targetParentPath: "归档"
            )
        )
        XCTAssertFalse(
            IOSWorkspaceState.isValidFolderMove(
                sourcePath: "学习科学",
                targetParentPath: "学习科学"
            )
        )
        XCTAssertFalse(
            IOSWorkspaceState.isValidFolderMove(
                sourcePath: "学习科学",
                targetParentPath: "学习科学/记忆"
            )
        )
        XCTAssertTrue(
            IOSWorkspaceState.isValidFolderMove(
                sourcePath: "学习科学",
                targetParentPath: "归档"
            )
        )

        let directory = try WorkspaceTestDirectory()
        defer { directory.remove() }
        let knowledgeBaseID = try makeKnowledgeBase(
            in: directory.url,
            named: "学习科学"
        )
        let store = try IOSLibraryStore(rootURL: directory.url)
        _ = try await store.createFolder(
            named: "记忆",
            in: knowledgeBaseID
        )
        _ = try await store.createFolder(
            named: "工作记忆",
            in: knowledgeBaseID,
            parentPath: "记忆"
        )

        await assertStoreError(.invalidFolderMove) {
            _ = try await store.moveFolder(
                at: "记忆",
                in: knowledgeBaseID,
                toParentPath: "记忆/工作记忆"
            )
        }
    }

    func testFolderCRUDRejectsConflictsAndMovesNestedPaths() async throws {
        let directory = try WorkspaceTestDirectory()
        defer { directory.remove() }
        let knowledgeBaseID = try makeKnowledgeBase(
            in: directory.url,
            named: "学习科学"
        )
        let store = try IOSLibraryStore(rootURL: directory.url)

        let source = try await store.createFolder(
            named: "记忆",
            in: knowledgeBaseID
        )
        let child = try await store.createFolder(
            named: "工作记忆",
            in: knowledgeBaseID,
            parentPath: source.path
        )
        let target = try await store.createFolder(
            named: "归档",
            in: knowledgeBaseID
        )
        let noteID = try await store.createMarkdownNote(
            title: "容量限制",
            in: knowledgeBaseID,
            markdown: "# 容量限制\n\n工作记忆容量有限。",
            folderPath: child.path
        )

        XCTAssertEqual(source.parentPath, "")
        XCTAssertEqual(child.path, "记忆/工作记忆")

        await assertStoreError(.folderAlreadyExists) {
            _ = try await store.createFolder(
                named: "记忆",
                in: knowledgeBaseID
            )
        }

        let moved = try await store.moveFolder(
            at: source.path,
            in: knowledgeBaseID,
            toParentPath: target.path
        )
        XCTAssertEqual(moved.path, "归档/记忆")
        XCTAssertEqual(moved.parentPath, "归档")

        _ = try await store.createFolder(
            named: "已占用",
            in: knowledgeBaseID,
            parentPath: target.path
        )
        await assertStoreError(.folderAlreadyExists) {
            _ = try await store.renameFolder(
                at: moved.path,
                in: knowledgeBaseID,
                to: "已占用"
            )
        }

        let renamed = try await store.renameFolder(
            at: moved.path,
            in: knowledgeBaseID,
            to: "核心记忆"
        )
        XCTAssertEqual(renamed.path, "归档/核心记忆")

        let snapshot = try await store.snapshot(isICloud: false)
        XCTAssertTrue(
            snapshot.folders.contains {
                $0.path == "归档/核心记忆/工作记忆"
            }
        )
        let movedNote = try XCTUnwrap(
            snapshot.materials.first { $0.id == noteID }
        )
        XCTAssertEqual(movedNote.manifest.knowledgeBaseID, knowledgeBaseID)
        XCTAssertEqual(movedNote.folderPath, "归档/核心记忆/工作记忆")
    }

    func testDeletingFolderReturnsContainedMaterialsToRecycleBin() async throws {
        let directory = try WorkspaceTestDirectory()
        defer { directory.remove() }
        let knowledgeBaseID = try makeKnowledgeBase(
            in: directory.url,
            named: "学习科学"
        )
        let store = try IOSLibraryStore(rootURL: directory.url)
        let parent = try await store.createFolder(
            named: "待归档",
            in: knowledgeBaseID
        )
        let child = try await store.createFolder(
            named: "子目录",
            in: knowledgeBaseID,
            parentPath: parent.path
        )
        let parentNoteID = try await store.createMarkdownNote(
            title: "父目录笔记",
            in: knowledgeBaseID,
            markdown: "# 父目录笔记",
            folderPath: parent.path
        )
        let childNoteID = try await store.createMarkdownNote(
            title: "子目录笔记",
            in: knowledgeBaseID,
            markdown: "# 子目录笔记",
            folderPath: child.path
        )

        let recycledIDs = try await store.deleteFolder(
            at: parent.path,
            in: knowledgeBaseID
        )

        XCTAssertEqual(Set(recycledIDs), [parentNoteID, childNoteID])
        let snapshot = try await store.snapshot(isICloud: false)
        XCTAssertFalse(
            snapshot.folders.contains {
                $0.path == parent.path
                    || $0.path == child.path
            }
        )
        XCTAssertFalse(
            snapshot.materials.contains {
                [parentNoteID, childNoteID].contains($0.id)
            }
        )
    }

    func testMaterialMoveChangesKnowledgeBaseAndFolderThenRecycleBin() async throws {
        let directory = try WorkspaceTestDirectory()
        defer { directory.remove() }
        let sourceKnowledgeBaseID = try makeKnowledgeBase(
            in: directory.url,
            named: "学习科学"
        )
        let targetKnowledgeBaseID = try makeKnowledgeBase(
            in: directory.url,
            named: "考试复习"
        )
        let store = try IOSLibraryStore(rootURL: directory.url)
        let targetFolder = try await store.createFolder(
            named: "重点",
            in: targetKnowledgeBaseID
        )
        let noteID = try await store.createMarkdownNote(
            title: "记忆模型",
            in: sourceKnowledgeBaseID,
            markdown: "# 记忆模型"
        )

        try await store.moveMaterials(
            ids: [noteID],
            toKnowledgeBaseID: targetKnowledgeBaseID,
            folderPath: targetFolder.path
        )

        let movedSnapshot = try await store.snapshot(isICloud: false)
        let movedNote = try XCTUnwrap(
            movedSnapshot.materials.first { $0.id == noteID }
        )
        XCTAssertEqual(
            movedNote.manifest.knowledgeBaseID,
            targetKnowledgeBaseID
        )
        XCTAssertEqual(movedNote.folderPath, "重点")

        try await store.moveMaterialsToRecycleBin(ids: [noteID])

        let recycledSnapshot = try await store.snapshot(isICloud: false)
        XCTAssertFalse(
            recycledSnapshot.materials.contains { $0.id == noteID }
        )
    }

    func testCreateNoteInTargetFolderAndSaveMarkdown() async throws {
        let directory = try WorkspaceTestDirectory()
        defer { directory.remove() }
        let knowledgeBaseID = try makeKnowledgeBase(
            in: directory.url,
            named: "学习科学"
        )
        let store = try IOSLibraryStore(rootURL: directory.url)
        let folder = try await store.createFolder(
            named: "原地笔记",
            in: knowledgeBaseID
        )

        let noteID = try await store.createMarkdownNote(
            title: "工作记忆",
            in: knowledgeBaseID,
            markdown: "# 工作记忆\n\n初稿",
            folderPath: folder.path
        )
        let saved = try await store.saveMarkdown(
            materialID: noteID,
            text: "# 工作记忆\r\n\r\n更新后的正文",
            title: "工作记忆",
            createRecoveryVersion: false
        )

        XCTAssertEqual(saved, "# 工作记忆\n\n更新后的正文")
        let snapshot = try await store.snapshot(isICloud: false)
        let note = try XCTUnwrap(
            snapshot.materials.first { $0.id == noteID }
        )
        XCTAssertEqual(note.folderPath, folder.path)
        XCTAssertEqual(note.kind, .note)
    }

    @MainActor
    func testSettingsRoundTripLocallyAndKeepMediaKeyInSecretStore() throws {
        let (userDefaults, suiteName) = try makeIsolatedDefaults()
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let secretStore = InMemorySecretStore()
        let store = IOSSettingsStore(
            userDefaults: userDefaults,
            secretStore: secretStore
        )
        let preferences = ReadingPreferences(
            theme: .dark,
            fontSize: 20,
            lineWidth: 700,
            lineHeight: 1.9,
            codeFont: "Menlo"
        )

        try store.save(readingPreferences: preferences)
        store.savePublishingServerURL(
            "  https://notes.example.com  "
        )

        let reloaded = IOSSettingsStore(
            userDefaults: userDefaults,
            secretStore: secretStore
        )
        XCTAssertEqual(reloaded.loadReadingPreferences(), preferences)
        XCTAssertEqual(
            reloaded.loadPublishingServerURL(),
            "https://notes.example.com"
        )
        XCTAssertEqual(secretStore.allValues, [])
        XCTAssertTrue(
            userDefaults.dictionaryRepresentation().values
                .compactMap { $0 as? String }
                .contains("https://notes.example.com")
        )

        XCTAssertFalse(reloaded.hasMediaKey())
        try reloaded.saveMediaKey(
            "  media-secret-0123456789abcdefghijklmn  "
        )
        XCTAssertTrue(reloaded.hasMediaKey())
        XCTAssertEqual(
            secretStore.allValues,
            ["media-secret-0123456789abcdefghijklmn"]
        )
        XCTAssertFalse(
            userDefaults.dictionaryRepresentation().values
                .compactMap { $0 as? String }
                .contains("media-secret-0123456789abcdefghijklmn")
        )

        try reloaded.removeMediaKey()
        XCTAssertFalse(reloaded.hasMediaKey())
        XCTAssertEqual(secretStore.allValues, [])
    }

    private func makeKnowledgeBase(
        in rootURL: URL,
        named name: String
    ) throws -> UUID {
        let id = UUID()
        let libraryURL = rootURL
            .appending(path: "Libraries", directoryHint: .isDirectory)
            .appending(path: id.uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: libraryURL,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let metadata = KnowledgeBase(
            id: id,
            name: name,
            createdAt: Date()
        )
        try encoder.encode(metadata).write(
            to: libraryURL.appending(path: "knowledge-base.json"),
            options: .atomic
        )
        return id
    }

    @MainActor
    private func makeIsolatedDefaults() throws -> (UserDefaults, String) {
        let suiteName =
            "StudyNotesIOSCoreTests.Settings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    private func assertStoreError(
        _ expected: StudyNotesError,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail(
                "Expected \(expected), but the operation succeeded.",
                file: file,
                line: line
            )
        } catch let error as StudyNotesError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail(
                "Expected \(expected), but received \(error).",
                file: file,
                line: line
            )
        }
    }
}

private struct WorkspaceTestDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appending(
            path: "StudyNotesIOSWorkspaceTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

private final class InMemorySecretStore:
    SecretStoring,
    @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    var allValues: [String] {
        lock.lock()
        defer { lock.unlock() }
        return values.values.sorted()
    }

    func save(_ secret: String, account: String) throws {
        lock.lock()
        values[account] = secret
        lock.unlock()
    }

    func load(account: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[account]
    }

    func delete(account: String) throws {
        lock.lock()
        values.removeValue(forKey: account)
        lock.unlock()
    }
}
