import Foundation
import Observation
import StudyNotesKit

@MainActor
@Observable
final class PublishingPanelModel {
    typealias MappingSaver = @MainActor (PublishMapping) async -> Bool
    typealias MappingClearer = @MainActor () async -> Void

    var serverURLText: String {
        didSet {
            PublishingServerSettings.save(serverURLText)
        }
    }
    var registrationSecret = ""
    var visibility: PublishVisibility = .publicArticle
    var rollbackTargetText = ""

    private(set) var credential: PublishingCredential?
    private(set) var currentStatus: PublishingStatusResponse?
    private(set) var mediaStates: [String: PublishMediaState] = [:]
    private(set) var isBusy = false
    private(set) var statusMessage: String?
    private(set) var hasError = false

    @ObservationIgnored private let keyService: PublishingKeyService
    @ObservationIgnored private var preview: PublishPreview?
    @ObservationIgnored private var tags: [String] = []
    @ObservationIgnored private var saveMapping: MappingSaver?
    @ObservationIgnored private var clearMapping: MappingClearer?
    @ObservationIgnored private var uploadedMedia: [String: UploadedPublishingMedia] = [:]
    @ObservationIgnored private var pendingPublishRequest: PublishingRequest?
    @ObservationIgnored private var pendingPublishSnapshot: String?
    @ObservationIgnored private var pendingActionRequestIDs: [String: String] = [:]
    @ObservationIgnored private var mediaSignature = ""
    @ObservationIgnored private var hasInitializedVisibility = false

    init(
        credentialStore: any PublishingCredentialStoring =
            KeychainPublishingCredentialStore()
    ) {
        self.serverURLText = PublishingServerSettings.load()
        self.keyService = PublishingKeyService(store: credentialStore)
        do {
            credential = try keyService.current()
        } catch {
            statusMessage = error.localizedDescription
            hasError = true
        }
    }

    var credentialKid: String? {
        credential?.kid
    }

    var articleID: String? {
        currentStatus?.articleId ?? preview?.mapping?.articleID
    }

    var expectedVersion: Int {
        currentStatus?.currentVersion
            ?? preview?.mapping?.lastPublishedVersion.flatMap(Int.init)
            ?? 0
    }

    var mediaItems: [PublishMediaItem] {
        preview?.media ?? []
    }

    var hasRetryableMedia: Bool {
        mediaItems.contains {
            let state = mediaState(for: $0)
            return state == .failed || state == .pendingCredentials
                || state == .pendingUpload
        }
    }

    func attach(
        preview: PublishPreview,
        tags: [String],
        saveMapping: @escaping MappingSaver,
        clearMapping: @escaping MappingClearer
    ) {
        self.saveMapping = saveMapping
        self.clearMapping = clearMapping
        update(preview: preview, tags: tags)
    }

    func update(preview: PublishPreview, tags: [String]) {
        self.preview = preview
        self.tags = tags
        let nextMediaSignature = preview.media
            .map { "\($0.id)|\($0.contentHash)|\($0.byteCount)" }
            .joined(separator: ",")
        if nextMediaSignature != mediaSignature {
            mediaSignature = nextMediaSignature
            uploadedMedia = [:]
            mediaStates = Dictionary(
                uniqueKeysWithValues: preview.media.map { ($0.id, $0.state) }
            )
            pendingPublishRequest = nil
            pendingPublishSnapshot = nil
        }
        if let mapping = preview.mapping, !hasInitializedVisibility {
            visibility = mapping.visibility
            hasInitializedVisibility = true
        }
    }

    func mediaState(for item: PublishMediaItem) -> PublishMediaState {
        mediaStates[item.id] ?? item.state
    }

    func registerKey() async {
        await run {
            guard !registrationSecret.isEmpty else {
                throw PublishingClientError.invalidRegistrationSecret
            }
            let credential = try keyService.ensureCredential().credential
            let client = try makeClient()
            _ = try await client.registerKey(
                credential: credential,
                registrationSecret: registrationSecret
            )
            self.credential = credential
            statusMessage = "发布公钥已登记：\(credential.kid)"
            hasError = false
        }
    }

    func rotateKey() async {
        await run {
            guard !registrationSecret.isEmpty else {
                throw PublishingClientError.invalidRegistrationSecret
            }
            let client = try makeClient()
            if let current = credential {
                try await client.revokeKey(credential: current)
            }
            let rotated = try keyService.rotate().credential
            credential = rotated
            do {
                _ = try await client.registerKey(
                    credential: rotated,
                    registrationSecret: registrationSecret
                )
                statusMessage = "已轮换并登记发布公钥：\(rotated.kid)"
                hasError = false
            } catch {
                statusMessage = "新密钥已生成，但公钥登记失败；可再次点击“登记现有公钥”。\(error.localizedDescription)"
                hasError = true
            }
        }
    }

