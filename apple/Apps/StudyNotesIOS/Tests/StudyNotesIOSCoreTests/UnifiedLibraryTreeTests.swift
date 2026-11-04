import Foundation
import XCTest
@testable import StudyNotesIOSCore

final class UnifiedLibraryTreeTests: XCTestCase {
    @MainActor
    func testExpansionPersistsPerKnowledgeBaseAndPrunesStalePaths() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let settingsStore = IOSSettingsStore(userDefaults: defaults)
        let firstKnowledgeBaseID = UUID()
        let secondKnowledgeBaseID = UUID()
        var state = IOSWorkspaceState(
            knowledgeBaseID: firstKnowledgeBaseID
        )

        XCTAssertEqual(state.expandedFolderPaths, [""])
        state.toggleFolderExpansion("学习科学")
        state.expandAncestors(of: "学习科学/记忆")
        XCTAssertEqual(
            state.expandedFolderPaths,
            ["", "学习科学", "学习科学/记忆"]
        )
        settingsStore.saveExpandedFolderPaths(
            state.expandedFolderPaths,
            for: firstKnowledgeBaseID
        )

        var relaunched = IOSWorkspaceState(
            knowledgeBaseID: firstKnowledgeBaseID,
            expandedFolderPaths: settingsStore.loadExpandedFolderPaths(
                for: firstKnowledgeBaseID
            )
        )
        relaunched.reconcileExpandedFolders(
            validPaths: ["", "学习科学"]
        )

