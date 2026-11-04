import Foundation
import StudyNotesKit
import Testing
@testable import StudyNotesMacUI

@Suite("Mac workspace and settings seams")
@MainActor
struct WorkspaceModelTests {
    @Test("pane collapse, resize, reset, and relaunch restore are device-local")
    func panePreferencesPersist() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = makeModel(defaults: defaults)

        model.togglePane(.library)
        model.setPaneWidth(.library, width: 10_000)
        model.setPaneWidth(.materials, width: 1)
        model.setPaneWidth(.study, width: 300)

        #expect(!model.isLibraryPaneVisible)
        #expect(model.libraryPaneWidth == 320)
        #expect(model.materialPaneWidth == 240)
        #expect(model.studyPaneWidth == 300)

        model.restoreDefaultWidth(.study)
        let relaunched = makeModel(defaults: defaults)
        #expect(!relaunched.isLibraryPaneVisible)
        #expect(relaunched.libraryPaneWidth == 320)
        #expect(relaunched.materialPaneWidth == 240)
        #expect(relaunched.studyPaneWidth == WorkspacePreferences.defaultStudyWidth)
    }

    @Test("reading preferences clamp and survive relaunch")
    func readingPreferencesPersist() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = makeModel(defaults: defaults)
        model.readingPreferences = ReadingPreferences(
            theme: .dark,
            fontSize: 100,
            lineWidth: 1,
            lineHeight: 9,
            codeFont: "   "
        )

        let relaunched = makeModel(defaults: defaults)
        #expect(relaunched.readingPreferences.theme == .dark)
        #expect(relaunched.readingPreferences.fontSize == 24)
        #expect(relaunched.readingPreferences.lineWidth == 420)
        #expect(relaunched.readingPreferences.lineHeight == 2.2)
        #expect(relaunched.readingPreferences.codeFont == "SFMono-Regular")
    }

    @Test("publishing defaults are unlisted with private annotations and AI")
    func publishingDefaults() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = makeModel(defaults: defaults)

        #expect(model.appSettings.defaultPublishVisibility == .unlisted)
        #expect(!model.appSettings.publishAnnotationsByDefault)
        #expect(!model.appSettings.publishAIByDefault)

        model.updateAppSettings {
            $0.defaultPublishVisibility = .publicArticle
            $0.publishAnnotationsByDefault = true
            $0.publishAIByDefault = true
        }
        #expect(model.appSettings.defaultPublishVisibility == .publicArticle)
        #expect(model.appSettings.publishAnnotationsByDefault)
        #expect(model.appSettings.publishAIByDefault)
    }

    @Test("publishing panel starts from the stored default visibility")
    func publishingPanelUsesStoredDefault() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settingsStore = AppSettingsStore(userDefaults: defaults)

        let unlisted = PublishingPanelModel(
            credentialStore: MemoryPublishingCredentialStore(),
            settingsStore: settingsStore
        )
        #expect(unlisted.visibility == .unlisted)
        unlisted.visibility = .publicArticle
        #expect(settingsStore.load().defaultPublishVisibility == .unlisted)

        try? settingsStore.update {
            $0.defaultPublishVisibility = .publicArticle
        }
        let publicArticle = PublishingPanelModel(
            credentialStore: MemoryPublishingCredentialStore(),
            settingsStore: settingsStore
        )
        #expect(publicArticle.visibility == .publicArticle)
    }

    @Test("connection tester reports success, failure, and HTTP risk")
    func connectionTester() async {
        let success = ServiceConnectionTester { request in
            #expect(request.url?.path == "/api/v1/health")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(#"{"ok":true}"#.utf8), response)
        }
        let successResult = await success.test(
            .publishing,
            serverURLText: "http://127.0.0.1:8090"
        )
        #expect(successResult.usesHTTP)
        #expect(
            successResult.status
                == .succeeded("服务可达。")
        )

        let failure = ServiceConnectionTester { _ in
            throw URLError(.cannotConnectToHost)
        }
        let failureResult = await failure.test(
            .publishing,
            serverURLText: "https://example.com"
        )
        guard case .failed = failureResult.status else {
            Issue.record("Expected a failed connection status")
            return
        }
        #expect(!failureResult.usesHTTP)
    }

    @Test("note media key is stored only through the injected secret store")
    func mediaKeyUsesSecretStore() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let secrets = MemorySecretStore()
        let model = makeModel(defaults: defaults, mediaSecretStore: secrets)

        #expect(!model.hasNoteMediaKey)
        #expect(model.saveNoteMediaKey(" bearer-secret-0123456789abcdefghijklmn "))
        #expect(model.hasNoteMediaKey)
        #expect(
            model.noteMediaKeyForConnectionTest()
                == "bearer-secret-0123456789abcdefghijklmn"
        )
        #expect(defaults.data(forKey: "StudyNotes.AppSettings.v1") == nil)
    }

    @Test("drop rules reject folder cycles and allow cross-library material moves")
    func dropRules() {
        let knowledgeBaseID = UUID()
        let folder = WorkspaceDragPayload(
            kind: .folder,
            knowledgeBaseID: knowledgeBaseID,
            folderPath: "A"
        )
        let items = WorkspaceDragPayload(
            kind: .materials,
            knowledgeBaseID: knowledgeBaseID,
            materialIDs: [UUID()]
        )

        #expect(!WorkspaceDropRules.allows(
            folder,
            on: .folder(knowledgeBaseID: knowledgeBaseID, path: "A")
        ))
        #expect(!WorkspaceDropRules.allows(
            folder,
            on: .folder(knowledgeBaseID: knowledgeBaseID, path: "A/B")
        ))
        #expect(WorkspaceDropRules.allows(
            folder,
            on: .knowledgeBaseRoot(knowledgeBaseID)
        ))
        #expect(WorkspaceDropRules.allows(
            items,
            on: .folder(knowledgeBaseID: knowledgeBaseID, path: "B")
        ))
        #expect(WorkspaceDropRules.allows(
            items,
            on: .knowledgeBaseRoot(UUID())
        ))
        #expect(!WorkspaceDropRules.allows(
            WorkspaceDragPayload(kind: .materials, knowledgeBaseID: knowledgeBaseID),
            on: .knowledgeBaseRoot(knowledgeBaseID)
        ))
        #expect(WorkspaceDropRules.allows(
            WorkspaceDragPayload(
                kind: .materials,
                knowledgeBaseID: nil,
                materialIDs: [UUID()]
            ),
            on: .folder(knowledgeBaseID: knowledgeBaseID, path: "B")
        ))
    }

    @Test("knowledge base directory projects folders before materials at every level")
    func unifiedDirectoryProjection() async throws {
        let workspace = try await makeWorkspace { store in
            let knowledgeBase = try await store.createKnowledgeBase(named: "学习科学")
            _ = try await store.createFolder(
                named: "Zeta",
                in: knowledgeBase.id
            )
            _ = try await store.createFolder(
                named: "Alpha",
                in: knowledgeBase.id
            )
            _ = try await store.createFolder(
                named: "Beta",
                in: knowledgeBase.id,
                parentPath: "Alpha"
            )
            _ = try await store.createMarkdownNote(
                title: "B 根材料",
                in: knowledgeBase.id,
                markdown: "# B"
            )
            _ = try await store.createMarkdownNote(
                title: "A 根材料",
                in: knowledgeBase.id,
                markdown: "# A"
            )
            _ = try await store.createMarkdownNote(
                title: "C 子材料",
                in: knowledgeBase.id,
                markdown: "# C",
                folderPath: "Alpha"
            )
            return knowledgeBase.id
        }
        defer { workspace.remove() }

        await workspace.model.selectKnowledgeBase(workspace.knowledgeBaseID)

        #expect(
            workspace.model.childFolders(
                in: workspace.knowledgeBaseID,
                parentPath: ""
            ).map(\.name) == ["Alpha", "Zeta"]
        )
        #expect(
            workspace.model.childMaterials(
                in: workspace.knowledgeBaseID,
                parentPath: ""
            ).map(\.title) == ["A 根材料", "B 根材料"]
        )
        #expect(
            workspace.model.childFolders(
                in: workspace.knowledgeBaseID,
                parentPath: "Alpha"
            ).map(\.name) == ["Beta"]
        )
        #expect(
            workspace.model.childMaterials(
                in: workspace.knowledgeBaseID,
                parentPath: "Alpha"
            ).map(\.title) == ["C 子材料"]
        )
        #expect(
            workspace.model.materialCount(
                inKnowledgeBase: workspace.knowledgeBaseID
            ) == 3
        )
        #expect(
            workspace.model.folderMaterialCount(
                knowledgeBaseID: workspace.knowledgeBaseID,
                path: "Alpha"
            ) == 1
        )
        #expect(
            workspace.model.folderMaterialCount(
                knowledgeBaseID: workspace.knowledgeBaseID,
                path: "Alpha/Beta"
            ) == 0
        )
    }

    @Test("directory expansion persists locally and opens the selected material ancestors")
    func directoryExpansionPersistsAndExpandsAncestors() async throws {
        let workspace = try await makeWorkspace { store in
            let knowledgeBase = try await store.createKnowledgeBase(named: "学习科学")
            _ = try await store.createFolder(
                named: "Alpha",
                in: knowledgeBase.id
            )
            _ = try await store.createFolder(
                named: "Beta",
                in: knowledgeBase.id,
                parentPath: "Alpha"
            )
            _ = try await store.createMarkdownNote(
                title: "深层材料",
                in: knowledgeBase.id,
                markdown: "# 深层",
                folderPath: "Alpha/Beta"
            )
            return knowledgeBase.id
        }
        defer { workspace.remove() }

        await workspace.model.selectKnowledgeBase(workspace.knowledgeBaseID)
        #expect(
            workspace.model.expandedDirectoryPaths(
                in: workspace.knowledgeBaseID
            ) == [""]
        )

        workspace.model.toggleDirectoryExpansion(
            path: "Alpha",
            in: workspace.knowledgeBaseID
        )
        #expect(
            workspace.model.isDirectoryExpanded(
                path: "Alpha",
                in: workspace.knowledgeBaseID
            )
        )

        let relaunched = await workspace.relaunchModel()
        await relaunched.selectKnowledgeBase(workspace.knowledgeBaseID)
        #expect(
            relaunched.isDirectoryExpanded(
                path: "Alpha",
                in: workspace.knowledgeBaseID
            )
        )

        let material = try #require(
            relaunched.childMaterials(
                in: workspace.knowledgeBaseID,
                parentPath: "Alpha/Beta"
            ).first
        )
        await relaunched.selectTreeMaterial(
            material.id,
            mode: .replace
        )
        #expect(
            relaunched.isDirectoryExpanded(
                path: "Alpha/Beta",
                in: workspace.knowledgeBaseID
            )
        )
        #expect(relaunched.selectedDocument?.summary.id == material.id)
    }

    @Test("invalid expanded paths are removed when the index reloads")
    func invalidExpandedPathsAreRemoved() async throws {
        let workspace = try await makeWorkspace { store in
            let knowledgeBase = try await store.createKnowledgeBase(named: "学习科学")
            _ = try await store.createFolder(
                named: "临时",
                in: knowledgeBase.id
            )
            return knowledgeBase.id
        }
        defer { workspace.remove() }

        await workspace.model.selectKnowledgeBase(workspace.knowledgeBaseID)
        workspace.model.toggleDirectoryExpansion(
            path: "临时",
            in: workspace.knowledgeBaseID
        )
        let store = StudyNotesStore(rootURL: workspace.directory)
        let folder = try #require(
            try await store.loadIndex().folders.first {
                $0.path == "临时"
            }
        )
        _ = try await store.deleteFolder(
            at: folder.path,
            in: folder.knowledgeBaseID
        )

        await workspace.model.reloadIndex()

        #expect(
            workspace.model.expandedDirectoryPaths(
                in: workspace.knowledgeBaseID
            ) == [""]
        )
    }

    @Test("tree selection separates reading, material selection, and folder target")
    func treeSelectionKeepsActiveMaterial() async throws {
        let workspace = try await makeWorkspace { store in
            let knowledgeBase = try await store.createKnowledgeBase(named: "学习科学")
            _ = try await store.createFolder(
                named: "Alpha",
                in: knowledgeBase.id
            )
            _ = try await store.createMarkdownNote(
                title: "根材料",
                in: knowledgeBase.id,
                markdown: "# 根"
            )
            _ = try await store.createMarkdownNote(
                title: "Alpha 材料",
                in: knowledgeBase.id,
                markdown: "# Alpha",
                folderPath: "Alpha"
            )
            return knowledgeBase.id
        }
        defer { workspace.remove() }

        await workspace.model.selectKnowledgeBase(workspace.knowledgeBaseID)
        workspace.model.toggleDirectoryExpansion(
            path: "Alpha",
            in: workspace.knowledgeBaseID
        )
        let rootMaterial = try #require(
            workspace.model.childMaterials(
                in: workspace.knowledgeBaseID,
                parentPath: ""
            ).first
        )
        let childMaterial = try #require(
            workspace.model.childMaterials(
                in: workspace.knowledgeBaseID,
                parentPath: "Alpha"
            ).first
        )

        await workspace.model.selectTreeMaterial(
            rootMaterial.id,
            mode: .replace
        )
        await workspace.model.selectTreeMaterial(
            childMaterial.id,
            mode: .toggle
        )
        #expect(
            workspace.model.selectedMaterialIDs
                == [rootMaterial.id, childMaterial.id]
        )
        #expect(workspace.model.selectedDocument?.summary.id == rootMaterial.id)

        await workspace.model.selectTreeMaterial(
            rootMaterial.id,
            mode: .toggle
        )
        await workspace.model.selectionDidChange()
        #expect(workspace.model.selectedMaterialIDs == [childMaterial.id])
        #expect(workspace.model.selectedDocument?.summary.id == rootMaterial.id)

        workspace.model.toggleDirectoryExpansion(
            path: "Alpha",
            in: workspace.knowledgeBaseID
        )
        await workspace.model.selectTreeFolder(
            knowledgeBaseID: workspace.knowledgeBaseID,
            path: "Alpha"
        )
        #expect(workspace.model.selectedMaterialIDs.isEmpty)
        #expect(workspace.model.selectedDocument?.summary.id == rootMaterial.id)
        #expect(
            !workspace.model.isDirectoryExpanded(
                path: "Alpha",
                in: workspace.knowledgeBaseID
            )
        )
        #expect(
            workspace.model.selectedCollection
                == .folder(
                    knowledgeBaseID: workspace.knowledgeBaseID,
                    path: "Alpha"
                )
        )
    }

    @Test("visible tree material range supports shift selection across folders")
    func treeRangeSelectionUsesVisibleMaterialOrder() async throws {
        let workspace = try await makeWorkspace { store in
            let knowledgeBase = try await store.createKnowledgeBase(named: "学习科学")
            _ = try await store.createFolder(
                named: "Alpha",
                in: knowledgeBase.id
            )
            _ = try await store.createFolder(
                named: "Beta",
                in: knowledgeBase.id,
                parentPath: "Alpha"
            )
            _ = try await store.createMarkdownNote(
                title: "A 根",
                in: knowledgeBase.id,
                markdown: "# A"
            )
            _ = try await store.createMarkdownNote(
                title: "B Alpha",
                in: knowledgeBase.id,
                markdown: "# B",
                folderPath: "Alpha"
            )
            _ = try await store.createMarkdownNote(
                title: "C Beta",
                in: knowledgeBase.id,
                markdown: "# C",
                folderPath: "Alpha/Beta"
            )
            return knowledgeBase.id
        }
        defer { workspace.remove() }

        await workspace.model.selectKnowledgeBase(workspace.knowledgeBaseID)
        workspace.model.toggleDirectoryExpansion(
            path: "Alpha",
            in: workspace.knowledgeBaseID
        )
        workspace.model.toggleDirectoryExpansion(
            path: "Alpha/Beta",
            in: workspace.knowledgeBaseID
        )
        let visible = workspace.model.visibleDirectoryMaterialIDs(
            in: workspace.knowledgeBaseID
        )
        #expect(visible.count == 3)
        let first = try #require(visible.first)
        let last = try #require(visible.last)

        await workspace.model.selectTreeMaterial(first, mode: .replace)
        await workspace.model.selectTreeMaterial(last, mode: .extendRange)

        #expect(workspace.model.selectedMaterialIDs == Set(visible))
        #expect(workspace.model.selectedDocument?.summary.id == first)
    }

    @Test("create folder expands its parent and selects the new organization target")
    func createFolderLocatesNewFolderInTree() async throws {
        let workspace = try await makeWorkspace { store in
            let knowledgeBase = try await store.createKnowledgeBase(named: "学习科学")
            _ = try await store.createFolder(
                named: "父目录",
                in: knowledgeBase.id
            )
            return knowledgeBase.id
        }
        defer { workspace.remove() }

        await workspace.model.selectTreeKnowledgeBase(workspace.knowledgeBaseID)
        #expect(
            await workspace.model.createFolder(
                named: "新文件夹",
                in: workspace.knowledgeBaseID,
                parentPath: "父目录"
            )
        )

        #expect(
            workspace.model.selectedCollection
                == .folder(
                    knowledgeBaseID: workspace.knowledgeBaseID,
                    path: "父目录/新文件夹"
                )
        )
        #expect(workspace.model.selectedMaterialIDs.isEmpty)
        #expect(
            workspace.model.isDirectoryExpanded(
                path: "父目录",
                in: workspace.knowledgeBaseID
            )
        )
    }

    @Test("create note and import open the first material in its target folder")
    func createAndImportLocateMaterials() async throws {
        let workspace = try await makeWorkspace { store in
            let knowledgeBase = try await store.createKnowledgeBase(named: "学习科学")
            _ = try await store.createFolder(
                named: "目标",
                in: knowledgeBase.id
            )
            return knowledgeBase.id
        }
        defer { workspace.remove() }

        #expect(
            await workspace.model.createMarkdownNote(
                title: "定位笔记",
                markdown: "# 定位笔记",
                in: workspace.knowledgeBaseID,
                folderPath: "目标",
                tags: []
            )
        )
        #expect(
            workspace.model.selectedDocument?.summary.title == "定位笔记"
        )
        #expect(
            workspace.model.isDirectoryExpanded(
                path: "目标",
                in: workspace.knowledgeBaseID
            )
        )

        let sourceURL = FileManager.default.temporaryDirectory
            .appending(path: "StudyNotesImport-\(UUID().uuidString).md")
        try Data("# 导入材料\n\n导入正文".utf8).write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        #expect(
            await workspace.model.importFiles(
                [sourceURL],
                knowledgeBaseID: workspace.knowledgeBaseID,
                folderPath: "目标",
                tags: []
            )
        )
        #expect(workspace.model.selectedDocument?.summary.title == "导入材料")
        #expect(
            workspace.model.selectedDocument?.summary.folderPath == "目标"
        )
    }

    @Test("search stays flat, excludes folder names, and restores the tree")
    func searchResultsUseFlatMaterialResults() async throws {
        let workspace = try await makeWorkspace { store in
            let knowledgeBase = try await store.createKnowledgeBase(named: "学习科学")
            _ = try await store.createFolder(
                named: "仅文件夹名称",
                in: knowledgeBase.id
            )
            _ = try await store.createMarkdownNote(
                title: "可搜索材料",
                in: knowledgeBase.id,
                markdown: "# 可搜索材料\n\n正文关键词",
                folderPath: "仅文件夹名称"
            )
            return knowledgeBase.id
        }
        defer { workspace.remove() }

        await workspace.model.selectKnowledgeBase(workspace.knowledgeBaseID)
        let material = try #require(
            workspace.model.materials.first {
                $0.folderPath == "仅文件夹名称"
            }
        )
        await workspace.model.selectTreeMaterial(material.id, mode: .replace)
        workspace.model.toggleDirectoryExpansion(
            path: "仅文件夹名称",
            in: workspace.knowledgeBaseID
        )

        workspace.model.searchText = "仅文件夹名称"
        await workspace.model.searchDidChange()
        #expect(workspace.model.filteredMaterials.isEmpty)

        workspace.model.searchText = "正文关键词"
        await workspace.model.searchDidChange()
        #expect(
            workspace.model.filteredMaterials.map(\.id) == [material.id]
        )
        #expect(
            workspace.model.filteredMaterials.first?.folderPath
                == "仅文件夹名称"
        )
        #expect(
            workspace.model.isDirectoryExpanded(
                path: "仅文件夹名称",
                in: workspace.knowledgeBaseID
            ) == false
        )

        workspace.model.searchText = ""
        await workspace.model.searchDidChange()
        #expect(
            workspace.model.isDirectoryExpanded(
                path: "仅文件夹名称",
                in: workspace.knowledgeBaseID
            )
        )
        #expect(workspace.model.selectedDocument?.summary.id == material.id)
    }

    @Test("settings center exposes the five canonical pages")
    func settingsPages() {
        #expect(WorkspaceSettingsPage.allCases.count == 5)
        #expect(WorkspaceSettingsPage.allCases.map(\.title) == [
            "学习目录",
            "AI 配置",
            "发布配置",
            "密钥与凭据",
            "阅读偏好"
        ])
    }

    @Test("settings preserve the reading workspace and support contextual entry")
    func settingsPresentationPreservesReadingContext() async throws {
        let workspace = try await makeWorkspace { store in
            let knowledgeBase = try await store.createKnowledgeBase(named: "学习科学")
            _ = try await store.createMarkdownNote(
                title: "工作记忆",
                in: knowledgeBase.id,
                markdown: "# 工作记忆\n\n正文"
            )
            return knowledgeBase.id
        }
        defer { workspace.remove() }

        await workspace.model.selectKnowledgeBase(workspace.knowledgeBaseID)
        let material = try #require(workspace.model.materials.first)
        await workspace.model.selectMaterial(material.id)
        workspace.model.studyPanelTab = .ai
        let collection = workspace.model.selectedCollection

        #expect(await workspace.model.openSettings(page: .credentials))
        #expect(workspace.model.isShowingSettings)
        #expect(workspace.model.settingsPage == .credentials)
        #expect(workspace.model.selectedCollection == collection)
        #expect(workspace.model.readingMaterialID == material.id)
        #expect(workspace.model.studyPanelTab == .ai)

        workspace.model.returnToWorkspace()
        #expect(!workspace.model.isShowingSettings)
        #expect(workspace.model.readingMaterialID == material.id)
        #expect(workspace.model.studyPanelTab == .ai)

        #expect(await workspace.model.openSettings())
        #expect(workspace.model.settingsPage == .workspace)
        await workspace.model.selectInbox()
        #expect(!workspace.model.isShowingSettings)
        #expect(workspace.model.selectedCollection == .inbox)
    }

    @Test("an editor conflict prevents opening settings")
    func settingsHonorMarkdownSaveBarrier() async throws {
        let workspace = try await makeWorkspace { store in
            let knowledgeBase = try await store.createKnowledgeBase(named: "学习科学")
            _ = try await store.createMarkdownNote(
                title: "冲突材料",
                in: knowledgeBase.id,
                markdown: "# 冲突材料\n\n本地正文"
            )
            return knowledgeBase.id
        }
        defer { workspace.remove() }

        await workspace.model.selectKnowledgeBase(workspace.knowledgeBaseID)
        let material = try #require(workspace.model.materials.first)
        await workspace.model.selectMaterial(material.id)
        workspace.model.beginMarkdownEditing()
        let session = try #require(workspace.model.markdownEditorSession)

        let externalStore = StudyNotesStore(rootURL: workspace.directory)
        _ = try await externalStore.saveReaderCopy(
            id: material.id,
            text: "# 冲突材料\n\n外部正文",
            title: material.title,
            createRecoveryVersion: false
        )
        await session.requestExplicitSave()

        #expect(!(await workspace.model.openSettings()))
        #expect(!workspace.model.isShowingSettings)
        #expect(workspace.model.markdownEditorSession != nil)
        #expect(workspace.model.errorMessage != nil)
    }

    private func makeModel(
        defaults: UserDefaults,
        mediaSecretStore: any SecretStoring = MemorySecretStore()
    ) -> WorkspaceModel {
        WorkspaceModel(
            secretStore: MemorySecretStore(),
            mediaSecretStore: mediaSecretStore,
            devicePreferences: DevicePreferencesStore(userDefaults: defaults),
            appSettingsStore: AppSettingsStore(userDefaults: defaults)
        )
    }

    private func isolatedDefaults() -> (UserDefaults, String) {
        let suite = "StudyNotesMacUITests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }

    private func makeWorkspace(
        seed: (StudyNotesStore) async throws -> UUID
    ) async throws -> TestWorkspace {
        let directory = FileManager.default.temporaryDirectory
            .appending(
                path: "StudyNotesMacUITests-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let store = StudyNotesStore(rootURL: directory)
        let knowledgeBaseID = try await seed(store)
        let suiteName = "StudyNotesMacUITests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let rootStore = WorkspaceRootStore(userDefaults: defaults)
        _ = try rootStore.adoptDirectory(at: directory)
        let model = WorkspaceModel(
            rootStore: rootStore,
            secretStore: MemorySecretStore(),
            mediaSecretStore: MemorySecretStore(),
            devicePreferences: DevicePreferencesStore(userDefaults: defaults),
            appSettingsStore: AppSettingsStore(userDefaults: defaults),
            treeExpansionStore: WorkspaceTreeExpansionStore(
                userDefaults: defaults
            )
        )
        await model.restoreLastWorkspace()
        return TestWorkspace(
            directory: directory,
            defaults: defaults,
            suiteName: suiteName,
            model: model,
            knowledgeBaseID: knowledgeBaseID
        )
    }
}

@MainActor
private struct TestWorkspace {
    let directory: URL
    let defaults: UserDefaults
    let suiteName: String
    let model: WorkspaceModel
    let knowledgeBaseID: UUID

    func relaunchModel() async -> WorkspaceModel {
        let model = WorkspaceModel(
            rootStore: WorkspaceRootStore(userDefaults: defaults),
            secretStore: MemorySecretStore(),
            mediaSecretStore: MemorySecretStore(),
            devicePreferences: DevicePreferencesStore(userDefaults: defaults),
            appSettingsStore: AppSettingsStore(userDefaults: defaults),
            treeExpansionStore: WorkspaceTreeExpansionStore(
                userDefaults: defaults
            )
        )
        await model.restoreLastWorkspace()
        return model
    }

    func remove() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }
}

private final class MemorySecretStore: SecretStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    func save(_ secret: String, account: String) throws {
        lock.withLock {
            values[account] = secret
        }
    }

    func load(account: String) throws -> String? {
        lock.withLock {
            values[account]
        }
    }

    func delete(account: String) throws {
        lock.withLock {
            _ = values.removeValue(forKey: account)
        }
    }
}

private final class MemoryPublishingCredentialStore:
    PublishingCredentialStoring,
    @unchecked Sendable {
    private let lock = NSLock()
    private var credential: PublishingCredential?

    func load() throws -> PublishingCredential? {
        lock.withLock { credential }
    }

    func save(_ credential: PublishingCredential) throws {
        lock.withLock {
            self.credential = credential
        }
    }

    func delete() throws {
        lock.withLock {
            credential = nil
        }
    }
}