    func retryMedia() async {
        guard let preview else {
            return
        }
        await run {
            let client = try makeClient()
            let credential = try requireCredential()
            try await uploadPendingMedia(
                preview: preview,
                client: client,
                credential: credential
            )
            statusMessage = mediaItems.isEmpty
                ? "没有需要上传的媒体。"
                : "发布媒体已全部上传，可继续发布。"
            hasError = false
        }
    }

    @discardableResult
    func publish() async -> PublishingResponse? {
        guard let preview else {
            return nil
        }
        var response: PublishingResponse?
        await run {
            let client = try makeClient()
            let credential = try requireCredential()
            try await uploadPendingMedia(
                preview: preview,
                client: client,
                credential: credential
            )
            let request = try makePublishRequest(preview: preview)
            do {
                let result = try await client.publish(
                    request,
                    credential: credential
                )
                pendingPublishRequest = nil
                pendingPublishSnapshot = nil
                currentStatus = PublishingStatusResponse(
                    articleId: result.articleId,
                    sourceMaterialId: preview.materialID.uuidString,
                    visibility: result.visibility,
                    currentVersion: result.version,
                    publicUrl: result.publicUrl,
                    unlistedUrl: result.unlistedUrl,
                    fingerprint: result.fingerprint,
                    updatedAt: result.publishedAt
                )
                await persistCurrentStatus()
                statusMessage = result.idempotent
                    ? "服务端已返回幂等发布结果：第 \(result.version) 版。"
                    : "发布成功：第 \(result.version) 版。"
                hasError = false
                response = result
            } catch {
                if shouldDiscardPendingRequest(error) {
                    pendingPublishRequest = nil
                    pendingPublishSnapshot = nil
                }
                if let apiError = error as? PublishingAPIError,
                   apiError.code == "VERSION_CONFLICT" {
                    try? await refreshStatusInsideRun()
                }
                throw error
            }
        }
        return response
    }

    func refreshStatus() async {
        await run {
            try await refreshStatusInsideRun()
            statusMessage = "已刷新服务端发布状态。"
            hasError = false
        }
    }

    func changeVisibility(to newValue: PublishVisibility) async {
        await run {
            guard let articleID else {
                throw PublishingClientError.missingCredential
            }
            let requestID = actionRequestID(
                key: "visibility:\(articleID):\(expectedVersion):\(newValue.rawValue)"
            )
            let client = try makeClient()
            _ = try await client.changeVisibility(
                articleID: articleID,
                input: PublishingVisibilityRequest(
                    requestId: requestID,
                    expectedVersion: expectedVersion,
                    visibility: newValue.publishingVisibility
                ),
                credential: try requireCredential()
            )
            pendingActionRequestIDs.removeValue(
                forKey: "visibility:\(articleID):\(expectedVersion):\(newValue.rawValue)"
            )
            try await refreshStatusInsideRun()
            statusMessage = "文章可见性已更新为\(newValue.title)。"
            hasError = false
        }
    }

    func withdraw() async {
        await run {
            let articleID = try requireArticleID()
            let requestID = actionRequestID(
                key: "withdraw:\(articleID):\(expectedVersion)"
            )
            let client = try makeClient()
            _ = try await client.withdraw(
                articleID: articleID,
                input: PublishingWithdrawRequest(
                    requestId: requestID,
                    expectedVersion: expectedVersion
                ),
                credential: try requireCredential()
            )
            pendingActionRequestIDs.removeValue(
                forKey: "withdraw:\(articleID):\(expectedVersion)"
            )
            try await refreshStatusInsideRun()
            statusMessage = "文章已下架，公开与未列出链接均不可访问。"
            hasError = false
        }
    }

    func rollback() async {
        await run {
            guard let target = Int(rollbackTargetText),
                  target >= 1 else {
                throw PublishingClientError.invalidResponse
            }
            let articleID = try requireArticleID()
            let requestID = actionRequestID(
                key: "rollback:\(articleID):\(expectedVersion):\(target)"
            )
            let client = try makeClient()
            _ = try await client.rollback(
                articleID: articleID,
                input: PublishingRollbackRequest(
                    requestId: requestID,
                    expectedVersion: expectedVersion,
                    targetVersion: target
                ),
                credential: try requireCredential()
            )
            pendingActionRequestIDs.removeValue(
                forKey: "rollback:\(articleID):\(expectedVersion):\(target)"
            )
            try await refreshStatusInsideRun()
            statusMessage = "已回滚到第 \(target) 版。"
            hasError = false
        }
    }

