import Foundation
import Network
import Observation
import StudyNotesKit

@MainActor
@Observable
public final class WorkspaceModel {
    public private(set) var knowledgeBases: [KnowledgeBase] = []
    public private(set) var materials: [StudyMaterialSummary] = []
    public private(set) var folders: [KnowledgeFolder] = []
    public private(set) var inboxMaterials: [StudyMaterialSummary] = []
    public private(set) var recycledMaterials: [StudyMaterialSummary] = []
    public private(set) var tags: [String] = []
    public private(set) var selectedNote: MarkdownNote?
    public private(set) var selectedDocument: MaterialDocument?
    public private(set) var markdownEditorSession: MarkdownEditorSession?
    public private(set) var annotations: [MaterialAnnotation] = []
    public private(set) var conversations: [AIConversation] = []
    public private(set) var revisions: [TextRevision] = []
    public private(set) var searchHits: [SearchHit] = []
    public private(set) var searchHitsQuery = ""
    public private(set) var providerProfiles: [AIProviderProfile] = []
    public private(set) var aiPhase: AIRequestPhase = .idle
    public private(set) var aiStreamingText = ""
    public private(set) var activeConversationID: UUID?
    public var pendingAIContext: AIContextPreview?
    public private(set) var publishPreview: PublishPreview?
    public private(set) var noteMediaStatus: NoteMediaStatusResponse?
    public private(set) var noteMediaConnection: ServiceConnectionStatus = .idle
    public private(set) var noteMediaQueue: [NoteMediaUploadItem] = []
    public private(set) var noteMediaCacheByteCount = 0
    public private(set) var noteMediaScan: NoteMediaReferenceScanResponse?
    public private(set) var noteMediaHistoricalFiles:
        [NoteMediaHistoricalLocalFile] = []
    public private(set) var isScanningNoteMedia = false
    public private(set) var connectionState: WorkspaceConnectionState = .disconnected
    public private(set) var isLoadingIndex = false
    public private(set) var isLoadingNote = false
    public private(set) var isPerformingAction = false
    public private(set) var errorMessage: String?
    public private(set) var actionNotice: String?
    public private(set) var workspacePreferences: WorkspacePreferences
    public var readingPreferences: ReadingPreferences {
        didSet {
            try? devicePreferences.save(readingPreferences: readingPreferences)
        }
    }
    public var settingsPage: WorkspaceSettingsPage = .workspace

    public var selectedCollection: WorkspaceCollection = .all
    public var selectedMaterialIDs: Set<UUID> = []
    public private(set) var readingMaterialID: UUID?
    public private(set) var expandedDirectoryPathsByKnowledgeBase:
        [UUID: Set<String>] = [:]
    public var searchText = ""
    public var studyPanelTab: StudyPanelTab = .annotations
    public var isShowingCreateKnowledgeBase = false
    public var isShowingCreateNote = false
    public var isShowingMoveMaterials = false
    public var isShowingEditTags = false
    public var isConfirmingRecycle = false
    public var isConfirmingPurgeExpired = false
    public var isShowingImport = false
    public var isShowingWebImport = false
    public var isShowingEditReaderCopy = false
    public var isShowingVersions = false
    public var isShowingLinkMaterials = false
    public var isShowingPublishPreview = false
    public var annotationDraftRequest: AnnotationDraftRequest?
    public var selectedProviderID: UUID?
    public var aiPromptText = ""
    public var readerSelection: ReaderSelection?
    public var annotationJumpID: UUID?
    public var documentSearchText = ""
    public var readerHeadingJumpID: String?
    public var webArticleURLText = ""
    public var webArticleDraft: WebArticleDraft?
    public var webArticleMarkdown = ""
    public var webArticleStatus = ""
    public var isFetchingWebArticle = false
    public var publishIncludeAnnotations = false
    public var publishIncludeAI = false
    public var searchKindFilter: StudyMaterialKind?
    public var searchUpdatedAfter: Date?
    public var createFolderRequest: WorkspaceCreateFolderRequest?
    public var renameRequest: WorkspaceRenameTarget?
    public var moveFolderRequest: WorkspaceMoveFolderRequest?
    public var createNoteTarget: WorkspaceDestination?
    public var importTarget: WorkspaceDestination?
    public var activeDragPayload: WorkspaceDragPayload?

    @ObservationIgnored private let rootStore: WorkspaceRootStore
    @ObservationIgnored private var store: StudyNotesStore?
    @ObservationIgnored private let secretStore: any SecretStoring
    @ObservationIgnored private let mediaSecretStore: any SecretStoring
    @ObservationIgnored private let mediaCredentialStore:
        KeychainNoteMediaCredentialStore
    @ObservationIgnored private var mediaCoordinator: NoteMediaCoordinator?
    @ObservationIgnored private let mediaSupportURL: URL?
    @ObservationIgnored private let mediaNetworkMonitor = NWPathMonitor()
    @ObservationIgnored private let mediaNetworkQueue = DispatchQueue(
        label: "com.studynotes.media-network"
    )
    @ObservationIgnored private let devicePreferences: DevicePreferencesStore
    @ObservationIgnored private let appSettingsStore: AppSettingsStore
    @ObservationIgnored private let treeExpansionStore:
        WorkspaceTreeExpansionStore
    @ObservationIgnored private let aiClient: OpenAICompatibleClient
    @ObservationIgnored private let webArticleFetcher: WebArticleFetcher
    @ObservationIgnored private var aiTask: Task<Void, Never>?
    @ObservationIgnored private var aiStopRequested = false
    @ObservationIgnored private var didRestoreWorkspace = false
    @ObservationIgnored private var noteLoadGeneration = 0
    @ObservationIgnored private var refreshGeneration = 0
    @ObservationIgnored private var treeSelectionAnchorID: UUID?

