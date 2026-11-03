import Foundation
import Observation
import StudyNotesKit

@MainActor
@Observable
public final class WorkspaceModel {
    public private(set) var knowledgeBases: [KnowledgeBase] = []
    public private(set) var materials: [StudyMaterialSummary] = []
    public private(set) var selectedNote: MarkdownNote?
    public private(set) var selectedMaterialID: UUID?
    public private(set) var connectionState: WorkspaceConnectionState = .disconnected
    public private(set) var isLoadingIndex = false
    public private(set) var isLoadingNote = false
    public private(set) var isPerformingAction = false
    public private(set) var errorMessage: String?

    public var selectedKnowledgeBaseID: UUID?
    public var searchText = ""
    public var isStudyPanelVisible = true
    public var studyPanelTab: StudyPanelTab = .annotations
    public var isShowingCreateKnowledgeBase = false
    public var isShowingCreateNote = false

    @ObservationIgnored private let rootStore: WorkspaceRootStore
    @ObservationIgnored private var store: StudyNotesStore?
    @ObservationIgnored private var didRestoreWorkspace = false
    @ObservationIgnored private var noteLoadGeneration = 0

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
        isConnected && !knowledgeBases.isEmpty
    }

    public var selectedKnowledgeBase: KnowledgeBase? {
        guard let selectedKnowledgeBaseID else {
            return nil
        }
        return knowledgeBases.first { $0.id == selectedKnowledgeBaseID }
    }

    public var selectedMaterial: StudyMaterialSummary? {
        guard let selectedMaterialID else {
            return nil
        }
        return materials.first { $0.id == selectedMaterialID }
    }

    public var filteredMaterials: [StudyMaterialSummary] {
        materials.filter { material in
            let matchesKnowledgeBase = selectedKnowledgeBaseID == nil
                || material.knowledgeBaseID == selectedKnowledgeBaseID
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = query.isEmpty || material.title.localizedCaseInsensitiveContains(query)
            return matchesKnowledgeBase && matchesSearch
        }
    }

    public var scopeTitle: String {
        selectedKnowledgeBase?.name ?? "全部材料"
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
        guard let store, case let .connected(location) = connectionState else {
            return
        }

        isLoadingIndex = true
        defer { isLoadingIndex = false }

        do {
            let index = try await store.loadIndex()
            apply(index: index, preferredKnowledgeBaseID: selectedKnowledgeBaseID)
            connectionState = .connected(location)

            if let selectedMaterialID,
               materials.contains(where: { $0.id == selectedMaterialID }) {
                await selectMaterial(selectedMaterialID)
            } else if let firstMaterial = filteredMaterials.first {
                await selectMaterial(firstMaterial.id)
            } else {
                selectedNote = nil
            }
        } catch {
            present(error)
        }
    }

    public func selectKnowledgeBase(_ id: UUID?) async {
        invalidateNoteLoad()
        selectedKnowledgeBaseID = id
        selectedMaterialID = nil
        selectedNote = nil

        if let firstMaterial = filteredMaterials.first {
            await selectMaterial(firstMaterial.id)
        }
    }

    public func selectMaterial(_ id: UUID) async {
        guard let store else {
            return
        }

        noteLoadGeneration += 1
        let generation = noteLoadGeneration
        selectedMaterialID = id
        isLoadingNote = true
        defer {
            if noteLoadGeneration == generation {
                isLoadingNote = false
            }
        }

        do {
            let note = try await store.loadMarkdownNote(id: id)
            guard selectedMaterialID == id, noteLoadGeneration == generation else {
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

    public func createKnowledgeBase(named name: String) async {
        guard let store, isConnected else {
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return
        }

        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            let knowledgeBase = try await store.createKnowledgeBase(named: trimmedName)
            let index = try await store.loadIndex()
            selectedKnowledgeBaseID = knowledgeBase.id
            selectedMaterialID = nil
            selectedNote = nil
            apply(index: index, preferredKnowledgeBaseID: knowledgeBase.id)
            isShowingCreateKnowledgeBase = false
        } catch {
            present(error)
        }
    }

    public func createMarkdownNote(
        title: String,
        markdown: String,
        in knowledgeBaseID: UUID
    ) async {
        guard let store, isConnected else {
            return
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return
        }

        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            let note = try await store.createMarkdownNote(
                title: trimmedTitle,
                in: knowledgeBaseID,
                markdown: markdown
            )
            let index = try await store.loadIndex()
            selectedKnowledgeBaseID = knowledgeBaseID
            apply(index: index, preferredKnowledgeBaseID: knowledgeBaseID)
            invalidateNoteLoad()
            selectedMaterialID = note.summary.id
            selectedNote = note
            isShowingCreateNote = false
        } catch {
            present(error)
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

    public func dismissError() {
        errorMessage = nil
    }

    private func loadWorkspace(at location: WorkspaceLocation) async {
        invalidateNoteLoad()
        isLoadingIndex = true
        connectionState = .connecting
        defer { isLoadingIndex = false }

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
            store = newStore
            selectedKnowledgeBaseID = index.knowledgeBases.first?.id
            selectedMaterialID = nil
            selectedNote = nil
            apply(index: index, preferredKnowledgeBaseID: selectedKnowledgeBaseID)
            connectionState = .connected(location)

            if let firstMaterial = filteredMaterials.first {
                await selectMaterial(firstMaterial.id)
            }
        } catch {
            store = nil
            knowledgeBases = []
            materials = []
            selectedKnowledgeBaseID = nil
            selectedMaterialID = nil
            selectedNote = nil
            connectionState = .failed(error.localizedDescription)
        }
    }

    private func apply(index: LibraryIndex, preferredKnowledgeBaseID: UUID?) {
        knowledgeBases = index.knowledgeBases
        materials = index.materials

        if let preferredKnowledgeBaseID,
           index.knowledgeBases.contains(where: { $0.id == preferredKnowledgeBaseID }) {
            selectedKnowledgeBaseID = preferredKnowledgeBaseID
        } else if let currentID = selectedKnowledgeBaseID,
                  index.knowledgeBases.contains(where: { $0.id == currentID }) {
            selectedKnowledgeBaseID = currentID
        } else {
            selectedKnowledgeBaseID = index.knowledgeBases.first?.id
        }

        if let selectedMaterialID,
           !index.materials.contains(where: { $0.id == selectedMaterialID }) {
            invalidateNoteLoad()
            self.selectedMaterialID = nil
            selectedNote = nil
        }
    }

    private func invalidateNoteLoad() {
        noteLoadGeneration += 1
        isLoadingNote = false
    }

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
    }
}
