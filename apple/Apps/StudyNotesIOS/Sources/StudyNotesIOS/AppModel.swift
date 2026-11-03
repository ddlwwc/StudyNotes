import Foundation
import Network
import Observation
import StudyNotesIOSCore
import StudyNotesKit

struct WorkspaceMoveDestination: Identifiable, Hashable {
    let title: String
    let knowledgeBaseID: UUID
    let folderPath: String

    var id: String {
        "\(knowledgeBaseID.uuidString)/\(folderPath)"
    }
}

@MainActor
@Observable
final class IOSAppModel {
    enum Tab: Hashable {
        case library
        case inbox
        case search
        case review
    }

    var selectedTab: Tab = .library
    var rootState: IOSRootState = .iCloudContainerUnavailable
    var snapshot = IOSLibrarySnapshot.empty
    var workspace = IOSWorkspaceState()
    var inboxItems: [InboxItem] = []
    var providers: [AIProvider] = []
    var selectedProviderID: UUID?
    var searchText = ""
    var searchHits: [StudyNotesIOSCore.SearchHit] = []
    var searchScope = SearchScopeSummary(
        metadataCount: 0,
        fullTextCount: 0,
        downloadedCount: 0,
        offlineCount: 0
    )
    var isLoading = false
    var errorMessage: String?
    var noticeMessage: String?
    var showingProviderSettings = false
    var showingSettings = false
    var readingPreferences = IOSReadingPreferences()
    var publishingServerURL = IOSSettingsStore.defaultPublishingServerURL
    var mediaKeyConfigured = false
    var mediaStatus: NoteMediaStatusResponse?
    var mediaStatusMessage = "尚未请求媒体服务状态"
    var mediaStatusIsLoading = false
    var mediaQueue: [NoteMediaUploadItem] = []
    var mediaConnection: NoteMediaConnection = .unknown
    var mediaCacheByteCount = 0
    var mediaScan: NoteMediaReferenceScanResponse?
    var mediaHistoricalFiles: [NoteMediaHistoricalLocalFile] = []
    var isScanningMedia = false
    var editorDrafts: [UUID: String] = [:]