    public init(
        rootStore: WorkspaceRootStore = WorkspaceRootStore(),
        secretStore: any SecretStoring = KeychainSecretStore(),
        mediaSecretStore: any SecretStoring = KeychainSecretStore(
            service: "com.studynotes.note-media"
        ),
        devicePreferences: DevicePreferencesStore = DevicePreferencesStore(),
        appSettingsStore: AppSettingsStore = AppSettingsStore(),
        treeExpansionStore: WorkspaceTreeExpansionStore =
            WorkspaceTreeExpansionStore(),
        aiClient: OpenAICompatibleClient = OpenAICompatibleClient(),
        webArticleFetcher: WebArticleFetcher = WebArticleFetcher(),
        mediaCoordinator: NoteMediaCoordinator? = nil
    ) {
        self.rootStore = rootStore
        self.secretStore = secretStore
        self.mediaSecretStore = mediaSecretStore
        let credentialStore = KeychainNoteMediaCredentialStore(
            secretStore: mediaSecretStore
        )
        mediaCredentialStore = credentialStore
        mediaSupportURL = Self.mediaApplicationSupportURL()
        if let mediaCoordinator {
            self.mediaCoordinator = mediaCoordinator
        } else if let supportURL = mediaSupportURL,
                  let baseURL = URL(
                      string: appSettingsStore.load().publishingServerURL
                  ) {
            self.mediaCoordinator = try? NoteMediaCoordinator(
                applicationSupportRoot: supportURL,
                baseURL: baseURL,
                credentialStore: credentialStore
            )
        } else {
            self.mediaCoordinator = nil
        }
        self.devicePreferences = devicePreferences
        self.appSettingsStore = appSettingsStore
        self.treeExpansionStore = treeExpansionStore
        self.aiClient = aiClient
        self.webArticleFetcher = webArticleFetcher
        workspacePreferences = devicePreferences.loadWorkspacePreferences()
        readingPreferences = devicePreferences.loadReadingPreferences()
        providerProfiles = AIProviderSettingsStore.load()
        selectedProviderID = providerProfiles.first?.id
        mediaNetworkMonitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else {
                return
            }
            Task { @MainActor [weak self] in
                await self?.refreshNoteMediaState()
            }
        }
        mediaNetworkMonitor.start(queue: mediaNetworkQueue)
    }

    deinit {
        mediaNetworkMonitor.cancel()
    }

    public var libraryPaneWidth: Double {
        workspacePreferences.libraryWidth
    }

    public var materialPaneWidth: Double {
        workspacePreferences.materialsWidth
    }

    public var studyPaneWidth: Double {
        workspacePreferences.studyWidth
    }

    public var isLibraryPaneVisible: Bool {
        !workspacePreferences.isLibraryCollapsed
    }

    public var isMaterialPaneVisible: Bool {
        !workspacePreferences.isMaterialsCollapsed
    }

    public var isStudyPanelVisible: Bool {
        get { !workspacePreferences.isStudyCollapsed }
        set {
            workspacePreferences.isStudyCollapsed = !newValue
            persistWorkspacePreferences()
        }
    }

    public func togglePane(_ pane: WorkspacePane) {
        switch pane {
        case .library:
            workspacePreferences.isLibraryCollapsed.toggle()
        case .materials:
            workspacePreferences.isMaterialsCollapsed.toggle()
        case .study:
            workspacePreferences.isStudyCollapsed.toggle()
        }
        persistWorkspacePreferences()
    }

    public func setPaneWidth(_ pane: WorkspacePane, width: Double) {
        switch pane {
        case .library:
            workspacePreferences.libraryWidth = width
        case .materials:
            workspacePreferences.materialsWidth = width
        case .study:
            workspacePreferences.studyWidth = width
        }
        persistWorkspacePreferences()
    }

    public func restoreDefaultWidth(_ pane: WorkspacePane) {
        switch pane {
        case .library:
            workspacePreferences.libraryWidth = WorkspacePreferences.defaultLibraryWidth
        case .materials:
            workspacePreferences.materialsWidth = WorkspacePreferences.defaultMaterialsWidth
        case .study:
            workspacePreferences.studyWidth = WorkspacePreferences.defaultStudyWidth
        }
        persistWorkspacePreferences()
    }

    public var isConnected: Bool {
        if case .connected = connectionState {
            return true
        }
        return false
    }

    public var canCreateNote: Bool {
        isConnected
    }

    public var canCreateFolder: Bool {
        isConnected && !knowledgeBases.isEmpty
    }

    public var selectedMaterialID: UUID? {
        selectedMaterialIDs.count == 1 ? selectedMaterialIDs.first : nil
    }

    public var selectedKnowledgeBaseID: UUID? {
        switch selectedCollection {
        case let .knowledgeBase(id):
            id
        case let .folder(knowledgeBaseID, _):
            knowledgeBaseID
        case .all, .inbox, .recycleBin, .tag:
            nil
        }
    }

    public var selectedFolderPath: String? {
        guard case let .folder(_, path) = selectedCollection else {
            return nil
        }
        return path
    }

    public var selectedKnowledgeBase: KnowledgeBase? {
        guard let selectedKnowledgeBaseID else {
            return nil
        }
        return knowledgeBases.first { $0.id == selectedKnowledgeBaseID }
    }

    public var selectedFolder: KnowledgeFolder? {
        guard case let .folder(knowledgeBaseID, path) = selectedCollection else {
            return nil
        }
        return folders.first {
            $0.knowledgeBaseID == knowledgeBaseID && $0.path == path
        }
    }

    public var searchTagFilter: String? {
        guard case let .tag(tag) = selectedCollection else {
            return nil
        }
        return tag
    }

    public var selectedProvider: AIProviderProfile? {
        guard let selectedProviderID else {
            return providerProfiles.first
        }
        return providerProfiles.first { $0.id == selectedProviderID }
    }

    public var activeConversation: AIConversation? {
        guard let activeConversationID else {
            return nil
        }
        return conversations.first { $0.id == activeConversationID }
    }

    public var canExplainSelection: Bool {
        selectedDocument != nil
            && readerSelection?.quote.isEmpty == false
            && selectedProvider != nil
    }

    public var canSummarizeMaterial: Bool {
        selectedDocument != nil && selectedProvider != nil
    }

    public var canPreviewPublish: Bool {
        selectedDocument?.summary.kind.canPublish == true
    }

    public var allActiveMaterials: [StudyMaterialSummary] {
        materials + inboxMaterials
    }

    public var allMaterials: [StudyMaterialSummary] {
        materials + inboxMaterials + recycledMaterials
    }

    public var selectedMaterials: [StudyMaterialSummary] {
        allMaterials.filter { selectedMaterialIDs.contains($0.id) }
    }

    public var selectedMaterial: StudyMaterialSummary? {
        guard let selectedMaterialID else {
            return nil
        }
        return allMaterials.first { $0.id == selectedMaterialID }
    }

    public var filteredMaterials: [StudyMaterialSummary] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty, searchHitsQuery == query {
            let byID = Dictionary(uniqueKeysWithValues: allActiveMaterials.map { ($0.id, $0) })
            var seen = Set<UUID>()
            return searchHits.compactMap { hit in
                guard seen.insert(hit.materialID).inserted else {
                    return nil
                }
                return byID[hit.materialID]
            }
        }
        return directoryMaterials.filter { material in
            guard !query.isEmpty else {
                return true
            }
            let haystack = [
                material.title,
                material.tags.joined(separator: " ")
            ].joined(separator: " ")
            return haystack.localizedCaseInsensitiveContains(query)
        }
    }

    public var currentDirectoryFolderPath: String {
        selectedFolderPath ?? ""
    }

    public var currentDirectoryKnowledgeBaseID: UUID? {
        selectedKnowledgeBaseID
    }

    public var directChildFolders: [KnowledgeFolder] {
        guard let selectedKnowledgeBaseID else {
            return []
        }
        let parentPath = currentDirectoryFolderPath
        return childFolders(
            in: selectedKnowledgeBaseID,
            parentPath: parentPath
        )
    }

    public func childFolders(
        in knowledgeBaseID: UUID,
        parentPath: String
    ) -> [KnowledgeFolder] {
        folders(in: knowledgeBaseID)
            .filter { $0.parentPath == parentPath }
    }

    public func childMaterials(
        in knowledgeBaseID: UUID,
        parentPath: String
    ) -> [StudyMaterialSummary] {
        materials
            .filter {
                $0.knowledgeBaseID == knowledgeBaseID
                    && $0.folderPath == parentPath
            }
            .sorted(by: materialNameOrder)
    }

    public var directoryMaterials: [StudyMaterialSummary] {
        let directMaterials: [StudyMaterialSummary]
        switch selectedCollection {
        case .all:
            directMaterials = materials
        case let .knowledgeBase(id):
            directMaterials = materials.filter {
                $0.knowledgeBaseID == id && $0.folderPath.isEmpty
            }
        case let .folder(knowledgeBaseID, path):
            directMaterials = materials.filter {
                $0.knowledgeBaseID == knowledgeBaseID && $0.folderPath == path
            }
        case .inbox:
            directMaterials = inboxMaterials
        case .recycleBin:
            directMaterials = recycledMaterials
        case let .tag(tag):
            directMaterials = allActiveMaterials.filter { material in
                material.tags.contains {
                    $0.compare(tag, options: .caseInsensitive) == .orderedSame
                }
            }
        }
        return directMaterials.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    public var scopeTitle: String {
        switch selectedCollection {
        case .all:
            "全部材料"
        case let .knowledgeBase(id):
            knowledgeBases.first { $0.id == id }?.name ?? "知识库"
        case let .folder(_, path):
            path.split(separator: "/").last.map(String.init) ?? "文件夹"
        case .inbox:
            "收件箱"
        case .recycleBin:
            "回收站"
        case let .tag(tag):
            "#\(tag)"
        }
    }

    public var scopeSubtitle: String {
        switch selectedCollection {
        case .all:
            return "\(knowledgeBases.count) 个知识库 · \(materials.count) 篇材料"
        case let .knowledgeBase(id):
            let folderCount = folders.count {
                $0.knowledgeBaseID == id && $0.parentPath.isEmpty
            }
            return "\(folderCount) 个文件夹 · \(directoryMaterials.count) 篇材料"
        case let .folder(knowledgeBaseID, path):
            let folder = folders.first {
                $0.knowledgeBaseID == knowledgeBaseID && $0.path == path
            }
            return "\(folder?.name ?? path) · \(directoryMaterials.count) 篇材料"
        case .inbox:
            return "\(inboxMaterials.count) 篇待整理材料"
        case .recycleBin:
            return "\(recycledMaterials.count) 篇 · 保留 30 天"
        case let .tag(tag):
            return "\(tagMaterialCount(tag)) 篇带此标签的材料"
        }
    }

    public var scopeSystemImage: String {
        switch selectedCollection {
        case .all:
            "tray.full"
        case .knowledgeBase:
            "books.vertical"
        case .folder:
            "folder"
        case .inbox:
            "tray"
        case .recycleBin:
            "trash"
        case .tag:
            "tag"
        }
    }

    public var hasSelection: Bool {
        !selectedMaterialIDs.isEmpty
    }

    public var isRecycleScope: Bool {
        selectedCollection == .recycleBin
    }

    public var canMoveSelection: Bool {
        hasSelection && !isRecycleScope
    }

    public var canEditSelectionTags: Bool {
        hasSelection && !isRecycleScope
    }

    public var canRecycleSelection: Bool {
        hasSelection && !isRecycleScope
    }

    public var canRestoreSelection: Bool {
        hasSelection && isRecycleScope
    }

    public var hasExpiredRecycleItems: Bool {
        !expiredRecycledMaterials.isEmpty
    }

    public var expiredRecycleCount: Int {
        expiredRecycledMaterials.count
    }

    public var selectedTagsForEditing: [String] {
        Array(Set(selectedMaterials.flatMap(\.tags))).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    public var defaultKnowledgeBaseIDForCreation: UUID? {
        selectedKnowledgeBaseID ?? knowledgeBases.first?.id
    }

    public var defaultFolderPathForCreation: String {
        selectedFolderPath ?? ""
    }

    public var connectionLabel: String {
        switch connectionState {
        case .disconnected:
            "未连接"
        case .restoring:
            "正在恢复目录"
        case .connecting:
            "正在加载"
        case let .connected(location):
            location.storageKind.label
        case .failed:
            "连接失败"
        }
    }

    public var connectionDetail: String {
        switch connectionState {
        case .disconnected:
            "尚未选择学习目录"
        case .restoring:
            "正在恢复上次的访问权限"
        case .connecting:
            "正在读取知识库索引"
        case let .connected(location):
            location.displayName
        case let .failed(message):
            message
        }
    }

    public func restoreLastWorkspace() async {
        guard !didRestoreWorkspace else {
            return
        }
        didRestoreWorkspace = true
        connectionState = .restoring

        do {
            guard let location = try rootStore.restoreSavedDirectory() else {
                connectionState = .disconnected
                return
            }
            await loadWorkspace(at: location)
            await refreshNoteMediaState()
        } catch {
            connectionState = .failed(error.localizedDescription)
        }
    }

    public func chooseWorkspace() async {
        guard !isPerformingAction else {
            return
        }

        guard let url = await rootStore.chooseDirectory() else {
            return
        }

        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            let location = try rootStore.adoptDirectory(at: url)
            await loadWorkspace(at: location)
        } catch {
            connectionState = .failed(error.localizedDescription)
        }
    }

    public func chooseICloudWorkspace() async {
        guard !isPerformingAction else {
            return
        }

        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            guard let url = try await rootStore.chooseICloudDirectory() else {
                return
            }
            let location = try rootStore.adoptDirectory(at: url)
            await loadWorkspace(at: location)
        } catch {
            connectionState = .failed(error.localizedDescription)
        }
    }

    public func reloadIndex() async {
        _ = await refreshIndex(
            preferredCollection: selectedCollection,
            preferredSelection: selectedMaterialIDs
        )
    }

    public func selectCollection(_ collection: WorkspaceCollection) async {
        guard !isLoadingIndex else {
            return
        }
        guard collectionIsAvailable(collection) else {
            return
        }

        guard await flushMarkdownEditorBeforeSelectionChange() else {
            return
        }
        invalidateNoteLoad()
        selectedCollection = collection
        selectedMaterialIDs = []
        readingMaterialID = nil
        treeSelectionAnchorID = nil
        selectedNote = nil
        selectedDocument = nil
        annotations = []
        conversations = []
        readerSelection = nil
        searchHits = []
        searchHitsQuery = ""
        await selectFirstMaterialIfAvailable()
    }

    public func selectKnowledgeBase(_ id: UUID?) async {
        await selectCollection(id.map(WorkspaceCollection.knowledgeBase) ?? .all)
    }

    public func selectFolder(knowledgeBaseID: UUID, path: String) async {
        await selectCollection(.folder(knowledgeBaseID: knowledgeBaseID, path: path))
    }

    public func selectTreeKnowledgeBase(_ knowledgeBaseID: UUID) async {
        guard await flushMarkdownEditorBeforeSelectionChange() else {
            return
        }
        selectedCollection = .knowledgeBase(knowledgeBaseID)
        selectedMaterialIDs = []
        treeSelectionAnchorID = nil
        searchHits = []
        searchHitsQuery = ""
    }

    public func selectTreeFolder(
        knowledgeBaseID: UUID,
        path: String
    ) async {
        guard await flushMarkdownEditorBeforeSelectionChange() else {
            return
        }
        selectedCollection = .folder(
            knowledgeBaseID: knowledgeBaseID,
            path: path
        )
        selectedMaterialIDs = []
        treeSelectionAnchorID = nil
        searchHits = []
        searchHitsQuery = ""
    }

    public func selectInbox() async {
        await selectCollection(.inbox)
    }

    public func selectRecycleBin() async {
        await selectCollection(.recycleBin)
    }

    public func selectTag(_ tag: String) async {
        await selectCollection(.tag(tag))
    }

    public func selectionDidChange() async {
        guard !isLoadingIndex else {
            return
        }
        if selectedMaterialIDs.count == 1,
           let id = selectedMaterialIDs.first,
           let hit = searchHits.first(where: { $0.materialID == id }) {
            isStudyPanelVisible = true
            if hit.matchedLayer == .ai {
                studyPanelTab = .ai
            } else if hit.matchedLayer == .annotation {
                studyPanelTab = .annotations
            }
        }
        await updateReaderForSelection()
    }

    public func searchDidChange() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let store, !query.isEmpty else {
            searchHits = []
            searchHitsQuery = ""
            let visibleIDs = Set(filteredMaterials.map(\.id))
            selectedMaterialIDs.formIntersection(visibleIDs)
            if let readingMaterialID,
               let knowledgeBaseID = allActiveMaterials.first(where: {
                   $0.id == readingMaterialID
               })?.knowledgeBaseID,
               let material = allActiveMaterials.first(where: {
                   $0.id == readingMaterialID
               }) {
                expandDirectoryAncestors(
                    of: material.folderPath,
                    in: knowledgeBaseID
                )
            }
            await updateReaderForSelection()
            return
        }
        do {
            searchHits = try await store.search(
                query,
                filter: SearchFilter(
                    knowledgeBaseID: selectedKnowledgeBaseID,
                    kind: searchKindFilter,
                    tag: searchTagFilter,
                    updatedAfter: searchUpdatedAfter
                )
            )
            searchHitsQuery = query
        } catch {
            searchHits = []
            searchHitsQuery = query
            present(error)
        }
        let visibleIDs = Set(filteredMaterials.map(\.id))
        selectedMaterialIDs.formIntersection(visibleIDs)
        await updateReaderForSelection()
    }

    public func selectMaterial(_ id: UUID) async {
        guard !isLoadingIndex else {
            return
        }
        if selectedMaterialID != id {
            guard await flushMarkdownEditorBeforeSelectionChange() else {
                return
            }
        }
        if let hit = searchHits.first(where: { $0.materialID == id }) {
            isStudyPanelVisible = true
            if hit.matchedLayer == .ai {
                studyPanelTab = .ai
            } else if hit.matchedLayer == .annotation {
                studyPanelTab = .annotations
            }
        }
        selectedMaterialIDs = [id]
        readingMaterialID = id
        treeSelectionAnchorID = id
        if let material = allMaterials.first(where: { $0.id == id }),
           let knowledgeBaseID = material.knowledgeBaseID {
            expandDirectoryAncestors(
                of: material.folderPath,
                in: knowledgeBaseID
            )
        }
        await updateReaderForSelection()
    }

    public func selectTreeMaterial(
        _ id: UUID,
        mode: WorkspaceTreeSelectionMode
    ) async {
        guard let material = allMaterials.first(where: { $0.id == id }) else {
            return
        }
        if let knowledgeBaseID = material.knowledgeBaseID {
            expandDirectoryAncestors(
                of: material.folderPath,
                in: knowledgeBaseID
            )
        }

        switch mode {
        case .replace:
            await selectMaterial(id)
        case .toggle:
            if selectedMaterialIDs.contains(id) {
                selectedMaterialIDs.remove(id)
            } else {
                selectedMaterialIDs.insert(id)
            }
            treeSelectionAnchorID = id
        case .extendRange:
            guard let knowledgeBaseID = material.knowledgeBaseID else {
                return
            }
            let visibleIDs = visibleDirectoryMaterialIDs(in: knowledgeBaseID)
            let anchorID = treeSelectionAnchorID ?? readingMaterialID
            guard let anchorID,
                  let start = visibleIDs.firstIndex(of: anchorID),
                  let end = visibleIDs.firstIndex(of: id) else {
                selectedMaterialIDs = [id]
                treeSelectionAnchorID = id
                return
            }
            selectedMaterialIDs = Set(
                visibleIDs[min(start, end)...max(start, end)]
            )
        }
    }

    public func expandedDirectoryPaths(
        in knowledgeBaseID: UUID
    ) -> Set<String> {
        expandedDirectoryPathsByKnowledgeBase[knowledgeBaseID] ?? [""]
    }

    public func isDirectoryExpanded(
        path: String,
        in knowledgeBaseID: UUID
    ) -> Bool {
        expandedDirectoryPaths(in: knowledgeBaseID).contains(path)
    }

    public func toggleDirectoryExpansion(
        path: String,
        in knowledgeBaseID: UUID
    ) {
        var paths = expandedDirectoryPaths(in: knowledgeBaseID)
        if paths.contains(path) {
            paths.remove(path)
        } else {
            paths.insert(path)
        }
        persistDirectoryExpansion(paths, in: knowledgeBaseID)
    }

    public func expandDirectoryAncestors(
        of path: String,
        in knowledgeBaseID: UUID
    ) {
        var paths = expandedDirectoryPaths(in: knowledgeBaseID)
        paths.formUnion(DirectoryPath.expandedAncestors(of: path))
        persistDirectoryExpansion(paths, in: knowledgeBaseID)
    }

    public func visibleDirectoryMaterialIDs(
        in knowledgeBaseID: UUID
    ) -> [UUID] {
        guard isDirectoryExpanded(path: "", in: knowledgeBaseID) else {
            return []
        }
        var result: [UUID] = []
        appendVisibleDirectoryMaterialIDs(
            in: knowledgeBaseID,
            parentPath: "",
            to: &result
        )
        return result
    }

    public func materials(in collection: WorkspaceCollection) -> [StudyMaterialSummary] {
        switch collection {
        case .all:
            materials
        case let .knowledgeBase(id):
            materials.filter { $0.knowledgeBaseID == id }
        case let .folder(knowledgeBaseID, path):
            materials.filter {
                $0.knowledgeBaseID == knowledgeBaseID
                    && ($0.folderPath == path || $0.folderPath.hasPrefix("\(path)/"))
            }
        case .inbox:
            inboxMaterials
        case .recycleBin:
            recycledMaterials
        case let .tag(tag):
            allActiveMaterials.filter { material in
                material.tags.contains {
                    $0.compare(tag, options: .caseInsensitive) == .orderedSame
                }
            }
        }
    }

    public func materialCount(inKnowledgeBase id: UUID) -> Int {
        materials.count { $0.knowledgeBaseID == id }
    }

    public func folderMaterialCount(knowledgeBaseID: UUID, path: String) -> Int {
        materials.count {
            $0.knowledgeBaseID == knowledgeBaseID
                && ($0.folderPath == path || $0.folderPath.hasPrefix("\(path)/"))
        }
    }

    public func tagMaterialCount(_ tag: String) -> Int {
        allActiveMaterials.count { material in
            material.tags.contains {
                $0.compare(tag, options: .caseInsensitive) == .orderedSame
            }
        }
    }

    public func folders(in knowledgeBaseID: UUID) -> [KnowledgeFolder] {
        folders
            .filter { $0.knowledgeBaseID == knowledgeBaseID }
            .sorted(by: folderNameOrder)
    }

    public func folderOptions(
        in knowledgeBaseID: UUID,
        excluding excludedFolder: KnowledgeFolder? = nil
    ) -> [KnowledgeFolder] {
        folders(in: knowledgeBaseID).filter { folder in
            guard let excludedFolder else {
                return true
            }
            return folder.path != excludedFolder.path
                && !folder.path.hasPrefix("\(excludedFolder.path)/")
        }
    }

    public var expiredRecycledMaterials: [StudyMaterialSummary] {
        let now = Date()
        return recycledMaterials.filter { material in
            guard let deletedAt = material.deletedAt else {
                return false
            }
            return now.timeIntervalSince(deletedAt) > 30 * 24 * 60 * 60
        }
    }

    public func presentCreateNoteSheet() {
        guard canCreateNote else {
            return
        }
        let target = selectedCollection == .inbox
            ? nil
            : defaultKnowledgeBaseIDForCreation.map {
                WorkspaceDestination(
                    knowledgeBaseID: $0,
                    folderPath: defaultFolderPathForCreation
                )
            }
        createBlankMarkdownNote(at: target)
    }

    public func presentCreateNoteSheet(
        in knowledgeBaseID: UUID,
        folderPath: String
    ) {
        guard canCreateNote else {
            return
        }
        createBlankMarkdownNote(
            at: WorkspaceDestination(
                knowledgeBaseID: knowledgeBaseID,
                folderPath: folderPath
            )
        )
    }

    private func createBlankMarkdownNote(
        at destination: WorkspaceDestination?
    ) {
        let title = availableBlankNoteTitle(
            knowledgeBaseID: destination?.knowledgeBaseID,
            folderPath: destination?.folderPath ?? ""
        )
        let markdown = "# \(title)\n\n"
        Task {
            let created: Bool
            if let knowledgeBaseID = destination?.knowledgeBaseID {
                created = await createMarkdownNote(
                    title: title,
                    markdown: markdown,
                    in: knowledgeBaseID,
                    folderPath: destination?.folderPath ?? "",
                    tags: []
                )
            } else {
                created = await createInboxMarkdownNote(
                    title: title,
                    markdown: markdown,
                    tags: []
                )
            }
            if created, let materialID = selectedMaterialIDs.first {
                await loadMaterial(id: materialID)
                beginMarkdownEditing()
            }
        }
    }

    private func availableBlankNoteTitle(
        knowledgeBaseID: UUID?,
        folderPath: String
    ) -> String {
        let existingTitles: Set<String> = Set(
            allActiveMaterials.compactMap { material in
                guard material.knowledgeBaseID == knowledgeBaseID,
                      material.folderPath == folderPath else {
                    return nil
                }
                return material.title
            }
        )
        guard existingTitles.contains("新笔记") else {
            return "新笔记"
        }
        var suffix = 2
        while existingTitles.contains("新笔记 \(suffix)") {
            suffix += 1
        }
        return "新笔记 \(suffix)"
    }

    public func presentCreateKnowledgeBaseSheet() {
        guard isConnected else {
            return
        }
        isShowingCreateKnowledgeBase = true
    }

    public func presentCreateFolderSheet(parentPath: String? = nil) {
        guard let knowledgeBaseID = selectedKnowledgeBaseID ?? knowledgeBases.first?.id else {
            return
        }
        let resolvedParentPath = parentPath ?? selectedFolderPath ?? ""
        presentCreateFolderSheet(
            in: knowledgeBaseID,
            parentPath: resolvedParentPath
        )
    }

    public func presentCreateFolderSheet(
        in knowledgeBaseID: UUID,
        parentPath: String
    ) {
        createFolderRequest = WorkspaceCreateFolderRequest(
            knowledgeBaseID: knowledgeBaseID,
            parentPath: parentPath
        )
    }

    public var appSettings: AppSettings {
        appSettingsStore.load()
    }

    public func updateAppSettings(_ change: (inout AppSettings) -> Void) {
        let previousServerURL = appSettings.publishingServerURL
        do {
            try appSettingsStore.update(change)
            if appSettings.publishingServerURL != previousServerURL {
                Task { await refreshNoteMediaState() }
            }
        } catch {
            present(error)
        }
    }

    public func saveNoteMediaKey(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "笔记媒体密钥不能为空。"
            return false
        }
        do {
            try mediaCredentialStore.save(
                NoteMediaCredential(secret: trimmed)
            )
            actionNotice = "笔记媒体密钥已保存到本机钥匙串"
            Task { await refreshNoteMediaState() }
            return true
        } catch {
            present(error)
            return false
        }
    }

    public var hasNoteMediaKey: Bool {
        (try? mediaCredentialStore.load()) != nil
    }

    public func noteMediaKeyForConnectionTest() -> String? {
        (try? mediaCredentialStore.load())?.secret
    }

    public var noteMediaHTTPWarning: String? {
        guard appSettings.publishingServerURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasPrefix("http://") else {
            return noteMediaStatus?.httpWarning == true
                ? "媒体服务报告当前链路使用 HTTP。"
                : nil
        }
        return "当前媒体服务使用 HTTP，Bearer 密钥可能在传输中被截获。"
    }

    public var readerMediaCoordinator: NoteMediaCoordinator? {
        mediaCoordinator
    }

    public func refreshNoteMediaState() async {
        if mediaCoordinator == nil {
            guard let mediaSupportURL,
                  let baseURL = URL(
                      string: appSettings.publishingServerURL
                  ) else {
                noteMediaConnection = .failed("媒体协调器未初始化。")
                return
            }
            mediaCoordinator = try? NoteMediaCoordinator(
                applicationSupportRoot: mediaSupportURL,
                baseURL: baseURL,
                credentialStore: mediaCredentialStore
            )
        }
        guard let mediaCoordinator else {
            noteMediaConnection = .failed("媒体协调器未初始化。")
            return
        }
        noteMediaConnection = .testing
        noteMediaQueue = await mediaCoordinator.items()
        noteMediaCacheByteCount =
            (try? await mediaCoordinator.cacheSize()) ?? 0
        do {
            guard let baseURL = URL(
                string: appSettings.publishingServerURL
            ) else {
                throw NoteMediaCoordinatorError.invalidBaseURL
            }
            try await mediaCoordinator.configure(baseURL: baseURL)
            noteMediaStatus = try await mediaCoordinator.status()
            guard let status = noteMediaStatus else {
                throw NoteMediaClientError.invalidResponse
            }
            noteMediaConnection = .succeeded(
                status.message ?? (status.ok ? "媒体服务可用。" : "媒体服务未就绪。")
            )
            await resumePendingNoteMediaUploads()
        } catch {
            noteMediaStatus = nil
            noteMediaConnection = .failed(error.localizedDescription)
        }
    }

    @discardableResult
    public func insertNoteMedia(
        fileAt url: URL,
        contentType: String,
        connection: NoteMediaConnection,
        confirmedCellularUpload: Bool = false
    ) async -> NoteMediaInsertionDecision? {
        guard let mediaCoordinator else {
            errorMessage = "媒体协调器未初始化。"
            return nil
        }
        do {
            let decision = try await mediaCoordinator.prepareInsertion(
                fileAt: url,
                contentType: contentType,
                connection: connection,
                confirmedCellularUpload: confirmedCellularUpload
            )
            noteMediaQueue = await mediaCoordinator.items()
            return decision
        } catch {
            present(error)
            return nil
        }
    }

    public func uploadNoteMedia(id: UUID) async {
        guard let mediaCoordinator else {
            return
        }
        let refreshTask = startNoteMediaQueuePolling()
        defer { refreshTask.cancel() }
        do {
            _ = try await mediaCoordinator.upload(id: id)
            noteMediaQueue = await mediaCoordinator.items()
        } catch {
            noteMediaQueue = await mediaCoordinator.items()
            present(error)
        }
    }

    public func reloadSelectedDocumentMedia() async {
        guard let store,
              let materialID = selectedDocument?.summary.id else {
            return
        }
        do {
            let document = try await store.loadMaterialDocument(id: materialID)
            selectedDocument = await resolvedMediaDocument(document)
        } catch {
            present(error)
        }
    }

    public func retryNoteMediaUpload(id: UUID) async {
        guard let mediaCoordinator else {
            return
        }
        let refreshTask = startNoteMediaQueuePolling()
        defer { refreshTask.cancel() }
        do {
            _ = try await mediaCoordinator.retry(id: id)
            noteMediaQueue = await mediaCoordinator.items()
        } catch {
            noteMediaQueue = await mediaCoordinator.items()
            present(error)
        }
    }

    public func cancelNoteMediaUpload(id: UUID) async {
        guard let mediaCoordinator else {
            return
        }
        do {
            try await mediaCoordinator.cancel(id: id)
            noteMediaQueue = await mediaCoordinator.items()
        } catch {
            present(error)
        }
    }

    public func clearNoteMediaCache() async {
        guard let mediaCoordinator else {
            return
        }
        do {
            try await mediaCoordinator.clearCache()
            noteMediaCacheByteCount = 0
            actionNotice = "已清除本机媒体派生缓存"
        } catch {
            present(error)
        }
    }

    public var noteMediaCleanupCandidates: [NoteMediaUploadItem] {
        let result = NoteMediaReferenceScanner.scan(
            currentMarkdown: markdownEditorSession?.markdown
                ?? selectedDocument?.markdown
                ?? "",
            historicalMarkdowns: revisions.map(\.text)
        )
        let referenced = Set(result.referencedObjectKeys)
        return noteMediaQueue.filter {
            $0.state == .uploaded
                && !referenced.contains($0.reference.objectKey)
        }
    }

    public var noteMediaCurrentByteCount: Int {
        noteMediaByteCount(for: .current)
    }

    public var noteMediaHistoricalByteCount: Int {
        noteMediaByteCount(for: .history)
    }

    public var noteMediaCleanupCandidateByteCount: Int {
        noteMediaCleanupCandidates.reduce(0) { $0 + $1.byteCount }
    }

    public func scanSelectedNoteMedia() async {
        guard let mediaCoordinator, let document = selectedDocument else {
            errorMessage = "请先打开一篇笔记再扫描媒体。"
            return
        }
        noteMediaScan = nil
        noteMediaHistoricalFiles = []
        isScanningNoteMedia = true
        defer { isScanningNoteMedia = false }
        do {
            let legacyDirectory = document.sourceURL
                .appending(path: "source", directoryHint: .isDirectory)
                .appending(path: "media", directoryHint: .isDirectory)
            noteMediaHistoricalFiles =
                try NoteMediaCoordinator.historicalLocalFiles(
                    in: legacyDirectory
                )
            let historicalRevisions = try await store?.loadTextRevisions(
                id: document.id
            ) ?? []
            revisions = historicalRevisions
            noteMediaScan = try await mediaCoordinator.scan(
                sourceId: document.id.uuidString,
                currentMarkdown: document.markdown,
                historicalMarkdowns: historicalRevisions.map(\.text),
                historicalLocalMedia: noteMediaHistoricalFiles.map {
                    NoteMediaHistoricalLocalReference(
                        reference: $0.reference,
                        size: $0.size
                    )
                }
            )
            noteMediaQueue = await mediaCoordinator.items()
            noteMediaCacheByteCount =
                (try? await mediaCoordinator.cacheSize()) ?? 0
        } catch {
            present(error)
        }
    }

    public func migrateSelectedNoteMediaHistory() async {
        guard let mediaCoordinator else {
            return
        }
        do {
            let references = try await mediaCoordinator
                .migrateHistoricalLocalFiles(
                    noteMediaHistoricalFiles,
                    confirmed: true
                )
            noteMediaQueue = await mediaCoordinator.items()
            actionNotice =
                "已将 \(references.count) 个历史媒体加入待上传队列；正文引用未自动改写"
        } catch {
            present(error)
        }
    }

    public func cleanupUnreferencedNoteMedia() async {
        guard let mediaCoordinator else {
            return
        }
        await scanSelectedNoteMedia()
        guard noteMediaScan != nil else {
            return
        }
        let candidates = noteMediaCleanupCandidates
        guard !candidates.isEmpty else {
            actionNotice = "没有可清理的本机已知云端媒体"
            return
        }
        do {
            let response = try await mediaCoordinator.cleanup(
                objectKeys: candidates.map(\.reference.objectKey),
                confirmed: true
            )
            actionNotice = response.queued.isEmpty
                ? "服务端已跳过全部清理请求"
                : "已排队清理 \(response.queued.count) 个媒体对象"
        } catch {
            present(error)
        }
    }

    private static func mediaApplicationSupportURL() -> URL? {
        guard let baseURL = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            return nil
        }
        let url = baseURL.appending(
            path: "StudyNotes",
            directoryHint: .isDirectory
        )
        try? FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }

    private func noteMediaByteCount(
        for scope: NoteMediaReferenceScope
    ) -> Int {
        noteMediaScan?.media
            .filter { $0.scopes.contains(scope) }
            .reduce(0) { $0 + ($1.size ?? 0) } ?? 0
    }

    private func startNoteMediaQueuePolling() -> Task<Void, Never> {
        Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let coordinator = mediaCoordinator else {
                    return
                }
                noteMediaQueue = await coordinator.items()
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    private func resumePendingNoteMediaUploads() async {
        guard noteMediaStatus?.ok == true else {
            return
        }
        for item in noteMediaQueue where item.state == .waiting {
            await uploadNoteMedia(id: item.id)
        }
    }

    public func canDrop(
        _ payload: WorkspaceDragPayload,
        on target: WorkspaceDropTarget
    ) -> Bool {
        WorkspaceDropRules.allows(payload, on: target)
    }

    @discardableResult
    public func drop(
        _ payload: WorkspaceDragPayload,
        on target: WorkspaceDropTarget
    ) async -> Bool {
        guard canDrop(payload, on: target) else {
            return false
        }
        switch payload.kind {
        case .folder:
            guard let knowledgeBaseID = payload.knowledgeBaseID,
                  let path = payload.folderPath,
                  let folder = folders.first(where: {
                      $0.knowledgeBaseID == knowledgeBaseID
                          && $0.path == path
                  }) else {
                return false
            }
            return await moveFolder(folder, toParentPath: target.folderPath)
        case .materials:
            return await moveMaterials(
                ids: Set(payload.materialIDs),
                toKnowledgeBaseID: target.knowledgeBaseID,
                folderPath: target.folderPath
            )
        }
    }

    @discardableResult
    public func createKnowledgeBase(named name: String) async -> Bool {
        guard let store, isConnected else {
            return false
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return false
        }

        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            let knowledgeBase = try await store.createKnowledgeBase(named: trimmedName)
            let succeeded = await refreshIndex(
                preferredCollection: .knowledgeBase(knowledgeBase.id),
                preferredSelection: []
            )
            if succeeded {
                isShowingCreateKnowledgeBase = false
                actionNotice = "已创建知识库“\(knowledgeBase.name)”"
            }
            return succeeded
        } catch {
            present(error)
            return false
        }
    }

    @discardableResult
    public func createFolder(
        named name: String,
        in knowledgeBaseID: UUID,
        parentPath: String
    ) async -> Bool {
        guard let store, isConnected else {
            return false
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return false
        }

        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            let folder = try await store.createFolder(
                named: trimmedName,
                in: knowledgeBaseID,
                parentPath: parentPath
            )
            let succeeded = await refreshIndex(
                preferredCollection: .folder(
                    knowledgeBaseID: knowledgeBaseID,
                    path: folder.path
                ),
                preferredSelection: [],
                autoSelectFirst: false
            )
            if succeeded {
                expandDirectoryAncestors(
                    of: folder.parentPath,
                    in: knowledgeBaseID
                )
                createFolderRequest = nil
                actionNotice = "已创建文件夹“\(folder.name)”"
            }
            return succeeded
        } catch {
            present(error)
            return false
        }
    }

    @discardableResult
    public func renameKnowledgeBase(id: UUID, to name: String) async -> Bool {
        guard let store, isConnected else {
            return false
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return false
        }

        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            let knowledgeBase = try await store.renameKnowledgeBase(id: id, to: trimmedName)
            let succeeded = await refreshIndex(
                preferredCollection: selectedCollection,
                preferredSelection: selectedMaterialIDs
            )
            if succeeded {
                renameRequest = nil
                actionNotice = "已重命名为“\(knowledgeBase.name)”"
            }
            return succeeded
        } catch {
            present(error)
            return false
        }
    }

    @discardableResult
    public func renameFolder(_ folder: KnowledgeFolder, to name: String) async -> Bool {
        guard let store, isConnected else {
            return false
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return false
        }

        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            let renamed = try await store.renameFolder(
                at: folder.path,
                in: folder.knowledgeBaseID,
                to: trimmedName
            )
            rebaseDirectoryExpansion(
                from: folder.path,
                to: renamed.path,
                in: folder.knowledgeBaseID
            )
            let collection = mappedCollection(
                selectedCollection,
                knowledgeBaseID: folder.knowledgeBaseID,
                oldPath: folder.path,
                newPath: renamed.path
            )
            let succeeded = await refreshIndex(
                preferredCollection: collection,
                preferredSelection: selectedMaterialIDs
            )
            if succeeded {
                renameRequest = nil
                actionNotice = "已重命名为“\(renamed.name)”"
            }
            return succeeded
        } catch {
            present(error)
            return false
        }
    }

    @discardableResult
    public func moveFolder(
        _ folder: KnowledgeFolder,
        toParentPath parentPath: String
    ) async -> Bool {
        guard let store, isConnected else {
            return false
        }

        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            let moved = try await store.moveFolder(
                at: folder.path,
                in: folder.knowledgeBaseID,
                toParentPath: parentPath
            )
            rebaseDirectoryExpansion(
                from: folder.path,
                to: moved.path,
                in: folder.knowledgeBaseID
            )
            let collection = mappedCollection(
                selectedCollection,
                knowledgeBaseID: folder.knowledgeBaseID,
                oldPath: folder.path,
                newPath: moved.path
            )
            let succeeded = await refreshIndex(
                preferredCollection: collection,
                preferredSelection: selectedMaterialIDs
            )
            if succeeded {
                moveFolderRequest = nil
                actionNotice = "已移动文件夹“\(moved.name)”"
            }
            return succeeded
        } catch {
            present(error)
            return false
        }
    }

    @discardableResult
    public func deleteKnowledgeBase(_ knowledgeBase: KnowledgeBase) async -> Bool {
        guard let store, isConnected else {
            return false
        }

        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            let recycledIDs = try await store.deleteKnowledgeBase(id: knowledgeBase.id)
            let collection: WorkspaceCollection = switch selectedCollection {
            case .knowledgeBase(knowledgeBase.id):
                .all
            case let .folder(knowledgeBaseID, _) where knowledgeBaseID == knowledgeBase.id:
                .all
            default:
                selectedCollection
            }
            let succeeded = await refreshIndex(
                preferredCollection: collection,
                preferredSelection: []
            )
            if succeeded {
                actionNotice = recycledIDs.isEmpty
                    ? "已删除知识库“\(knowledgeBase.name)”"
                    : "已删除知识库“\(knowledgeBase.name)”，\(recycledIDs.count) 篇材料移入回收站"
            }
            return succeeded
        } catch {
            present(error)
            return false
        }
    }

    @discardableResult
    public func deleteFolder(_ folder: KnowledgeFolder) async -> Bool {
        guard let store, isConnected else {
            return false
        }

        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            let recycledIDs = try await store.deleteFolder(
                at: folder.path,
                in: folder.knowledgeBaseID
            )
            let parentPath = folder.parentPath
            let collection = collectionReferencing(
                folder.path,
                knowledgeBaseID: folder.knowledgeBaseID,
                in: selectedCollection
            )
                ? parentPath.isEmpty
                    ? .knowledgeBase(folder.knowledgeBaseID)
                    : .folder(
                        knowledgeBaseID: folder.knowledgeBaseID,
                        path: parentPath
                    )
                : selectedCollection
            let succeeded = await refreshIndex(
                preferredCollection: collection,
                preferredSelection: []
            )
            if succeeded {
                actionNotice = recycledIDs.isEmpty
                    ? "已删除文件夹“\(folder.name)”"
                    : "已删除文件夹“\(folder.name)”，\(recycledIDs.count) 篇材料移入回收站"
            }
            return succeeded
        } catch {
            present(error)
            return false
        }
    }

    @discardableResult
    public func createMarkdownNote(
        title: String,
        markdown: String,
        in knowledgeBaseID: UUID,
        folderPath: String,
        tags: [String]
    ) async -> Bool {
        guard let store, isConnected else {
            return false
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return false
        }

        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            let note = try await store.createMarkdownNote(
                title: trimmedTitle,
                in: knowledgeBaseID,
                markdown: markdown,
                folderPath: folderPath,
                tags: tags
            )
            let collection: WorkspaceCollection = folderPath.isEmpty
                ? .knowledgeBase(knowledgeBaseID)
                : .folder(knowledgeBaseID: knowledgeBaseID, path: folderPath)
            let succeeded = await refreshIndex(
                preferredCollection: collection,
                preferredSelection: [note.summary.id]
            )
            if succeeded {
                expandDirectoryAncestors(
                    of: folderPath,
                    in: knowledgeBaseID
                )
                selectedNote = note
                isShowingCreateNote = false
                createNoteTarget = nil
                actionNotice = "已创建笔记“\(note.summary.title)”"
                beginMarkdownEditing()
            }
            return succeeded
        } catch {
            present(error)
            return false
        }
    }

    @discardableResult
    public func createInboxMarkdownNote(
        title: String,
        markdown: String,
        tags: [String]
    ) async -> Bool {
        guard let store, isConnected else {
            return false
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return false
        }

        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            let note = try await store.createInboxMarkdownNote(
                title: trimmedTitle,
                markdown: markdown,
                tags: tags
            )
            let succeeded = await refreshIndex(
                preferredCollection: .inbox,
                preferredSelection: [note.summary.id]
            )
            if succeeded {
                selectedNote = note
                isShowingCreateNote = false
                createNoteTarget = nil
                actionNotice = "已创建收件箱笔记“\(note.summary.title)”"
                beginMarkdownEditing()
            }
            return succeeded
        } catch {
            present(error)
            return false
        }
    }

    @discardableResult
    public func moveSelectedMaterials(
        toKnowledgeBaseID knowledgeBaseID: UUID,
        folderPath: String
    ) async -> Bool {
        guard canMoveSelection else {
            return false
        }
        let succeeded = await moveMaterials(
            ids: selectedMaterialIDs,
            toKnowledgeBaseID: knowledgeBaseID,
            folderPath: folderPath
        )
        if succeeded {
            isShowingMoveMaterials = false
        }
        return succeeded
    }

    @discardableResult
    public func moveMaterials(
        ids: Set<UUID>,
        toKnowledgeBaseID knowledgeBaseID: UUID,
        folderPath: String
    ) async -> Bool {
        guard let store, isConnected, !ids.isEmpty else {
            return false
        }
        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            let movedIDs = try await store.moveMaterials(
                ids: Array(ids),
                toKnowledgeBaseID: knowledgeBaseID,
                folderPath: folderPath
            )
            let succeeded = await refreshIndex(
                preferredCollection: selectedCollection,
                preferredSelection: Set(movedIDs)
            )
            if succeeded {
                actionNotice = "已移动 \(movedIDs.count) 篇材料"
            }
            return succeeded
        } catch {
            present(error)
            return false
        }
    }

    @discardableResult
    public func applyTagMutation(
        _ tags: [String],
        mode: WorkspaceTagMutationMode
    ) async -> Bool {
        guard let store, isConnected, canEditSelectionTags else {
            return false
        }

        let ids = Array(selectedMaterialIDs)
        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            switch mode {
            case .add:
                _ = try await store.addTags(tags, toMaterialIDs: ids)
            case .remove:
                _ = try await store.removeTags(tags, fromMaterialIDs: ids)
            case .replace:
                _ = try await store.setTags(tags, onMaterialIDs: ids)
            }
            let succeeded = await refreshIndex(
                preferredCollection: selectedCollection,
                preferredSelection: Set(ids)
            )
            if succeeded {
                isShowingEditTags = false
                actionNotice = tagMutationNotice(
                    mode: mode,
                    tagCount: tags.count,
                    materialCount: ids.count
                )
            }
            return succeeded
        } catch {
            present(error)
            return false
        }
    }

    @discardableResult
    public func moveSelectedMaterialsToRecycleBin() async -> Bool {
        guard let store, isConnected, canRecycleSelection else {
            return false
        }

        let ids = Array(selectedMaterialIDs)
        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            let recycledIDs = try await store.moveMaterialsToRecycleBin(ids: ids)
            let succeeded = await refreshIndex(
                preferredCollection: selectedCollection,
                preferredSelection: []
            )
            isConfirmingRecycle = false
            if succeeded {
                actionNotice = "已将 \(recycledIDs.count) 篇材料移入回收站"
            }
            return succeeded
        } catch {
            present(error)
            return false
        }
    }

    @discardableResult
    public func restoreSelectedMaterials() async -> Bool {
        guard let store, isConnected, canRestoreSelection else {
            return false
        }

        let ids = Array(selectedMaterialIDs)
        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            let restoredIDs = try await store.restoreMaterials(ids: ids)
            let succeeded = await refreshIndex(
                preferredCollection: selectedCollection,
                preferredSelection: []
            )
            if succeeded {
                actionNotice = "已恢复 \(restoredIDs.count) 篇材料"
            }
            return succeeded
        } catch {
            present(error)
            return false
        }
    }

    @discardableResult
    public func purgeExpiredRecycleBin() async -> Bool {
        guard let store, isConnected, hasExpiredRecycleItems else {
            return false
        }

        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            let purgedIDs = try await store.purgeExpiredRecycleBin()
            let succeeded = await refreshIndex(
                preferredCollection: .recycleBin,
                preferredSelection: []
            )
            isConfirmingPurgeExpired = false
            if succeeded {
                actionNotice = "已清理 \(purgedIDs.count) 篇过期材料"
            }
            return succeeded
        } catch {
            present(error)
            return false
        }
    }

    public func dismissError() {
        errorMessage = nil
    }

    public func dismissActionNotice() {
        actionNotice = nil
    }

    public var defaultImportKnowledgeBaseID: UUID? {
        switch selectedCollection {
        case .inbox:
            nil
        case let .knowledgeBase(id), let .folder(id, _):
            id
        case .all, .recycleBin, .tag:
            knowledgeBases.first?.id
        }
    }

    public var defaultImportFolderPath: String {
        selectedFolderPath ?? ""
    }

    public func presentImportSheet(webArticle: Bool = false) {
        guard isConnected else {
            return
        }
        importTarget = WorkspaceDestination(
            knowledgeBaseID: defaultImportKnowledgeBaseID,
            folderPath: defaultImportFolderPath
        )
        if webArticle {
            isShowingWebImport = true
        } else {
            isShowingImport = true
        }
    }

    public func presentImportSheet(
        in knowledgeBaseID: UUID,
        folderPath: String,
        webArticle: Bool = false
    ) {
        guard isConnected else {
            return
        }
        importTarget = WorkspaceDestination(
            knowledgeBaseID: knowledgeBaseID,
            folderPath: folderPath
        )
        if webArticle {
            isShowingWebImport = true
        } else {
            isShowingImport = true
        }
    }

    public func importFiles(
        _ urls: [URL],
        knowledgeBaseID: UUID?,
        folderPath: String,
        tags: [String]
    ) async -> Bool {
        guard let store, isConnected, !urls.isEmpty else {
            return false
        }
        isPerformingAction = true
        defer { isPerformingAction = false }
        let accessingURLs = urls.filter { $0.startAccessingSecurityScopedResource() }
        defer {
            accessingURLs.forEach { $0.stopAccessingSecurityScopedResource() }
        }
        do {
            let batch = try await store.importFiles(
                at: urls,
                knowledgeBaseID: knowledgeBaseID,
                folderPath: folderPath,
                tags: tags
            )
            let preferredID = batch.results.first { !$0.isDuplicate }?.summary.id
            let collection: WorkspaceCollection
            if let knowledgeBaseID {
                collection = folderPath.isEmpty
                    ? .knowledgeBase(knowledgeBaseID)
                    : .folder(knowledgeBaseID: knowledgeBaseID, path: folderPath)
            } else {
                collection = .inbox
            }
            let succeeded = await refreshIndex(
                preferredCollection: collection,
                preferredSelection: preferredID.map { Set([$0]) } ?? []
            )
            if succeeded {
                if let knowledgeBaseID {
                    expandDirectoryAncestors(
                        of: folderPath,
                        in: knowledgeBaseID
                    )
                }
                isShowingImport = false
                importTarget = nil
                let mediaFailureCount = batch.results.reduce(0) {
                    $0 + $1.mediaFailures.count
                }
                var notice = "导入 \(batch.importedCount) 份材料"
                if batch.duplicateCount > 0 {
                    notice += "，跳过 \(batch.duplicateCount) 份重复内容"
                }
                if mediaFailureCount > 0 {
                    notice += "，\(mediaFailureCount) 张图片下载失败"
                }
                actionNotice = notice
            }
            return succeeded
        } catch {
            present(error)
            return false
        }
    }

    public func fetchWebArticle() async {
        guard let url = URL(
            string: webArticleURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        ), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            errorMessage = "请输入完整的 http 或 https 网页地址。"
            return
        }
        guard !isFetchingWebArticle else {
            return
        }
        isFetchingWebArticle = true
        webArticleDraft = nil
        webArticleMarkdown = ""
        webArticleStatus = "准备抓取"
        defer { isFetchingWebArticle = false }
        do {
            let draft = try await webArticleFetcher.fetch(url: url) { [weak self] message in
                await MainActor.run {
                    self?.webArticleStatus = message
                }
            }
            webArticleDraft = draft
            webArticleMarkdown = draft.markdown
            webArticleStatus = draft.mediaFailures.isEmpty
                ? "已提取正文和 \(draft.media.count) 张图片"
                : "已提取正文；\(draft.mediaFailures.count) 张图片失败，可重试"
        } catch {
            webArticleStatus = ""
            present(error)
        }
    }

    public func importFetchedWebArticle(
        title: String,
        markdown: String,
        knowledgeBaseID: UUID?,
        folderPath: String,
        tags: [String]
    ) async -> Bool {
        guard let store, let draft = webArticleDraft, !markdown.isEmpty else {
            return false
        }
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            let result = try await store.importWebArticle(
                draft,
                title: title,
                markdown: markdown,
                knowledgeBaseID: knowledgeBaseID,
                folderPath: folderPath,
                tags: tags
            )
            let collection: WorkspaceCollection
            if let knowledgeBaseID {
                collection = folderPath.isEmpty
                    ? .knowledgeBase(knowledgeBaseID)
                    : .folder(knowledgeBaseID: knowledgeBaseID, path: folderPath)
            } else {
                collection = .inbox
            }
            let succeeded = await refreshIndex(
                preferredCollection: collection,
                preferredSelection: result.isDuplicate ? [] : [result.summary.id]
            )
            if succeeded {
                if let knowledgeBaseID {
                    expandDirectoryAncestors(
                        of: folderPath,
                        in: knowledgeBaseID
                    )
                }
                isShowingWebImport = false
                importTarget = nil
                webArticleDraft = nil
                actionNotice = result.isDuplicate
                    ? "网页内容已在资料库中，未创建重复材料"
                    : "已导入网页文章；正文和本地图片可离线阅读"
            }
            return succeeded
        } catch {
            present(error)
            return false
        }
    }

    public func updateReaderSelection(_ selection: ReaderSelection?) {
        readerSelection = selection
    }

    public func presentAnnotationEditor(for selection: ReaderSelection) {
        guard let document = selectedDocument,
              !selection.quote.isEmpty
                || selection.rect != nil
                || selection.pageIndex != nil else {
            return
        }
        annotationDraftRequest = AnnotationDraftRequest(
            materialID: document.summary.id,
            quote: selection.quote,
            anchor: selection.anchor
        )
    }

    public func presentAnnotationEditor(for annotation: MaterialAnnotation) {
        annotationDraftRequest = AnnotationDraftRequest(
            materialID: annotation.materialID,
            annotationID: annotation.id,
            quote: annotation.quote,
            anchor: annotation.anchor,
            initialNote: annotation.note
        )
    }

    public func presentAnnotationForCurrentSelection() {
        guard let readerSelection else {
            return
        }
        presentAnnotationEditor(for: readerSelection)
    }

    public func saveAnnotation(note: String) async -> Bool {
        guard let store, let request = annotationDraftRequest else {
            return false
        }
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            let saved = try await store.upsertAnnotation(
                MaterialAnnotation(
                    id: request.annotationID ?? UUID(),
                    materialID: request.materialID,
                    anchor: request.anchor,
                    quote: request.quote,
                    note: note.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
            annotations = try await store.loadAnnotations(materialID: request.materialID)
            annotationDraftRequest = nil
            annotationJumpID = saved.id
            isStudyPanelVisible = true
            studyPanelTab = .annotations
            actionNotice = request.annotationID == nil ? "已创建标注" : "已更新标注"
            return true
        } catch {
            present(error)
            return false
        }
    }

    public func deleteAnnotation(_ annotation: MaterialAnnotation) async {
        guard let store else {
            return
        }
        do {
            try await store.deleteAnnotation(
                id: annotation.id,
                materialID: annotation.materialID
            )
            annotations = try await store.loadAnnotations(materialID: annotation.materialID)
            if annotationJumpID == annotation.id {
                annotationJumpID = nil
            }
            actionNotice = "已删除标注，正文未改变"
        } catch {
            present(error)
        }
    }

    public func rebind(_ annotation: MaterialAnnotation) async {
        guard let store, let selection = readerSelection else {
            return
        }
        do {
            _ = try await store.rebindAnnotation(
                id: annotation.id,
                materialID: annotation.materialID,
                anchor: selection.anchor
            )
            annotations = try await store.loadAnnotations(materialID: annotation.materialID)
            actionNotice = "已重新绑定标注位置"
        } catch {
            present(error)
        }
    }

    public var isEditingMarkdown: Bool {
        markdownEditorSession != nil
    }

    public func beginMarkdownEditing() {
        guard let document = selectedDocument,
              document.summary.kind == .note
                || document.summary.kind == .markdown else {
            return
        }
        if markdownEditorSession?.materialID == document.id {
            return
        }
        let decoded = try? MarkdownEditorCodec().decode(document.markdown)
        markdownEditorSession = MarkdownEditorSession(
            snapshot: MarkdownEditorSnapshot(
                materialID: document.id,
                title: document.summary.title,
                markdown: document.markdown,
                fingerprint: ContentFingerprint.sha256(document.markdown),
                compatibilityBlocks: decoded?.compatibilityBlocks ?? []
            )
        ) { [weak self] request in
            guard let self else {
                return .failed(reason: "编辑器所属工作区已关闭。")
            }
            return await self.persistMarkdownEditor(request)
        }
    }

    @discardableResult
    public func finishMarkdownEditing() async -> Bool {
        guard let session = markdownEditorSession else {
            return true
        }
        await session.endEditing()
        if session.saveState.status == .saved,
           session.titleConflict == nil,
           session.errorMessage == nil {
            markdownEditorSession = nil
            return true
        }
        errorMessage = session.errorMessage ?? "当前编辑内容尚未保存。"
        return false
    }

    public func toggleMarkdownEditing() async {
        if isEditingMarkdown {
            _ = await finishMarkdownEditing()
        } else {
            beginMarkdownEditing()
        }
    }

    public func flushMarkdownEditor(_ reason: MarkdownFlushReason) async {
        guard let markdownEditorSession else {
            return
        }
        await markdownEditorSession.flush(reason)
    }

    public func resolveMarkdownTitleConflict(
        usingManifestTitle: Bool
    ) async {
        await markdownEditorSession?.resolveTitleConflict(
            usingManifestTitle: usingManifestTitle
        )
    }

    public func reloadMarkdownEditorFromDisk() async {
        guard let store, let current = markdownEditorSession else {
            return
        }
        do {
            let document = try await store.loadMaterialDocument(
                id: current.materialID
            )
            let decoded = try MarkdownEditorCodec().decode(document.markdown)
            current.replaceSnapshot(
                MarkdownEditorSnapshot(
                    materialID: document.id,
                    title: document.summary.title,
                    markdown: document.markdown,
                    fingerprint: ContentFingerprint.sha256(document.markdown),
                    compatibilityBlocks: decoded.compatibilityBlocks
                )
            )
            selectedDocument = document
            selectedNote = document.summary.kind == .note
                ? MarkdownNote(
                    summary: document.summary,
                    markdown: document.markdown
                )
                : nil
        } catch {
            present(error)
        }
    }

    public func keepLocalMarkdownVersion() async {
        await markdownEditorSession?.overrideConflictAndSave()
    }

    public func prepareEditorAction(
        _ action: MarkdownEditorAction
    ) async -> Bool {
        guard let markdownEditorSession else {
            return true
        }
        switch await markdownEditorSession.prepareForAction(action) {
        case .allowed:
            return true
        case let .blocked(reason):
            errorMessage = reason
            return false
        }
    }

    public func saveReaderCopy(_ text: String) async -> Bool {
        guard let store, let document = selectedDocument else {
            return false
        }
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            _ = try await store.saveReaderCopy(id: document.summary.id, text: text)
            let updated = try await store.loadMaterialDocument(id: document.summary.id)
            selectedDocument = await resolvedMediaDocument(updated)
            selectedNote = updated.summary.kind == .note
                ? MarkdownNote(summary: updated.summary, markdown: updated.markdown)
                : nil
            revisions = try await store.loadTextRevisions(id: document.summary.id)
            isShowingEditReaderCopy = false
            actionNotice = "已保存阅读副本并保留最近的文字版本"
            await reloadIndexPreservingSelection()
            return true
        } catch {
            present(error)
            return false
        }
    }

    private func persistMarkdownEditor(
        _ request: MarkdownEditorSaveRequest
    ) async -> MarkdownEditorSaveResult {
        guard let store else {
            return .failed(reason: "学习目录尚未连接。")
        }
        do {
            let current = try await store.loadMaterialDocument(
                id: request.materialID
            )
            let currentFingerprint = ContentFingerprint.sha256(current.markdown)
            guard currentFingerprint == request.expectedFingerprint else {
                return .conflict(currentFingerprint: currentFingerprint)
            }
            _ = try await store.saveReaderCopy(
                id: request.materialID,
                text: request.markdown,
                title: request.title,
                createRecoveryVersion: request.createRecoveryVersion
            )
            let updated = try await store.loadMaterialDocument(
                id: request.materialID
            )
            selectedDocument = await resolvedMediaDocument(updated)
            selectedNote = updated.summary.kind == .note
                ? MarkdownNote(
                    summary: updated.summary,
                    markdown: updated.markdown
                )
                : nil
            annotations = try await store.loadAnnotations(
                materialID: request.materialID
            )
            revisions = try await store.loadTextRevisions(
                id: request.materialID
            )
            await reloadIndexPreservingSelection()
            actionNotice = request.createRecoveryVersion
                ? "已保存并创建可恢复版本"
                : "已保存"
            return .saved(
                title: request.title,
                markdown: updated.markdown,
                fingerprint: ContentFingerprint.sha256(updated.markdown)
            )
        } catch {
            return .failed(reason: error.localizedDescription)
        }
    }

    private func flushMarkdownEditorBeforeSelectionChange() async -> Bool {
        guard let markdownEditorSession else {
            return true
        }
        await markdownEditorSession.flush(.materialSwitch)
        guard markdownEditorSession.saveState.status == .saved,
              markdownEditorSession.titleConflict == nil,
              markdownEditorSession.errorMessage == nil else {
            errorMessage = markdownEditorSession.errorMessage
                ?? "切换材料前无法保存当前编辑内容。"
            return false
        }
        self.markdownEditorSession = nil
        return true
    }

    public func loadRevisions() async {
        guard let store, let document = selectedDocument else {
            return
        }
        guard await prepareEditorAction(.versions) else {
            return
        }
        do {
            revisions = try await store.loadTextRevisions(id: document.summary.id)
        } catch {
            present(error)
        }
    }

    public func restoreRevision(_ revision: TextRevision) async {
        guard let store, let document = selectedDocument else {
            return
        }
        do {
            _ = try await store.restoreRevision(
                id: document.summary.id,
                revisionID: revision.id
            )
            let updated = try await store.loadMaterialDocument(id: document.summary.id)
            selectedDocument = updated
            selectedNote = updated.summary.kind == .note
                ? MarkdownNote(summary: updated.summary, markdown: updated.markdown)
                : nil
            revisions = try await store.loadTextRevisions(id: document.summary.id)
            isShowingVersions = false
            actionNotice = "已恢复文字版本，并生成新的当前版本"
        } catch {
            present(error)
        }
    }

    public func setLinkedMaterials(_ ids: Set<UUID>) async {
        guard let store, let document = selectedDocument else {
            return
        }
        do {
            _ = try await store.setLinkedMaterials(
                for: document.summary.id,
                linkedMaterialIDs: Array(ids)
            )
            isShowingLinkMaterials = false
            await reloadIndexPreservingSelection()
            actionNotice = ids.isEmpty ? "已清除材料关联" : "已关联 \(ids.count) 份学习材料"
        } catch {
            present(error)
        }
    }

    public func saveProviderProfile(
        id: UUID?,
        name: String,
        baseURLText: String,
        model: String,
        apiKey: String
    ) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              !trimmedModel.isEmpty,
              let baseURL = URL(
                  string: baseURLText.trimmingCharacters(in: .whitespacesAndNewlines)
              ),
              ["http", "https"].contains(baseURL.scheme?.lowercased() ?? "") else {
            errorMessage = "请填写供应商名称、有效的 HTTP(S) 基础地址和模型标识。"
            return false
        }
        let profileID = id ?? UUID()
        let existing = providerProfiles.first { $0.id == profileID }
        let account = existing?.keychainAccount ?? "provider-\(profileID.uuidString)"
        do {
            let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedKey.isEmpty {
                try secretStore.save(trimmedKey, account: account)
            } else if existing == nil {
                throw AIStreamError.missingAPIKey
            }
            let profile = AIProviderProfile(
                id: profileID,
                name: trimmedName,
                baseURL: baseURL,
                model: trimmedModel,
                keychainAccount: account
            )
            var updated = providerProfiles.filter { $0.id != profileID }
            updated.append(profile)
            updated.sort {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            providerProfiles = updated
            selectedProviderID = profile.id
            AIProviderSettingsStore.save(updated)
            actionNotice = "已保存 AI 供应商“\(profile.name)”"
            return true
        } catch {
            present(error)
            return false
        }
    }

    public func deleteProviderProfile(_ profile: AIProviderProfile) {
        do {
            try secretStore.delete(account: profile.keychainAccount)
        } catch {
            present(error)
        }
        providerProfiles.removeAll { $0.id == profile.id }
        AIProviderSettingsStore.save(providerProfiles)
        if selectedProviderID == profile.id {
            selectedProviderID = providerProfiles.first?.id
        }
        actionNotice = "已删除 AI 供应商“\(profile.name)”"
    }

    public func hasAPIKey(for profile: AIProviderProfile) -> Bool {
        ((try? secretStore.load(account: profile.keychainAccount)) ?? nil)?.isEmpty == false
    }

    public func prepareSelectionExplanation() {
        Task {
            guard await prepareEditorAction(.aiExplain) else {
                return
            }
            presentSelectionExplanation()
        }
    }

    private func presentSelectionExplanation() {
        guard let selection = readerSelection,
              let document = selectedDocument,
              let profile = selectedProvider else {
            errorMessage = "请先选择一段文字并配置 AI 供应商。"
            return
        }
        let prompt = aiPromptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "请解释这段内容在整篇材料中的含义。"
            : aiPromptText.trimmingCharacters(in: .whitespacesAndNewlines)
        let context = [
            "前文：\(selection.prefix)",
            "选段：\(selection.quote)",
            "后文：\(selection.suffix)"
        ].joined(separator: "\n")
        pendingAIContext = AIContextPreview(
            profile: profile,
            prompt: prompt,
            context: context,
            origin: .selection,
            anchor: selection.anchor
        )
        isStudyPanelVisible = true
        studyPanelTab = .ai
        _ = document
    }

    public func prepareMaterialSummary() {
        Task {
            guard await prepareEditorAction(.aiSummarize) else {
                return
            }
            presentMaterialSummary()
        }
    }

    private func presentMaterialSummary() {
        guard let document = selectedDocument,
              let profile = selectedProvider else {
            errorMessage = "请先配置并选择 AI 供应商。"
            return
        }
        let prompt = aiPromptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "请总结这份学习材料的结构、核心观点和可继续追问的问题。"
            : aiPromptText.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingAIContext = AIContextPreview(
            profile: profile,
            prompt: prompt,
            context: document.markdown,
            origin: .summary,
            anchor: nil
        )
        isStudyPanelVisible = true
        studyPanelTab = .ai
    }

    public func prepareSectionSummary(heading: ReaderHeading) {
        Task {
            guard await prepareEditorAction(.aiSummarize) else {
                return
            }
            presentSectionSummary(heading: heading)
        }
    }

    private func presentSectionSummary(heading: ReaderHeading) {
        guard let document = selectedDocument,
              let profile = selectedProvider else {
            errorMessage = "请先配置并选择 AI 供应商。"
            return
        }
        let lines = document.markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        var startIndex: Int?
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let hashes = trimmed.prefix { $0 == "#" }
            let title = trimmed.dropFirst(hashes.count)
                .trimmingCharacters(in: .whitespaces)
            if hashes.count == heading.level, title == heading.title {
                startIndex = index
                break
            }
        }
        guard let startIndex else {
            prepareMaterialSummary()
            return
        }
        var endIndex = lines.count
        if startIndex + 1 < lines.count {
            for index in (startIndex + 1)..<lines.count {
                let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
                let hashes = trimmed.prefix { $0 == "#" }
                if !hashes.isEmpty, hashes.count <= heading.level {
                    endIndex = index
                    break
                }
            }
        }
        let context = lines[startIndex..<endIndex].joined(separator: "\n")
        pendingAIContext = AIContextPreview(
            profile: profile,
            prompt: "请总结“\(heading.title)”这一节的结构、核心观点和可继续追问的问题。",
            context: context,
            origin: .summary,
            anchor: nil
        )
        isStudyPanelVisible = true
        studyPanelTab = .ai
    }

    public func confirmAIContext() {
        guard let preview = pendingAIContext else {
            return
        }
        guard let apiKey = try? secretStore.load(account: preview.profile.keychainAccount),
              !apiKey.isEmpty else {
            pendingAIContext = nil
            present(AIStreamError.missingAPIKey)
            return
        }
        pendingAIContext = nil
        startAIRequest(preview: preview, apiKey: apiKey)
    }

    public func cancelAIContext() {
        pendingAIContext = nil
    }

    public func stopAIStream() {
        guard aiPhase.isStreaming else {
            return
        }
        aiStopRequested = true
        aiTask?.cancel()
        aiTask = nil
        persistStreamingResponse(includeStoppedMarker: true)
        aiPhase = .stopped
    }

    public func retryActiveAIRequest() {
        guard case .failed = aiPhase,
              let conversation = activeConversation else {
            return
        }
        guard let profile = providerProfiles.first(where: {
            $0.name == conversation.providerName && $0.model == conversation.model
        }) ?? selectedProvider else {
            errorMessage = "找不到这个会话使用的 AI 供应商。"
            return
        }
        guard let apiKey = try? secretStore.load(account: profile.keychainAccount),
              !apiKey.isEmpty else {
            present(AIStreamError.missingAPIKey)
            return
        }

        runAIStream(
            conversationID: conversation.id,
            profile: profile,
            apiKey: apiKey,
            messages: requestMessages(for: conversation)
        )
    }

    public func continueAIConversation(prompt: String) {
        guard let conversation = activeConversation else {
            return
        }
        guard let profile = providerProfiles.first(where: {
            $0.name == conversation.providerName && $0.model == conversation.model
        }) ?? selectedProvider else {
            errorMessage = "找不到这个会话使用的 AI 供应商。"
            return
        }
        guard let apiKey = try? secretStore.load(account: profile.keychainAccount),
              !apiKey.isEmpty else {
            present(AIStreamError.missingAPIKey)
            return
        }
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            return
        }
        var updated = conversation
        updated.messages.append(AIMessage(role: .user, content: trimmedPrompt))
        conversations.removeAll { $0.id == updated.id }
        conversations.insert(updated, at: 0)
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            if let store,
               let saved = try? await store.saveConversation(updated) {
                replaceConversation(saved)
            }
            runAIStream(
                conversationID: conversation.id,
                profile: profile,
                apiKey: apiKey,
                messages: requestMessages(for: updated)
            )
        }
    }

    public func renameConversation(_ conversation: AIConversation, title: String) async {
        guard let store else {
            return
        }
        var updated = conversation
        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !updated.title.isEmpty else {
            return
        }
        do {
            let saved = try await store.saveConversation(updated)
            replaceConversation(saved)
            actionNotice = "已重命名 AI 研读会话"
        } catch {
            present(error)
        }
    }

    public func deleteConversation(_ conversation: AIConversation) async {
        guard let store else {
            return
        }
        do {
            try await store.deleteConversation(
                id: conversation.id,
                materialID: conversation.materialID
            )
            conversations.removeAll { $0.id == conversation.id }
            if activeConversationID == conversation.id {
                activeConversationID = conversations.first?.id
            }
            actionNotice = "已删除 AI 研读会话，原文与标注未受影响"
        } catch {
            present(error)
        }
    }

    public func promoteConversationMessage(
        _ conversation: AIConversation,
        message: AIMessage,
        target: AIPromotionTarget
    ) async {
        guard let store,
              let knowledgeBaseID = selectedDocument?.summary.knowledgeBaseID
                ?? knowledgeBases.first?.id else {
            return
        }
        do {
            let result = try await store.promoteAIResult(
                conversationID: conversation.id,
                messageID: message.id,
                materialID: conversation.materialID,
                target: target,
                knowledgeBaseID: knowledgeBaseID
            )
            if target == .annotation {
                annotations = try await store.loadAnnotations(
                    materialID: conversation.materialID
                )
            } else {
                _ = await refreshIndex(
                    preferredCollection: result.material.knowledgeBaseID.map {
                        WorkspaceCollection.knowledgeBase($0)
                    } ?? .inbox,
                    preferredSelection: [result.material.id]
                )
            }
            actionNotice = target == .annotation
                ? "已把 AI 结果提升为标注"
                : "已提升“\(result.material.title)”"
        } catch {
            present(error)
        }
    }

    public func preparePublishPreview() {
        guard canPreviewPublish, let document = selectedDocument else {
            return
        }
        let settings = appSettings
        publishIncludeAnnotations = settings.publishAnnotationsByDefault
        publishIncludeAI = settings.publishAIByDefault
        Task {
            guard await prepareEditorAction(.publishPreview) else {
                return
            }
            let markdown = markdownEditorSession?.markdown
                ?? document.markdown
            if let mediaCoordinator {
                let currentKeys = NoteMediaReferenceScanner.objectKeys(
                    in: markdown
                )
                if !currentKeys.isEmpty {
                    do {
                        let historicalRevisions = try await store?.loadTextRevisions(
                            id: document.id
                        ) ?? revisions
                        let scan = try await mediaCoordinator.scan(
                            sourceId: document.id.uuidString,
                            currentMarkdown: markdown,
                            historicalMarkdowns:
                                historicalRevisions.map(\.text)
                        )
                        let blocked = scan.media.filter {
                            currentKeys.contains($0.objectKey)
                                && $0.status != .ready
                        }
                        if !blocked.isEmpty {
                            errorMessage =
                                "正文仍有 \(blocked.count) 个媒体未上传或不可用，全部就绪前不能发布。"
                            return
                        }
                    } catch {
                        errorMessage =
                            "无法验证正文媒体状态，发布已阻断：\(error.localizedDescription)"
                        return
                    }
                }
            }
            await refreshPublishPreview()
            isShowingPublishPreview = true
        }
    }

    public func refreshPublishPreview() async {
        guard let store, let document = selectedDocument else {
            return
        }
        do {
            publishPreview = try await store.publishPreview(
                materialID: document.summary.id,
                includeAnnotations: publishIncludeAnnotations,
                includeAI: publishIncludeAI
            )
        } catch {
            present(error)
        }
    }

    public func saveLocalPublishMapping(
        articleID: String,
        publicURLText: String,
        version: String,
        visibility: PublishVisibility,
        contentFingerprint: String? = nil
    ) async -> Bool {
        guard let store, let preview = publishPreview,
              let publicURL = URL(
                  string: publicURLText.trimmingCharacters(in: .whitespacesAndNewlines)
              ),
              !articleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "请填写文章标识和有效的公开地址。"
            return false
        }
        do {
            _ = try await store.savePublishMapping(
                materialID: preview.materialID,
                mapping: PublishMapping(
                    articleID: articleID,
                    publicURL: publicURL,
                    lastPublishedVersion: version.isEmpty ? nil : version,
                    visibility: visibility,
                    contentFingerprint: contentFingerprint
                        ?? preview.contentFingerprint,
                    updatedAt: Date()
                )
            )
            await reloadIndexPreservingSelection()
            await refreshPublishPreview()
            actionNotice = "已保存轻量本地发布映射"
            return true
        } catch {
            present(error)
            return false
        }
    }

    public func clearLocalPublishMapping() async {
        guard let store, let preview = publishPreview else {
            return
        }
        do {
            _ = try await store.clearPublishMapping(
                materialID: preview.materialID
            )
            await reloadIndexPreservingSelection()
            await refreshPublishPreview()
            actionNotice = "已清除本地轻量发布映射"
        } catch {
            present(error)
        }
    }

    private func reloadIndexPreservingSelection() async {
        _ = await refreshIndex(
            preferredCollection: selectedCollection,
            preferredSelection: selectedMaterialIDs,
            autoSelectFirst: false
        )
    }

    private func startAIRequest(preview: AIContextPreview, apiKey: String) {
        guard let document = selectedDocument else {
            return
        }
        let title = preview.origin == .summary
            ? "整篇总结"
            : String(preview.prompt.prefix(28))
        let messages = [
            AIMessage(role: .user, content: "\(preview.prompt)\n\n发送上下文：\n\(preview.context)")
        ]
        let conversation = AIConversation(
            materialID: document.summary.id,
            title: title.isEmpty ? "AI 研读" : title,
            origin: preview.origin,
            originAnchor: preview.anchor,
            messages: messages,
            providerName: preview.profile.name,
            model: preview.profile.model
        )
        conversations.removeAll { $0.id == conversation.id }
        conversations.insert(conversation, at: 0)
        activeConversationID = conversation.id
        Task {
            if let store,
               let saved = try? await store.saveConversation(conversation) {
                replaceConversation(saved)
            }
            runAIStream(
                conversationID: conversation.id,
                profile: preview.profile,
                apiKey: apiKey,
                messages: [
                    AIMessage(
                        role: .system,
                        content: "你是学习研读助手。只解释或总结用户明确发送的材料，不推测未发送内容。"
                    )
                ] + messages
            )
        }
    }

    private func runAIStream(
        conversationID: UUID,
        profile: AIProviderProfile,
        apiKey: String,
        messages: [AIMessage]
    ) {
        aiTask?.cancel()
        aiStopRequested = false
        aiStreamingText = ""
        aiPhase = .streaming
        activeConversationID = conversationID
        aiTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                for try await event in aiClient.stream(
                    profile: profile,
                    apiKey: apiKey,
                    messages: messages
                ) {
                    guard !aiStopRequested else {
                        return
                    }
                    switch event {
                    case let .delta(delta):
                        aiStreamingText += delta
                    case .completed:
                        break
                    }
                }
                guard !aiStopRequested else {
                    return
                }
                persistStreamingResponse(includeStoppedMarker: false)
                aiPhase = .idle
                aiTask = nil
            } catch is CancellationError {
                if !aiStopRequested {
                    aiPhase = .stopped
                }
            } catch {
                aiPhase = .failed(error.localizedDescription)
                aiTask = nil
            }
        }
    }

    private func requestMessages(for conversation: AIConversation) -> [AIMessage] {
        [
            AIMessage(
                role: .system,
                content: "继续同一学习研读会话。保持已有上下文，不自动切换到其他供应商。"
            )
        ] + conversation.messages
    }

    private func persistStreamingResponse(includeStoppedMarker: Bool) {
        guard let activeConversationID,
              let index = conversations.firstIndex(where: { $0.id == activeConversationID }) else {
            return
        }
        var content = aiStreamingText
        if includeStoppedMarker, !content.isEmpty {
            content += "\n\n（已由用户停止生成）"
        }
        guard !content.isEmpty else {
            return
        }
        var conversation = conversations[index]
        conversation.messages.append(AIMessage(role: .assistant, content: content))
        conversations[index] = conversation
        if let store {
            Task {
                if let saved = try? await store.saveConversation(conversation) {
                    replaceConversation(saved)
                }
            }
        }
    }

    private func replaceConversation(_ conversation: AIConversation) {
        conversations.removeAll { $0.id == conversation.id }
        conversations.insert(conversation, at: 0)
    }

    private func loadWorkspace(at location: WorkspaceLocation) async {
        invalidateNoteLoad()
        refreshGeneration += 1
        let generation = refreshGeneration
        isLoadingIndex = true
        connectionState = .connecting
        defer {
            if refreshGeneration == generation {
                isLoadingIndex = false
            }
        }

        do {
            let storageStatus: StudyNotesRootStatus = switch location.storageKind {
            case .iCloud:
                .available(.iCloud(location.url))
            case .local:
                .available(.local(location.url))
            }
            let newStore = StudyNotesStore(
                rootProvider: FixedStudyNotesRootProvider(status: storageStatus)
            )
            let index = try await newStore.loadIndex()
            guard refreshGeneration == generation else {
                return
            }
            store = newStore
            selectedCollection = .all
            selectedMaterialIDs = []
            readingMaterialID = nil
            treeSelectionAnchorID = nil
            selectedNote = nil
            apply(index: index)
            connectionState = .connected(location)
            await selectFirstMaterialIfAvailable()
        } catch {
            guard refreshGeneration == generation else {
                return
            }
            store = nil
            clearIndex()
            connectionState = .failed(error.localizedDescription)
        }
    }

    @discardableResult
    private func refreshIndex(
        preferredCollection: WorkspaceCollection?,
        preferredSelection: Set<UUID>,
        autoSelectFirst: Bool = true
    ) async -> Bool {
        guard let store, case let .connected(location) = connectionState else {
            return false
        }

        refreshGeneration += 1
        let generation = refreshGeneration
        isLoadingIndex = true
        defer {
            if refreshGeneration == generation {
                isLoadingIndex = false
            }
        }

        do {
            let index = try await store.loadIndex()
            guard refreshGeneration == generation else {
                return false
            }
            apply(index: index)
            if let preferredCollection,
               collectionIsAvailable(preferredCollection) {
                selectedCollection = preferredCollection
            }
            settleSelectedCollection()
            connectionState = .connected(location)

            let visibleIDs = Set(filteredMaterials.map(\.id))
            var nextSelection = preferredSelection.intersection(visibleIDs)
            if nextSelection.isEmpty,
               autoSelectFirst,
               let firstMaterial = filteredMaterials.first {
                nextSelection = [firstMaterial.id]
            }
            selectedMaterialIDs = nextSelection
            if !preferredSelection.isEmpty,
               let preferredReadingID = nextSelection.first {
                readingMaterialID = preferredReadingID
                treeSelectionAnchorID = preferredReadingID
            } else if let readingMaterialID,
               allActiveMaterials.contains(where: {
                   $0.id == readingMaterialID
               }) {
                treeSelectionAnchorID = readingMaterialID
            } else {
                readingMaterialID = nextSelection.first
                treeSelectionAnchorID = readingMaterialID
            }
            await updateReaderForSelection()
            return true
        } catch {
            guard refreshGeneration == generation else {
                return false
            }
            present(error)
            return false
        }
    }

    private func apply(index: LibraryIndex) {
        knowledgeBases = index.knowledgeBases
        materials = index.materials
        folders = index.folders
        inboxMaterials = index.inboxMaterials
        recycledMaterials = index.recycledMaterials
        tags = index.tags
        reconcileDirectoryExpansions()
        settleSelectedCollection()

        let visibleIDs = Set(filteredMaterials.map(\.id))
        selectedMaterialIDs.formIntersection(visibleIDs)
        if let readingMaterialID,
           !allActiveMaterials.contains(where: {
               $0.id == readingMaterialID
           }) {
            self.readingMaterialID = nil
            treeSelectionAnchorID = nil
        }
        if let selectedNote,
           !allMaterials.contains(where: { $0.id == selectedNote.summary.id }) {
            invalidateNoteLoad()
            self.selectedNote = nil
            selectedDocument = nil
            annotations = []
            conversations = []
        } else if let selectedDocument,
                  !allMaterials.contains(where: { $0.id == selectedDocument.summary.id }) {
            invalidateNoteLoad()
            self.selectedDocument = nil
            selectedNote = nil
            annotations = []
            conversations = []
        }
    }

    private func clearIndex() {
        knowledgeBases = []
        materials = []
        folders = []
        inboxMaterials = []
        recycledMaterials = []
        tags = []
        selectedCollection = .all
        selectedMaterialIDs = []
        readingMaterialID = nil
        treeSelectionAnchorID = nil
        expandedDirectoryPathsByKnowledgeBase = [:]
        selectedNote = nil
        selectedDocument = nil
        annotations = []
        conversations = []
        searchHits = []
        searchHitsQuery = ""
    }

    private func selectFirstMaterialIfAvailable() async {
        guard let firstMaterial = filteredMaterials.first else {
            selectedNote = nil
            selectedDocument = nil
            return
        }
        selectedMaterialIDs = [firstMaterial.id]
        readingMaterialID = firstMaterial.id
        treeSelectionAnchorID = firstMaterial.id
        await updateReaderForSelection()
    }

    private func updateReaderForSelection() async {
        invalidateNoteLoad()
        noteMediaScan = nil
        noteMediaHistoricalFiles = []

        guard let materialID = readingMaterialID else {
            selectedNote = nil
            selectedDocument = nil
            annotations = []
            conversations = []
            readerSelection = nil
            return
        }

        if selectedDocument?.summary.id == materialID {
            return
        }
        await loadMaterial(id: materialID)
    }

    private func resolvedMediaDocument(
        _ document: MaterialDocument
    ) async -> MaterialDocument {
        guard let mediaCoordinator,
              document.summary.kind.isTextDocument else {
            return document
        }
        let objectKeys = NoteMediaReferenceScanner.objectKeys(
            in: document.markdown
        )
        let remoteURLs = await mediaCoordinator.inlineURLMap(
            for: objectKeys
        )
        guard !remoteURLs.isEmpty else {
            return document
        }
        let mediaURLs = document.mediaURLs.merging(remoteURLs) {
            _, remote in remote
        }
        let content = ReaderContentBuilder.build(
            markdown: document.markdown,
            title: document.summary.title,
            mediaURLs: mediaURLs
        )
        return MaterialDocument(
            summary: document.summary,
            markdown: document.markdown,
            renderedHTML: content.html,
            headings: content.headings,
            sourceURL: document.sourceURL,
            sourceFileURL: document.sourceFileURL,
            mediaURLs: mediaURLs,
            pageCount: document.pageCount,
            hasTextLayer: document.hasTextLayer
        )
    }

    private func loadMaterial(id: UUID) async {
        guard let store else {
            return
        }

        noteLoadGeneration += 1
        let generation = noteLoadGeneration
        isLoadingNote = true
        defer {
            if noteLoadGeneration == generation {
                isLoadingNote = false
            }
        }

        do {
            let loadedDocument = try await store.loadMaterialDocument(id: id)
            let document = await resolvedMediaDocument(loadedDocument)
            let loadedAnnotations = try await store.loadAnnotations(materialID: id)
            let loadedConversations = try await store.loadConversations(materialID: id)
            guard readingMaterialID == id, noteLoadGeneration == generation else {
                return
            }
            selectedDocument = document
            selectedNote = document.summary.kind == .note
                ? MarkdownNote(summary: document.summary, markdown: document.markdown)
                : nil
            annotations = loadedAnnotations
            conversations = loadedConversations
            readerSelection = nil
            activeConversationID = loadedConversations.first?.id
        } catch {
            guard noteLoadGeneration == generation else {
                return
            }
            selectedNote = nil
            selectedDocument = nil
            annotations = []
            conversations = []
            present(error)
        }
    }

    private func settleSelectedCollection() {
        guard !collectionIsAvailable(selectedCollection) else {
            return
        }

        switch selectedCollection {
        case let .folder(knowledgeBaseID, _):
            selectedCollection = knowledgeBases.contains { $0.id == knowledgeBaseID }
                ? .knowledgeBase(knowledgeBaseID)
                : .all
        case .knowledgeBase, .tag:
            selectedCollection = .all
        case .all, .inbox, .recycleBin:
            break
        }
    }

    private func collectionIsAvailable(_ collection: WorkspaceCollection) -> Bool {
        switch collection {
        case .all, .inbox, .recycleBin:
            true
        case let .knowledgeBase(id):
            knowledgeBases.contains { $0.id == id }
        case let .folder(knowledgeBaseID, path):
            knowledgeBases.contains { $0.id == knowledgeBaseID }
                && folders.contains {
                    $0.knowledgeBaseID == knowledgeBaseID && $0.path == path
                }
        case let .tag(tag):
            tags.contains { $0.compare(tag, options: .caseInsensitive) == .orderedSame }
        }
    }

    private func mappedCollection(
        _ collection: WorkspaceCollection,
        knowledgeBaseID: UUID,
        oldPath: String,
        newPath: String
    ) -> WorkspaceCollection {
        guard case let .folder(collectionKnowledgeBaseID, path) = collection,
              collectionKnowledgeBaseID == knowledgeBaseID else {
            return collection
        }

        if path == oldPath {
            return .folder(knowledgeBaseID: knowledgeBaseID, path: newPath)
        }
        guard path.hasPrefix("\(oldPath)/") else {
            return collection
        }
        let suffix = path.dropFirst(oldPath.count)
        return .folder(knowledgeBaseID: knowledgeBaseID, path: newPath + suffix)
    }

    private func collectionReferencing(
        _ path: String,
        knowledgeBaseID: UUID,
        in collection: WorkspaceCollection
    ) -> Bool {
        guard case let .folder(collectionKnowledgeBaseID, selectedPath) = collection,
              collectionKnowledgeBaseID == knowledgeBaseID else {
            return false
        }
        return selectedPath == path || selectedPath.hasPrefix("\(path)/")
    }

    private func invalidateNoteLoad() {
        noteLoadGeneration += 1
        isLoadingNote = false
    }

    private func tagMutationNotice(
        mode: WorkspaceTagMutationMode,
        tagCount: Int,
        materialCount: Int
    ) -> String {
        switch mode {
        case .add:
            "已为 \(materialCount) 篇材料添加 \(tagCount) 个标签"
        case .remove:
            "已从 \(materialCount) 篇材料移除 \(tagCount) 个标签"
        case .replace:
            tagCount == 0
                ? "已清除 \(materialCount) 篇材料的全部标签"
                : "已替换 \(materialCount) 篇材料的标签"
        }
    }

    private func folderNameOrder(
        _ lhs: KnowledgeFolder,
        _ rhs: KnowledgeFolder
    ) -> Bool {
        lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private func materialNameOrder(
        _ lhs: StudyMaterialSummary,
        _ rhs: StudyMaterialSummary
    ) -> Bool {
        lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    private func appendVisibleDirectoryMaterialIDs(
        in knowledgeBaseID: UUID,
        parentPath: String,
        to result: inout [UUID]
    ) {
        for folder in childFolders(
            in: knowledgeBaseID,
            parentPath: parentPath
        ) where isDirectoryExpanded(
            path: folder.path,
            in: knowledgeBaseID
        ) {
            appendVisibleDirectoryMaterialIDs(
                in: knowledgeBaseID,
                parentPath: folder.path,
                to: &result
            )
        }
        result.append(
            contentsOf: childMaterials(
                in: knowledgeBaseID,
                parentPath: parentPath
            ).map(\.id)
        )
    }

    private func reconcileDirectoryExpansions() {
        let knowledgeBaseIDs = Set(knowledgeBases.map(\.id))
        expandedDirectoryPathsByKnowledgeBase =
            expandedDirectoryPathsByKnowledgeBase.filter {
                knowledgeBaseIDs.contains($0.key)
            }
        for knowledgeBaseID in knowledgeBaseIDs {
            let validPaths = Set(
                [""] + folders
                    .filter { $0.knowledgeBaseID == knowledgeBaseID }
                    .map(\.path)
            )
            var paths = expandedDirectoryPathsByKnowledgeBase[
                knowledgeBaseID
            ] ?? treeExpansionStore.load(
                knowledgeBaseID: knowledgeBaseID
            ) ?? [""]
            paths.formIntersection(validPaths)
            paths.insert("")
            persistDirectoryExpansion(paths, in: knowledgeBaseID)
        }
    }

    private func persistDirectoryExpansion(
        _ paths: Set<String>,
        in knowledgeBaseID: UUID
    ) {
        expandedDirectoryPathsByKnowledgeBase[knowledgeBaseID] = paths
        treeExpansionStore.save(paths, knowledgeBaseID: knowledgeBaseID)
    }

    private func rebaseDirectoryExpansion(
        from oldPath: String,
        to newPath: String,
        in knowledgeBaseID: UUID
    ) {
        let paths = DirectoryPath.rebase(
            expandedDirectoryPaths(in: knowledgeBaseID),
            from: oldPath,
            to: newPath
        )
        persistDirectoryExpansion(paths, in: knowledgeBaseID)
    }

    private func persistWorkspacePreferences() {
        try? devicePreferences.save(
            workspacePreferences: workspacePreferences
        )
    }

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
    }
}
