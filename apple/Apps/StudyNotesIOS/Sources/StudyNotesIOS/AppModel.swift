import Foundation
import Observation
import StudyNotesIOSCore

@MainActor
@Observable
final class IOSAppModel {
    enum Tab: Hashable {
        case library
        case inbox
        case search
        case review
    }

    struct ReaderRoute: Identifiable, Hashable {
        let id: UUID
    }

    var selectedTab: Tab = .library
    var rootState: IOSRootState = .iCloudContainerUnavailable
    var snapshot = IOSLibrarySnapshot.empty
    var inboxItems: [InboxItem] = []
    var providers: [AIProvider] = []
    var selectedProviderID: UUID?
    var searchText = ""
    var searchHits: [SearchHit] = []
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
    var readerRoute: ReaderRoute?

    @ObservationIgnored private var libraryStore: IOSLibraryStore?
    @ObservationIgnored private var inboxStore: InboxStore?
    @ObservationIgnored private var searchService: LibrarySearchService?
    @ObservationIgnored private let providerStore = AIProviderStore()
    @ObservationIgnored private var didStart = false
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    init() {
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
        if let materialID = ProcessInfo.processInfo.environment["STUDYNOTES_OPEN_MATERIAL"],
           let id = UUID(uuidString: materialID) {
            readerRoute = ReaderRoute(id: id)
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
            selectedProviderID: selectedProviderID
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
                    readerRoute = ReaderRoute(id: id)
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
}
