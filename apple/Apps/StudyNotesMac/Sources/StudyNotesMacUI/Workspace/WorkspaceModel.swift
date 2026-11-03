import Foundation
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
    public private(set) var connectionState: WorkspaceConnectionState = .disconnected
    public private(set) var isLoadingIndex = false
    public private(set) var isLoadingNote = false
    public private(set) var isPerformingAction = false
    public private(set) var errorMessage: String?
    public private(set) var actionNotice: String?

    public var selectedCollection: WorkspaceCollection = .all
    public var selectedMaterialIDs: Set<UUID> = []
    public var searchText = ""
    public var isStudyPanelVisible = true
    public var studyPanelTab: StudyPanelTab = .annotations
    public var isShowingCreateKnowledgeBase = false
    public var isShowingCreateNote = false
    public var isShowingMoveMaterials = false
    public var isShowingEditTags = false
    public var isConfirmingRecycle = false
    public var isConfirmingPurgeExpired = false
    public var createFolderRequest: WorkspaceCreateFolderRequest?
    public var renameRequest: WorkspaceRenameTarget?
    public var moveFolderRequest: WorkspaceMoveFolderRequest?

    @ObservationIgnored private let rootStore: WorkspaceRootStore
    @ObservationIgnored private var store: StudyNotesStore?
    @ObservationIgnored private var didRestoreWorkspace = false
    @ObservationIgnored private var noteLoadGeneration = 0
    @ObservationIgnored private var refreshGeneration = 0

    public init(rootStore: WorkspaceRootStore = WorkspaceRootStore()) {
        self.rootStore = rootStore
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
        return materials(in: selectedCollection).filter { material in
            guard !query.isEmpty else {
                return true
            }
            let knowledgeBaseName = knowledgeBases.first {
                $0.id == material.knowledgeBaseID
            }?.name ?? ""
            let haystack = [
                material.title,
                material.folderPath,
                material.tags.joined(separator: " "),
                knowledgeBaseName
            ].joined(separator: " ")
            return haystack.localizedCaseInsensitiveContains(query)
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
            let folderCount = folders.count { $0.knowledgeBaseID == id }
            return "\(folderCount) 个文件夹 · \(materials.count { $0.knowledgeBaseID == id }) 篇材料"
        case let .folder(knowledgeBaseID, path):
            let folder = folders.first {
                $0.knowledgeBaseID == knowledgeBaseID && $0.path == path
            }
            return "\(folder?.name ?? path) · \(materials(in: selectedCollection).count) 篇材料"
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
            "inbox"
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

        invalidateNoteLoad()
        selectedCollection = collection
        selectedMaterialIDs = []
        selectedNote = nil
        await selectFirstMaterialIfAvailable()
    }

    public func selectKnowledgeBase(_ id: UUID?) async {
        await selectCollection(id.map(WorkspaceCollection.knowledgeBase) ?? .all)
    }

    public func selectFolder(knowledgeBaseID: UUID, path: String) async {
        await selectCollection(.folder(knowledgeBaseID: knowledgeBaseID, path: path))
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
        await updateReaderForSelection()
    }

    public func searchDidChange() async {
        let visibleIDs = Set(filteredMaterials.map(\.id))
        selectedMaterialIDs.formIntersection(visibleIDs)
        await updateReaderForSelection()
    }

    public func selectMaterial(_ id: UUID) async {
        guard !isLoadingIndex else {
            return
        }
        selectedMaterialIDs = [id]
        await updateReaderForSelection()
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
        folders.filter { $0.knowledgeBaseID == knowledgeBaseID }
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
        isShowingCreateNote = true
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
                preferredSelection: []
            )
            if succeeded {
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
                selectedNote = note
                isShowingCreateNote = false
                actionNotice = "已创建笔记“\(note.summary.title)”"
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
                actionNotice = "已创建收件箱笔记“\(note.summary.title)”"
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
        guard let store, isConnected, canMoveSelection else {
            return false
        }

        let ids = Array(selectedMaterialIDs)
        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            let movedIDs = try await store.moveMaterials(
                ids: ids,
                toKnowledgeBaseID: knowledgeBaseID,
                folderPath: folderPath
            )
            let succeeded = await refreshIndex(
                preferredCollection: selectedCollection,
                preferredSelection: Set(movedIDs)
            )
            if succeeded {
                isShowingMoveMaterials = false
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
        settleSelectedCollection()

        let visibleIDs = Set(filteredMaterials.map(\.id))
        selectedMaterialIDs.formIntersection(visibleIDs)
        if let selectedNote,
           !allMaterials.contains(where: { $0.id == selectedNote.summary.id }) {
            invalidateNoteLoad()
            self.selectedNote = nil
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
        selectedNote = nil
    }

    private func selectFirstMaterialIfAvailable() async {
        guard let firstMaterial = filteredMaterials.first else {
            selectedNote = nil
            return
        }
        selectedMaterialIDs = [firstMaterial.id]
        await updateReaderForSelection()
    }

    private func updateReaderForSelection() async {
        invalidateNoteLoad()

        guard selectedMaterialIDs.count == 1,
              let materialID = selectedMaterialIDs.first else {
            selectedNote = nil
            return
        }

        if selectedNote?.summary.id == materialID {
            return
        }
        await loadNote(id: materialID)
    }

    private func loadNote(id: UUID) async {
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
            let note = try await store.loadMarkdownNote(id: id)
            guard selectedMaterialIDs == [id], noteLoadGeneration == generation else {
                return
            }
            selectedNote = note
        } catch {
            guard noteLoadGeneration == generation else {
                return
            }
            selectedNote = nil
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

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
    }
}