    @ObservationIgnored private var libraryStore: IOSLibraryStore?
    @ObservationIgnored private var inboxStore: InboxStore?
    @ObservationIgnored private var searchService: LibrarySearchService?
    @ObservationIgnored private let providerStore = AIProviderStore()
    @ObservationIgnored private let settingsStore = IOSSettingsStore()
    @ObservationIgnored private let mediaNetworkMonitor = NWPathMonitor()
    @ObservationIgnored private let mediaNetworkQueue = DispatchQueue(
        label: "com.studynotes.media-network"
    )
    @ObservationIgnored private var mediaCoordinator: NoteMediaCoordinator?
    @ObservationIgnored private var mediaStatusGeneration = 0
    @ObservationIgnored private var didStart = false
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    init() {
        readingPreferences = settingsStore.loadReadingPreferences()
        publishingServerURL = settingsStore.loadPublishingServerURL()
        mediaKeyConfigured = settingsStore.hasMediaKey()
        if let supportURL = try? StudyNotesFileSupport
            .applicationSupportDirectory(),
            let baseURL = URL(string: publishingServerURL) {
            mediaCoordinator = try? NoteMediaCoordinator(
                applicationSupportRoot: supportURL,
                baseURL: baseURL,
                credentialStore: settingsStore.mediaCredentialStore
            )
        }
        mediaNetworkMonitor.pathUpdateHandler = { [weak self] path in
            let connection: NoteMediaConnection
            if path.status == .satisfied {
                connection = path.usesInterfaceType(.cellular)
                    ? .cellular
                    : .wifi
            } else {
                connection = .unknown
            }
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                let changed = mediaConnection != connection
                mediaConnection = connection
                if changed, connection != .unknown {
                    await refreshMediaStatus()
                }
            }
        }
        mediaNetworkMonitor.start(queue: mediaNetworkQueue)
        switch ProcessInfo.processInfo.environment["STUDYNOTES_START_TAB"] {
        case "inbox":
            selectedTab = .inbox
        case "search":
            selectedTab = .search
        case "review":
            selectedTab = .review
        default:
            selectedTab = .library
        }
    }

    deinit {
        mediaNetworkMonitor.cancel()
    }

    var isICloud: Bool {
        if case .available(_, true) = rootState {
            return true
        }
        return false
    }

    var selectedProvider: AIProvider? {
        providers.first { $0.id == selectedProviderID } ?? providers.first
    }

    func start() async {
        guard !didStart else {
            return
        }
        didStart = true
        await loadProviders()
        rootState = StudyNotesFileSupport.resolveRoot(allowLocalFallback: true)
        await reloadAll()
        await refreshMediaStatus()
        if let materialID = ProcessInfo.processInfo.environment["STUDYNOTES_OPEN_MATERIAL"],
           let id = UUID(uuidString: materialID) {
            selectMaterial(id)
        }
    }

    func retryICloud() async {
        rootState = StudyNotesFileSupport.resolveRoot(allowLocalFallback: false)
        if rootState.url == nil {
            rootState = StudyNotesFileSupport.resolveRoot(allowLocalFallback: true)
        }
        await reloadAll()
    }

    func reloadAll() async {
        guard let rootURL = rootState.url else {
            errorMessage = rootState.label
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let libraryStore = try IOSLibraryStore(rootURL: rootURL)
            let inboxStore = try InboxStore(rootURL: rootURL)
            self.libraryStore = libraryStore
            self.inboxStore = inboxStore
            let searchService = LibrarySearchService(libraryStore: libraryStore)
            self.searchService = searchService
            snapshot = try await libraryStore.snapshot(isICloud: isICloud)
            reconcileWorkspace()
            inboxItems = try await inboxStore.listItems()
            searchScope = await searchService.scopeSummary(snapshot: snapshot)
            await runSearch()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func material(id: UUID) -> LibraryMaterial? {
        snapshot.materials.first { $0.id == id }
    }

    func updateWorkspaceLayout(isRegular: Bool) {
        workspace.updateLayout(isRegular ? .regular : .compact)
    }

    func selectKnowledgeBase(_ id: UUID) {
        workspace.openKnowledgeBase(id)
    }

    func selectFolder(_ path: String) {
        workspace.openFolder(path)
    }

    func selectMaterial(_ id: UUID, editing: Bool = false) {
        mediaScan = nil
        mediaHistoricalFiles = []
        if let material = material(id: id),
           let knowledgeBaseID = material.manifest.knowledgeBaseID {
            workspace.openKnowledgeBase(knowledgeBaseID)
            workspace.openFolder(material.folderPath)
        }
        workspace.openMaterial(id, editing: editing)
    }

    func navigateBack() {
        workspace.navigateBack()
    }

    func setEditing(_ editing: Bool) {
        workspace.setEditing(editing)
    }

    func editorDraft(for materialID: UUID) -> String? {
        editorDrafts[materialID]
    }

    func updateEditorDraft(_ text: String, materialID: UUID) {
        editorDrafts[materialID] = text
    }

    func clearEditorDraft(materialID: UUID) {
        editorDrafts.removeValue(forKey: materialID)
    }

    func folders(for knowledgeBase: KnowledgeBaseSummary) -> [FolderNode] {
        LibraryTreeBuilder.folders(
            for: knowledgeBase.id,
            in: snapshot.materials,
            knownFolders: snapshot.folders
        )
    }

    func folder(at path: String, in knowledgeBase: KnowledgeBaseSummary) -> FolderNode? {
        LibraryTreeBuilder.folder(
            at: path,
            in: folders(for: knowledgeBase)
        )
    }

    func materials(
        in knowledgeBase: KnowledgeBaseSummary,
        folderPath: String
    ) -> [LibraryMaterial] {
        snapshot.materials
            .filter {
                $0.manifest.knowledgeBaseID == knowledgeBase.id
                    && $0.folderPath == folderPath
            }
            .sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
    }

    func childFolders(
        in knowledgeBase: KnowledgeBaseSummary,
        folderPath: String
    ) -> [FolderNode] {
        let roots = folders(for: knowledgeBase)
        if folderPath.isEmpty {
            return roots
        }
        return folder(at: folderPath, in: knowledgeBase)?.children ?? []
    }

    func moveDestinations(
        for knowledgeBaseID: UUID
    ) -> [WorkspaceMoveDestination] {
        snapshot.knowledgeBases
            .filter { $0.id == knowledgeBaseID }
            .flatMap { knowledgeBase -> [WorkspaceMoveDestination] in
                let folders = self.folders(for: knowledgeBase)
                return [
                    WorkspaceMoveDestination(
                        title: "\(knowledgeBase.name) / 根目录",
                        knowledgeBaseID: knowledgeBaseID,
                        folderPath: ""
                    )
                ]
                    + folders.flatMap { flatten($0) }.map {
                        WorkspaceMoveDestination(
                            title: "\(knowledgeBase.name) / \($0.path)",
                            knowledgeBaseID: knowledgeBaseID,
                            folderPath: $0.path
                        )
                    }
            }
    }

    func materialMoveDestinations() -> [WorkspaceMoveDestination] {
        snapshot.knowledgeBases.flatMap { knowledgeBase in
            [
                WorkspaceMoveDestination(
                    title: "\(knowledgeBase.name) / 根目录",
                    knowledgeBaseID: knowledgeBase.id,
                    folderPath: ""
                )
            ]
                + folders(for: knowledgeBase).flatMap { flatten($0) }.map {
                    WorkspaceMoveDestination(
                        title: "\(knowledgeBase.name) / \($0.path)",
                        knowledgeBaseID: knowledgeBase.id,
                        folderPath: $0.path
                    )
                }
        }
    }

    func download(materialID: UUID) async {
        guard let libraryStore else {
            return
        }
        errorMessage = nil
        do {
            _ = try await libraryStore.requestDownload(
                materialID: materialID,
                isICloud: isICloud
            )
            noticeMessage = "正文已下载"
            snapshot = try await libraryStore.snapshot(isICloud: isICloud)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveOffline(materialID: UUID) async {
        guard let libraryStore else {
            return
        }
        errorMessage = nil
        do {
            _ = try await libraryStore.saveOffline(
                materialID: materialID,
                isICloud: isICloud
            )
            noticeMessage = "已保存到此 iPhone/iPad"
            snapshot = try await libraryStore.snapshot(isICloud: isICloud)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeOffline(materialID: UUID) async {
        guard let libraryStore else {
            return
        }
        do {
            _ = try await libraryStore.removeOffline(
                materialID: materialID,
                isICloud: isICloud
            )
            noticeMessage = "已移除离线副本"
            snapshot = try await libraryStore.snapshot(isICloud: isICloud)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func createFolder(
        named name: String,
        in knowledgeBaseID: UUID,
        parentPath: String
    ) async throws -> IOSFolder {
        guard let libraryStore else {
            throw StudyNotesIOSError.noWorkspace
        }
        let folder = try await libraryStore.createFolder(
            named: name,
            in: knowledgeBaseID,
            parentPath: parentPath
        )
        try await refreshSnapshot()
        return folder
    }

    @discardableResult
    func renameFolder(
        _ folder: FolderNode,
        knowledgeBaseID: UUID,
        to name: String
    ) async throws -> IOSFolder {
        guard let libraryStore else {
            throw StudyNotesIOSError.noWorkspace
        }
        let updated = try await libraryStore.renameFolder(
            at: folder.path,
            in: knowledgeBaseID,
            to: name
        )
        rebaseWorkspaceFolder(from: folder.path, to: updated.path)
        try await refreshSnapshot()
        return updated
    }

    @discardableResult
    func moveFolder(
        _ folder: FolderNode,
        knowledgeBaseID: UUID,
        toParentPath parentPath: String
    ) async throws -> IOSFolder {
        guard let libraryStore else {
            throw StudyNotesIOSError.noWorkspace
        }
        let updated = try await libraryStore.moveFolder(
            at: folder.path,
            in: knowledgeBaseID,
            toParentPath: parentPath
        )
        rebaseWorkspaceFolder(from: folder.path, to: updated.path)
        try await refreshSnapshot()
        return updated
    }

    func deleteFolder(
        _ folder: FolderNode,
        knowledgeBaseID: UUID
    ) async {
        guard let libraryStore else {
            return
        }
        do {
            _ = try await libraryStore.deleteFolder(
                at: folder.path,
                in: knowledgeBaseID
            )
            if workspace.folderPath == folder.path
                || workspace.folderPath.hasPrefix(folder.path + "/") {
                workspace.openFolder(
                    IOSWorkspaceState.parentPath(of: folder.path)
                )
            }
            try await refreshSnapshot()
            noticeMessage = "文件夹已删除，材料已移入回收站"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createMarkdownNote(
        in knowledgeBaseID: UUID,
        folderPath: String
    ) async {
        guard let libraryStore else {
            return
        }
        do {
            let title = "新笔记"
            let materialID = try await libraryStore.createMarkdownNote(
                title: title,
                in: knowledgeBaseID,
                markdown: "# \(title)\n\n",
                folderPath: folderPath
            )
            try await refreshSnapshot()
            workspace.openKnowledgeBase(knowledgeBaseID)
            workspace.openFolder(folderPath)
            workspace.openMaterial(materialID, editing: true)
            noticeMessage = "笔记已创建"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func moveMaterial(
        _ materialID: UUID,
        toKnowledgeBaseID knowledgeBaseID: UUID,
        folderPath: String
    ) async throws {
        guard let libraryStore else {
            throw StudyNotesIOSError.noWorkspace
        }
        try await libraryStore.moveMaterials(
            ids: [materialID],
            toKnowledgeBaseID: knowledgeBaseID,
            folderPath: folderPath
        )
        try await refreshSnapshot()
        if workspace.materialID == materialID {
            let wasEditing = workspace.isEditing
            workspace.openKnowledgeBase(knowledgeBaseID)
            workspace.openFolder(folderPath)
            workspace.openMaterial(materialID, editing: wasEditing)
        }
    }

    func moveFolderByForm(
        _ folder: FolderNode,
        knowledgeBaseID: UUID,
        toParentPath parentPath: String
    ) async throws {
        _ = try await moveFolder(
            folder,
            knowledgeBaseID: knowledgeBaseID,
            toParentPath: parentPath
        )
    }

    func moveMaterialToRecycleBin(_ materialID: UUID) async {
        guard let libraryStore else {
            return
        }
        do {
            try await libraryStore.moveMaterialsToRecycleBin(ids: [materialID])
            if workspace.materialID == materialID {
                workspace.closeMaterial()
            }
            try await refreshSnapshot()
            noticeMessage = "材料已移入回收站"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func canDrop(
        _ token: String,
        into folderPath: String,
        knowledgeBaseID: UUID
    ) -> Bool {
        let parts = token.split(separator: ":", maxSplits: 2).map(String.init)
        if parts.first == "material" {
            return parts.count == 2 && UUID(uuidString: parts[1]) != nil
        }
        guard parts.first == "folder",
              parts.count == 3,
              UUID(uuidString: parts[1]) == knowledgeBaseID else {
            return false
        }
        return IOSWorkspaceState.isValidFolderMove(
            sourcePath: parts[2],
            targetParentPath: folderPath
        )
    }

    func handleDrop(
        _ token: String,
        into folderPath: String,
        knowledgeBaseID: UUID
    ) async -> Bool {
        guard canDrop(
            token,
            into: folderPath,
            knowledgeBaseID: knowledgeBaseID
        ) else {
            if token.hasPrefix("folder:") {
                errorMessage = "不能把文件夹移动到自身或其子文件夹中。"
            }
            return false
        }
        let parts = token.split(separator: ":", maxSplits: 2).map(String.init)
        do {
            if parts.first == "folder", parts.count == 3 {
                _ = try await moveFolder(
                    FolderNode(
                        name: parts[2].split(separator: "/").last.map(String.init) ?? "",
                        path: parts[2],
                        children: [],
                        materialCount: 0
                    ),
                    knowledgeBaseID: knowledgeBaseID,
                    toParentPath: folderPath
                )
            } else if parts.first == "material",
                      parts.count >= 2,
                      let materialID = UUID(uuidString: parts[1]) {
                try await moveMaterial(
                    materialID,
                    toKnowledgeBaseID: knowledgeBaseID,
                    folderPath: folderPath
                )
            } else {
                return false
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func makeReaderModel(materialID: UUID) async throws -> ReaderSessionModel {
        guard let libraryStore else {
            throw StudyNotesIOSError.noWorkspace
        }
        let document = try await libraryStore.loadDocument(
            materialID: materialID,
            isICloud: isICloud
        )
        return try await ReaderSessionModel(
            document: document,
            libraryStore: libraryStore,
            providerStore: providerStore,
            providers: providers,
            selectedProviderID: selectedProviderID,
            isICloud: isICloud,
            mediaCoordinator: mediaCoordinator
        )
    }

    func collectURL(_ value: String) async {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard URL(string: trimmed)?.scheme != nil else {
            errorMessage = "请输入有效的网址。"
            return
        }
        let title = URL(string: trimmed)?.host ?? trimmed
        await collect(
            InboxDraft(
                kind: .url,
                title: title,
                payloadFileExtension: "txt",
                payloadData: Data(trimmed.utf8)
            )
        )
    }

    func collectText(_ value: String) async {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        let title = String(
            trimmed
                .split(separator: "\n")
                .first?
                .prefix(60) ?? "文本片段"
        )
        await collect(
            InboxDraft(
                kind: .text,
                title: title,
                payloadFileExtension: "txt",
                payloadData: Data(trimmed.utf8)
            )
        )
    }

    func collectImage(data: Data, title: String, pathExtension: String) async {
        await collect(
            InboxDraft(
                kind: .image,
                title: title,
                payloadFileExtension: pathExtension,
                payloadData: data
            )
        )
    }

    func handleIncomingURL(_ url: URL) async {
        if url.scheme == "studynotes" {
            switch url.host {
            case "inbox":
                selectedTab = .inbox
                return
            case "search":
                selectedTab = .search
                return
            case "review":
                selectedTab = .review
                return
            case "material":
                if let id = UUID(
                    uuidString: url.pathComponents.last ?? ""
                ), material(id: id) != nil {
                    selectedTab = .library
                    selectMaterial(id)
                }
                return
            default:
                break
            }
        }
        guard let inboxStore else {
            return
        }
        if url.isFileURL {
            guard let data = try? Data(contentsOf: url) else {
                errorMessage = "无法读取分享内容。"
                return
            }
            let isImage = ["png", "jpg", "jpeg", "heic"].contains(
                url.pathExtension.lowercased()
            )
            let draft: InboxDraft
            if isImage {
                draft = InboxDraft(
                    kind: .image,
                    title: url.lastPathComponent,
                    payloadFileExtension: url.pathExtension.lowercased(),
                    payloadData: data
                )
            } else if let text = String(data: data, encoding: .utf8) {
                draft = InboxDraft(
                    kind: .text,
                    title: url.lastPathComponent,
                    payloadFileExtension: "txt",
                    payloadData: Data(text.utf8)
                )
            } else {
                errorMessage = "无法识别分享文件。"
                return
            }
            let item = try? await inboxStore.collect(draft)
            applyInboxResult(item)
        } else {
            await collectURL(url.absoluteString)
        }
    }

    func retryInboxItem(_ item: InboxItem) async {
        guard let inboxStore else {
            return
        }
        let result = try? await inboxStore.retry(itemID: item.id)
        applyInboxResult(result)
    }

    func discardInboxItem(_ item: InboxItem) async {
        guard let inboxStore else {
            return
        }
        try? await inboxStore.discardPending(itemID: item.id)
        inboxItems = (try? await inboxStore.listItems()) ?? inboxItems
    }

    func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else {
                return
            }
            await runSearch()
        }
    }

    func runSearch() async {
        guard let searchService else {
            searchHits = []
            return
        }
        searchScope = await searchService.scopeSummary(snapshot: snapshot)
        searchHits = await searchService.search(
            query: searchText,
            snapshot: snapshot
        )
    }

    func loadProviders() async {
        providers = await providerStore.loadProviders()
        if selectedProviderID == nil {
            selectedProviderID = providers.first?.id
        }
    }

    func saveProvider(_ provider: AIProvider, apiKey: String?) async {
        do {
            try await providerStore.upsert(provider, apiKey: apiKey)
            await loadProviders()
            selectedProviderID = provider.id
            noticeMessage = "AI 供应商已保存"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteProvider(_ provider: AIProvider) async {
        do {
            try await providerStore.delete(provider.id)
            await loadProviders()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func apiKey(for provider: AIProvider) async -> String? {
        try? await providerStore.apiKey(for: provider.id)
    }

    func hasAPIKey(for provider: AIProvider) async -> Bool {
        await providerStore.hasAPIKey(for: provider.id)
    }

    func updateReadingPreferences(_ preferences: IOSReadingPreferences) {
        do {
            try settingsStore.save(readingPreferences: preferences)
            readingPreferences = preferences
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func savePublishingServerURL(_ value: String) {
        settingsStore.savePublishingServerURL(value)
        publishingServerURL = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        Task { await refreshMediaStatus() }
    }

    func refreshMediaKeyState() {
        mediaKeyConfigured = settingsStore.hasMediaKey()
    }

    func saveMediaKey(_ value: String) throws {
        try settingsStore.saveMediaKey(value)
        refreshMediaKeyState()
        Task { await refreshMediaStatus() }
    }

    func removeMediaKey() throws {
        try settingsStore.removeMediaKey()
        refreshMediaKeyState()
        mediaStatus = nil
        mediaStatusMessage = "尚未配置媒体密钥"
    }

    var mediaHTTPWarning: String? {
        guard let status = mediaStatus else {
            return publishingServerURL
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .hasPrefix("http://")
                ? "当前媒体服务使用 HTTP，Bearer 密钥可能在链路中被截获。"
                : nil
        }
        return status.httpWarning
            ? "当前媒体服务使用 HTTP，Bearer 密钥可能在链路中被截获。"
            : nil
    }

    var mediaCleanupCandidates: [NoteMediaUploadItem] {
        let scannedReferences = Set(
            mediaScan?.media
                .filter {
                    $0.scopes.contains(.current)
                        || $0.scopes.contains(.history)
                }
                .map(\.objectKey) ?? []
        )
        let draftReferences = workspace.materialID.flatMap {
            editorDrafts[$0]
        }.map {
            NoteMediaReferenceScanner.objectKeys(in: $0)
        } ?? []
        let references = scannedReferences.union(draftReferences)
        return mediaQueue.filter {
            $0.state == .uploaded
                && !references.contains($0.reference.objectKey)
        }
    }

    var mediaCurrentByteCount: Int {
        mediaByteCount(for: .current)
    }

    var mediaHistoricalByteCount: Int {
        mediaByteCount(for: .history)
    }

    var mediaCleanupCandidateByteCount: Int {
        mediaCleanupCandidates.reduce(0) { $0 + $1.byteCount }
    }

    func refreshMediaStatus() async {
        mediaStatusGeneration += 1
        let generation = mediaStatusGeneration
        let requestedServerURL = publishingServerURL
        if mediaCoordinator == nil {
            guard let supportURL = try? StudyNotesFileSupport
                .applicationSupportDirectory(),
                let baseURL = URL(string: publishingServerURL) else {
                mediaStatusMessage = "媒体协调器未初始化"
                return
            }
            mediaCoordinator = try? NoteMediaCoordinator(
                applicationSupportRoot: supportURL,
                baseURL: baseURL,
                credentialStore: settingsStore.mediaCredentialStore
            )
        }
        guard let mediaCoordinator else {
            mediaStatusMessage = "媒体协调器未初始化"
            return
        }
        mediaStatusIsLoading = true
        defer {
            if generation == mediaStatusGeneration {
                mediaStatusIsLoading = false
            }
        }
        mediaQueue = await mediaCoordinator.items()
        mediaCacheByteCount =
            (try? await mediaCoordinator.cacheSize()) ?? 0
        do {
            guard let baseURL = URL(string: requestedServerURL) else {
                throw NoteMediaCoordinatorError.invalidBaseURL
            }
            try await mediaCoordinator.configure(baseURL: baseURL)
            let status = try await mediaCoordinator.status()
            guard generation == mediaStatusGeneration,
                  requestedServerURL == publishingServerURL else {
                return
            }
            mediaStatus = status
            mediaStatusMessage =
                status.message ?? (status.ok ? "媒体服务可用" : "媒体服务未就绪")
            await resumePendingMediaUploads()
        } catch {
            guard generation == mediaStatusGeneration else {
                return
            }
            mediaStatus = nil
            mediaStatusMessage = error.localizedDescription
        }
    }

    @discardableResult
    func insertMedia(
        fileAt url: URL,
        contentType: String,
        connection: NoteMediaConnection,
        confirmedCellularUpload: Bool = false
    ) async -> NoteMediaInsertionDecision? {
        guard let mediaCoordinator else {
            errorMessage = "媒体协调器未初始化"
            return nil
        }
        do {
            let decision = try await mediaCoordinator.prepareInsertion(
                fileAt: url,
                contentType: contentType,
                connection: connection,
                confirmedCellularUpload: confirmedCellularUpload
            )
            mediaQueue = await mediaCoordinator.items()
            return decision
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func requiresCellularConfirmation(
        for item: NoteMediaUploadItem
    ) -> Bool {
        (try? NoteMediaPolicy.requiresCellularConfirmation(
            byteCount: item.byteCount,
            connection: mediaConnection
        )) == true
    }

    @discardableResult
    func uploadMedia(
        id: UUID,
        confirmedCellularUpload: Bool = false
    ) async -> Bool {
        guard let mediaCoordinator else {
            return false
        }
        let queuedItems = await mediaCoordinator.items()
        guard let item = mediaQueue.first(where: { $0.id == id })
            ?? queuedItems.first(where: { $0.id == id }) else {
            return false
        }
        if requiresCellularConfirmation(for: item),
           !confirmedCellularUpload {
            errorMessage = "该媒体超过 10MB，请确认使用蜂窝网络上传。"
            return false
        }
        let refreshTask = startMediaQueuePolling()
        defer { refreshTask.cancel() }
        do {
            _ = try await mediaCoordinator.upload(id: id)
            mediaQueue = await mediaCoordinator.items()
            return true
        } catch {
            mediaQueue = await mediaCoordinator.items()
            errorMessage = error.localizedDescription
            return false
        }
    }

    func retryMediaUpload(id: UUID) async {
        guard let mediaCoordinator else {
            return
        }
        let refreshTask = startMediaQueuePolling()
        defer { refreshTask.cancel() }
        do {
            _ = try await mediaCoordinator.retry(id: id)
            mediaQueue = await mediaCoordinator.items()
        } catch {
            mediaQueue = await mediaCoordinator.items()
            errorMessage = error.localizedDescription
        }
    }

    func cancelMediaUpload(id: UUID) async {
        guard let mediaCoordinator else {
            return
        }
        do {
            try await mediaCoordinator.cancel(id: id)
            mediaQueue = await mediaCoordinator.items()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearMediaCache() async {
        guard let mediaCoordinator else {
            return
        }
        do {
            try await mediaCoordinator.clearCache()
            mediaCacheByteCount = 0
            noticeMessage = "已清除本机媒体缓存"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func scanSelectedMedia() async {
        guard let mediaCoordinator,
              let materialID = workspace.materialID,
              let libraryStore else {
            errorMessage = "请先打开一篇笔记再扫描媒体"
            return
        }
        mediaScan = nil
        mediaHistoricalFiles = []
        isScanningMedia = true
        defer { isScanningMedia = false }
        do {
            let document = try await libraryStore.loadDocument(
                materialID: materialID,
                isICloud: isICloud
            )
            let legacyDirectory = document.packageURL
                .appending(path: "source", directoryHint: .isDirectory)
                .appending(path: "media", directoryHint: .isDirectory)
            mediaHistoricalFiles =
                try NoteMediaCoordinator.historicalLocalFiles(
                    in: legacyDirectory
                )
            mediaScan = try await mediaCoordinator.scan(
                sourceId: document.id.uuidString,
                currentMarkdown: document.sourceText ?? "",
                historicalMarkdowns: historicalMarkdowns(
                    in: document.packageURL
                ),
                historicalLocalMedia: mediaHistoricalFiles.map {
                    NoteMediaHistoricalLocalReference(
                        reference: $0.reference,
                        size: $0.size
                    )
                }
            )
            mediaQueue = await mediaCoordinator.items()
            mediaCacheByteCount =
                (try? await mediaCoordinator.cacheSize()) ?? 0
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func migrateSelectedMediaHistory() async {
        guard let mediaCoordinator else {
            return
        }
        do {
            let references = try await mediaCoordinator
                .migrateHistoricalLocalFiles(
                    mediaHistoricalFiles,
                    confirmed: true
                )
            mediaQueue = await mediaCoordinator.items()
            noticeMessage =
                "已将 \(references.count) 个历史媒体加入队列；正文引用未自动改写"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cleanupUnreferencedMedia() async {
        guard let mediaCoordinator else {
            return
        }
        await scanSelectedMedia()
        guard mediaScan != nil else {
            return
        }
        let candidates = mediaCleanupCandidates
        guard !candidates.isEmpty else {
            noticeMessage = "没有可清理的本机已知云端媒体"
            return
        }
        do {
            let response = try await mediaCoordinator.cleanup(
                objectKeys: candidates.map(\.reference.objectKey),
                confirmed: true
            )
            noticeMessage = response.queued.isEmpty
                ? "服务端已跳过全部清理请求"
                : "已排队清理 \(response.queued.count) 个媒体对象"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var readerMediaCoordinator: NoteMediaCoordinator? {
        mediaCoordinator
    }

    private func historicalMarkdowns(in packageURL: URL) -> [String] {
        let revisionsURL = packageURL.appending(
            path: "revisions",
            directoryHint: .isDirectory
        )
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: revisionsURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return files.compactMap { url in
            guard url.pathExtension.lowercased() == "md",
                  let values = try? url.resourceValues(
                      forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
                  ),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true else {
                return nil
            }
            return coordinatedText(at: url)
        }
    }

    private func coordinatedText(at url: URL) -> String? {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var text: String?
        coordinator.coordinate(
            readingItemAt: url,
            options: [],
            error: &coordinationError
        ) { coordinatedURL in
            text = try? String(
                contentsOf: coordinatedURL,
                encoding: .utf8
            )
        }
        guard coordinationError == nil else {
            return nil
        }
        return text
    }

    private func mediaByteCount(
        for scope: NoteMediaReferenceScope
    ) -> Int {
        mediaScan?.media
            .filter { $0.scopes.contains(scope) }
            .reduce(0) { $0 + ($1.size ?? 0) } ?? 0
    }

    private func startMediaQueuePolling() -> Task<Void, Never> {
        Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let coordinator = mediaCoordinator else {
                    return
                }
                mediaQueue = await coordinator.items()
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    private func resumePendingMediaUploads() async {
        guard mediaConnection != .unknown,
              mediaStatus?.ok == true else {
            return
        }
        let waiting = mediaQueue.filter { $0.state == .waiting }
        for item in waiting where !requiresCellularConfirmation(for: item) {
            _ = await uploadMedia(id: item.id)
        }
    }

    func editingBindingValue() -> Bool {
        workspace.isEditing
    }

    private func collect(_ draft: InboxDraft) async {
        guard let inboxStore else {
            return
        }
        let item = try? await inboxStore.collect(draft)
        applyInboxResult(item)
    }

    private func applyInboxResult(_ item: InboxItem?) {
        guard let item else {
            errorMessage = "收件箱写入失败，草稿已保留，可手动重试。"
            Task {
                if let inboxStore {
                    inboxItems = (try? await inboxStore.listItems()) ?? inboxItems
                }
            }
            return
        }
        switch item.status {
        case .collected:
            noticeMessage = "已写入 iCloud 收件箱"
        case .pending:
            noticeMessage = "已保留本地草稿"
        case let .failed(message):
            errorMessage = message
        }
        Task {
            if let inboxStore {
                inboxItems = (try? await inboxStore.listItems()) ?? inboxItems
            }
        }
    }

    private func refreshSnapshot() async throws {
        guard let libraryStore else {
            throw StudyNotesIOSError.noWorkspace
        }
        snapshot = try await libraryStore.snapshot(isICloud: isICloud)
        reconcileWorkspace()
        if let searchService {
            searchScope = await searchService.scopeSummary(snapshot: snapshot)
            await runSearch()
        }
    }

    private func reconcileWorkspace() {
        workspace.reconcile(
            validKnowledgeBaseIDs: Set(snapshot.knowledgeBases.map(\.id)),
            folderPaths: Set(snapshot.folders.map(\.path)),
            materialIDs: Set(snapshot.materials.map(\.id))
        )
    }

    private func rebaseWorkspaceFolder(from oldPath: String, to newPath: String) {
        workspace.rebaseFolderPath(from: oldPath, to: newPath)
    }

    private func flatten(_ folder: FolderNode) -> [FolderNode] {
        [folder] + folder.children.flatMap(flatten)
    }
}