        XCTAssertEqual(
            relaunched.expandedFolderPaths,
            ["", "学习科学"]
        )
        XCTAssertEqual(
            settingsStore.loadExpandedFolderPaths(
                for: secondKnowledgeBaseID
            ),
            [""]
        )
    }

    func testFolderTargetClearsMaterialSelectionWithoutChangingOpenMaterial() {
        let knowledgeBaseID = UUID()
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()
        let fourthID = UUID()
        var state = IOSWorkspaceState(
            layout: .regular,
            knowledgeBaseID: knowledgeBaseID,
            folderPath: "学习科学"
        )

        state.openMaterial(firstID)
        state.toggleMaterialSelection(fourthID)
        XCTAssertEqual(state.materialID, firstID)
        XCTAssertEqual(state.selectedMaterialIDs, [firstID, fourthID])

        state.openMaterial(firstID, editing: true)
        state.extendMaterialSelection(
            to: fourthID,
            visibleMaterialIDs: [firstID, secondID, thirdID, fourthID]
        )
        XCTAssertEqual(
            state.selectedMaterialIDs,
            [firstID, secondID, thirdID, fourthID]
        )

        state.selectFolderForOrganization("学习科学/记忆")

        XCTAssertEqual(state.folderPath, "学习科学/记忆")
        XCTAssertEqual(state.materialID, firstID)
        XCTAssertTrue(state.isEditing)
        XCTAssertTrue(state.selectedMaterialIDs.isEmpty)
    }

    func testSearchMatchesMaterialMetadataButNotFolderOrKnowledgeBaseNames()
        async throws {
        let rootURL = FileManager.default.temporaryDirectory.appending(
            path: "StudyNotesUnifiedSearch-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try FileManager.default.createDirectory(
            at: rootURL.appending(path: "Libraries"),
            withIntermediateDirectories: true
        )
        let knowledgeBaseID = UUID()
        let now = Date()
        let material = LibraryMaterial(
            manifest: MaterialManifestRecord(
                id: UUID(),
                knowledgeBaseID: knowledgeBaseID,
                kind: "note",
                title: "工作记忆",
                createdAt: now,
                updatedAt: now,
                folderPath: "学习科学/记忆",
                tags: ["认知负荷"]
            ),
            knowledgeBaseName: "学习科学",
            packageURL: rootURL.appending(path: "missing.studyitem"),
            accessState: .metadataOnly
        )
        let snapshot = IOSLibrarySnapshot(
            knowledgeBases: [],
            materials: [material],
            rootURL: rootURL,
            isICloud: false
        )
        let search = LibrarySearchService(
            libraryStore: try IOSLibraryStore(rootURL: rootURL)
        )

        let titleHits = await search.search(
            query: "工作记忆",
            snapshot: snapshot
        )
        let folderHits = await search.search(
            query: "学习科学",
            snapshot: snapshot
        )
        let metadataHit = try XCTUnwrap(
            titleHits.first { $0.kind == .metadata }
        )

        XCTAssertTrue(metadataHit.snippet.contains("学习科学 / 记忆"))
        XCTAssertTrue(folderHits.isEmpty)
    }

    func testDropRulesRejectCyclesMaterialTargetsAndUseVisibleSelection() {
        let knowledgeBaseID = UUID()
        let draggedFolder = LibraryTreeDragPayload.folder(
            knowledgeBaseID: knowledgeBaseID,
            path: "学习科学"
        )

        XCTAssertFalse(
            LibraryTreeDropRules.allows(
                draggedFolder,
                on: .folder(
                    knowledgeBaseID: knowledgeBaseID,
                    path: "学习科学"
                ),
                layout: .regular
            )
        )
        XCTAssertFalse(
            LibraryTreeDropRules.allows(
                draggedFolder,
                on: .folder(
                    knowledgeBaseID: knowledgeBaseID,
                    path: "学习科学/记忆"
                ),
                layout: .regular
            )
        )
        XCTAssertTrue(
            LibraryTreeDropRules.allows(
                draggedFolder,
                on: .root(knowledgeBaseID: knowledgeBaseID),
                layout: .regular
            )
        )
        XCTAssertFalse(
            LibraryTreeDropRules.allows(
                draggedFolder,
                on: .root(knowledgeBaseID: knowledgeBaseID),
                layout: .compact
            )
        )

        let firstID = UUID()
        let secondID = UUID()
        let hiddenID = UUID()
        let unselectedID = UUID()
        XCTAssertEqual(
            LibraryTreeDropRules.materialIDsToMove(
                draggedID: firstID,
                selectedIDs: [firstID, secondID, hiddenID],
                visibleIDs: [firstID, secondID]
            ),
            [firstID, secondID]
        )
        XCTAssertEqual(
            LibraryTreeDropRules.materialIDsToMove(
                draggedID: unselectedID,
                selectedIDs: [firstID, secondID, hiddenID],
                visibleIDs: [firstID, secondID]
            ),
            [unselectedID]
        )
    }

    func testVisibleRowsUseFolderFirstLocalizedOrderAndRecursiveCounts() {
        let knowledgeBase = KnowledgeBaseSummary(
            id: UUID(),
            name: "学习科学",
            createdAt: Date()
        )
        let materials = [
            makeMaterial(
                named: "Beta Root",
                knowledgeBaseID: knowledgeBase.id,
                folderPath: ""
            ),
            makeMaterial(
                named: "Alpha Root",
                knowledgeBaseID: knowledgeBase.id,
                folderPath: ""
            ),
            makeMaterial(
                named: "Zulu Material",
                knowledgeBaseID: knowledgeBase.id,
                folderPath: "Zulu"
            )
        ]
        let folders = [
            makeFolder(
                named: "Zulu",
                path: "Zulu",
                parentPath: "",
                knowledgeBaseID: knowledgeBase.id
            ),
            makeFolder(
                named: "Empty",
                path: "Zulu/Empty",
                parentPath: "Zulu",
                knowledgeBaseID: knowledgeBase.id
            ),
            makeFolder(
                named: "Alpha",
                path: "Alpha",
                parentPath: "",
                knowledgeBaseID: knowledgeBase.id
            )
        ]

        let rows = LibraryTreeBuilder.visibleRows(
            knowledgeBase: knowledgeBase,
            materials: materials,
            folders: folders,
            expandedPaths: ["", "Zulu", "Zulu/Empty"]
        )

        XCTAssertEqual(
            rows.map(\.title),
            [
                "学习科学",
                "Alpha",
                "Zulu",
                "Empty",
                "Zulu Material",
                "Alpha Root",
                "Beta Root"
            ]
        )
        XCTAssertEqual(rows.map(\.depth), [0, 1, 1, 2, 2, 1, 1])
        XCTAssertEqual(rows.first?.materialCount, 3)
        XCTAssertEqual(
            rows.first { $0.title == "Zulu" }?.materialCount,
            1
        )
        XCTAssertEqual(
            rows.first { $0.title == "Empty" }?.materialCount,
            0
        )
    }

    private func makeMaterial(
        named title: String,
        knowledgeBaseID: UUID,
        folderPath: String
    ) -> LibraryMaterial {
        let now = Date()
        return LibraryMaterial(
            manifest: MaterialManifestRecord(
                id: UUID(),
                knowledgeBaseID: knowledgeBaseID,
                kind: "note",
                title: title,
                createdAt: now,
                updatedAt: now,
                folderPath: folderPath
            ),
            knowledgeBaseName: "学习科学",
            packageURL: URL(fileURLWithPath: "/tmp/\(UUID()).studyitem"),
            accessState: .downloaded
        )
    }

    private func makeFolder(
        named name: String,
        path: String,
        parentPath: String,
        knowledgeBaseID: UUID
    ) -> IOSFolder {
        IOSFolder(
            knowledgeBaseID: knowledgeBaseID,
            name: name,
            path: path,
            parentPath: parentPath
        )
    }

    @MainActor
    private func makeIsolatedDefaults() throws -> (UserDefaults, String) {
        let suiteName =
            "StudyNotesIOSCoreTests.UnifiedTree.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