    func deleteArticle() async {
        await run {
            let articleID = try requireArticleID()
            let requestID = actionRequestID(
                key: "delete:\(articleID):\(expectedVersion)"
            )
            let client = try makeClient()
            _ = try await client.deleteArticle(
                articleID: articleID,
                input: PublishingDeleteRequest(
                    requestId: requestID,
                    expectedVersion: expectedVersion
                ),
                credential: try requireCredential()
            )
            pendingActionRequestIDs.removeValue(
                forKey: "delete:\(articleID):\(expectedVersion)"
            )
            currentStatus = nil
            if let clearMapping {
                await clearMapping()
            }
            statusMessage = "Web 文章、版本和无引用媒体已永久删除。"
            hasError = false
        }
    }

    private func makePublishRequest(
        preview: PublishPreview
    ) throws -> PublishingRequest {
        let uploaded = preview.media.compactMap {
            uploadedMedia[$0.id]
        }
        let snapshot = [
            preview.contentFingerprint,
            visibility.rawValue,
            String(expectedVersion),
            articleID ?? "",
            uploaded.map(\.reference.objectKey).sorted().joined(separator: ","),
            tags.joined(separator: "\u{1f}")
        ].joined(separator: "\u{1e}")
        if pendingPublishSnapshot == snapshot,
           let pendingPublishRequest {
            return pendingPublishRequest
        }
        let request = try PublishingRequestBuilder.make(
            preview: preview,
            tags: tags,
            visibility: visibility.publishingVisibility,
            expectedVersion: expectedVersion,
            articleID: articleID,
            uploadedMedia: uploaded
        )
        pendingPublishRequest = request
        pendingPublishSnapshot = snapshot
        return request
    }

    private func uploadPendingMedia(
        preview: PublishPreview,
        client: PublishingClient,
        credential: PublishingCredential
    ) async throws {
        for item in preview.media where uploadedMedia[item.id] == nil {
            mediaStates[item.id] = .uploading
            do {
                let uploaded = try await client.uploadMedia(
                    item,
                    sourceMaterialID: preview.materialID,
                    credential: credential
                )
                uploadedMedia[item.id] = uploaded
                mediaStates[item.id] = .uploaded
            } catch {
                mediaStates[item.id] = .failed
                throw error
            }
        }
    }

    private func refreshStatusInsideRun() async throws {
        let articleID = try requireArticleID()
        let client = try makeClient()
        currentStatus = try await client.getStatus(
            articleID: articleID,
            credential: try requireCredential()
        )
        await persistCurrentStatus()
    }

    private func persistCurrentStatus() async {
        guard let currentStatus,
              currentStatus.visibility != .withdrawn,
              let version = currentStatus.currentVersion,
              let fingerprint = currentStatus.fingerprint else {
            return
        }
        let visibility = currentStatus.visibility == .publicArticle
            ? PublishVisibility.publicArticle
            : .unlisted
        let urlText = visibility == .publicArticle
            ? currentStatus.publicUrl
            : currentStatus.unlistedUrl
        guard let publicURL = URL(string: urlText),
              let saveMapping else {
            return
        }
        let mapping = PublishMapping(
            articleID: currentStatus.articleId,
            publicURL: publicURL,
            lastPublishedVersion: String(version),
            visibility: visibility,
            contentFingerprint: fingerprint,
            updatedAt: Date()
        )
        let saved = await saveMapping(mapping)
        if !saved {
            statusMessage = "Web 操作成功，但本地轻量发布映射保存失败。"
            hasError = true
        }
    }

    private func actionRequestID(key: String) -> String {
        if let requestID = pendingActionRequestIDs[key] {
            return requestID
        }
        let requestID = PublishingIdentifiers.requestID()
        pendingActionRequestIDs[key] = requestID
        return requestID
    }

    private func requireCredential() throws -> PublishingCredential {
        guard let credential else {
            throw PublishingClientError.missingCredential
        }
        return credential
    }

    private func requireArticleID() throws -> String {
        guard let articleID, !articleID.isEmpty else {
            throw PublishingClientError.invalidResponse
        }
        return articleID
    }

    private func makeClient() throws -> PublishingClient {
        let text = serverURLText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard let url = URL(string: text) else {
            throw PublishingClientError.invalidBaseURL
        }
        return try PublishingClient(baseURL: url)
    }

    private func shouldDiscardPendingRequest(_ error: Error) -> Bool {
        guard let apiError = error as? PublishingAPIError else {
            return false
        }
        return apiError.statusCode < 500
    }

    private func run(
        _ operation: @MainActor () async throws -> Void
    ) async {
        guard !isBusy else {
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            try await operation()
        } catch {
            statusMessage = error.localizedDescription
            hasError = true
        }
    }
}

private extension PublishVisibility {
    var publishingVisibility: PublishingVisibility {
        switch self {
        case .publicArticle:
            .publicArticle
        case .unlisted:
            .unlisted
        }
    }
}

private enum PublishingServerSettings {
    private static let key = "StudyNotes.Publishing.ServerURL"

    static func load() -> String {
        UserDefaults.standard.string(forKey: key)
            ?? "http://127.0.0.1:8090"
    }

    static func save(_ value: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
