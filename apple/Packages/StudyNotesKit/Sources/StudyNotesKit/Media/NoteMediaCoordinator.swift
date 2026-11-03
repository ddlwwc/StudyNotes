import Foundation

public struct NoteMediaInsertion: Equatable, Sendable {
    public let item: NoteMediaUploadItem
    public let localURL: URL

    public var reference: NoteMediaReference { item.reference }

    public init(item: NoteMediaUploadItem, localURL: URL) {
        self.item = item
        self.localURL = localURL
    }
}

public enum NoteMediaInsertionDecision: Equatable, Sendable {
    case requiresCellularConfirmation(byteCount: Int)
    case inserted(NoteMediaInsertion)
}

public struct NoteMediaHistoricalLocalFile: Equatable, Sendable {
    public let reference: String
    public let fileURL: URL
    public let size: Int

    public init(reference: String, fileURL: URL, size: Int) {
        self.reference = reference
        self.fileURL = fileURL
        self.size = size
    }
}

public enum NoteMediaCoordinatorError:
    Error,
    Equatable,
    Sendable,
    LocalizedError {
    case invalidBaseURL
    case invalidContentType
    case missingQueuedFile
    case invalidUploadCredential
    case uploadFailed
    case migrationNotConfirmed

    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "笔记媒体服务地址无效。"
        case .invalidContentType:
            "媒体类型必须使用 image、application、audio、video 或 text 前缀。"
        case .missingQueuedFile:
            "待上传媒体文件不存在。"
        case .invalidUploadCredential:
            "上传凭据与待上传对象不匹配。"
        case .uploadFailed:
            "七牛云媒体上传失败。"
        case .migrationNotConfirmed:
            "迁移历史媒体前必须明确确认。"
        }
    }
}

public actor NoteMediaCoordinator {
    public typealias ServerTransport = BearerHTTPClient.Transport
    public typealias UploadTransport = @Sendable (
        URLRequest,
        @escaping @Sendable (Double) -> Void
    ) async throws -> (Data, URLResponse)
    public typealias DownloadTransport = @Sendable (URL) async throws -> (
        Data,
        URLResponse
    )

    private var baseURL: URL
    private let credentialStore: KeychainNoteMediaCredentialStore
    private let uploadQueue: NoteMediaUploadQueue
    private let cache: NoteMediaCache
    private let serverTransport: ServerTransport
    private let uploadTransport: UploadTransport
    private let downloadTransport: DownloadTransport
    private var activeUploads: [UUID: ActiveUpload] = [:]

    private struct ActiveUpload {
        let token: UUID
        let task: Task<NoteMediaUploadItem, Error>
    }

    public init(
        applicationSupportRoot: URL,
        baseURL: URL,
        credentialStore: KeychainNoteMediaCredentialStore =
            KeychainNoteMediaCredentialStore(),
        serverTransport: @escaping ServerTransport = { request in
            try await URLSession.shared.data(for: request)
        },
        uploadTransport: UploadTransport? = nil,
        downloadTransport: @escaping DownloadTransport = { url in
            try await URLSession.shared.data(from: url)
        }
    ) throws {
        try Self.validate(baseURL: baseURL)
        self.baseURL = baseURL
        self.credentialStore = credentialStore
        uploadQueue = try NoteMediaUploadQueue(
            applicationSupportRoot: applicationSupportRoot
        )
        cache = try NoteMediaCache(
            applicationSupportRoot: applicationSupportRoot
        )
        self.serverTransport = serverTransport
        self.uploadTransport = uploadTransport ?? {
            request,
            progress in
            try await Self.performUpload(request, progress: progress)
        }
        self.downloadTransport = downloadTransport
    }

    public func configure(baseURL: URL) throws {
        try Self.validate(baseURL: baseURL)
        self.baseURL = baseURL
    }

    public func items() async -> [NoteMediaUploadItem] {
        await uploadQueue.items()
    }

    public func localFileURL(for id: UUID) async -> URL? {
        await uploadQueue.localFileURL(for: id)
    }

    public func previewFileURL(
        for reference: NoteMediaReference
    ) async -> URL? {
        if let item = await uploadQueue.items().first(
            where: { $0.reference == reference }
        ), let url = await uploadQueue.localFileURL(for: item.id) {
            return url
        }
        let cached = await cache.fileURL(for: reference)
        return FileManager.default.fileExists(atPath: cached.path)
            ? cached
            : nil
    }

    public func prepareInsertion(
        fileAt sourceURL: URL,
        contentType: String,
        connection: NoteMediaConnection,
        confirmedCellularUpload: Bool
    ) async throws -> NoteMediaInsertionDecision {
        let byteCount = try fileByteCount(at: sourceURL)
        let contentType = try normalizedContentType(contentType)
        if try NoteMediaPolicy.requiresCellularConfirmation(
            byteCount: byteCount,
            connection: connection
        ), !confirmedCellularUpload {
            return .requiresCellularConfirmation(byteCount: byteCount)
        }
        let item = try await uploadQueue.enqueue(
            fileAt: sourceURL,
            contentType: contentType
        )
        guard let localURL = await uploadQueue.localFileURL(for: item.id) else {
            throw NoteMediaCoordinatorError.missingQueuedFile
        }
        return .inserted(
            NoteMediaInsertion(item: item, localURL: localURL)
        )
    }

    public func status() async throws -> NoteMediaStatusResponse {
        try await makeClient().status()
    }

    public func upload(id: UUID) async throws -> NoteMediaUploadItem {
        if let activeUpload = activeUploads[id] {
            return try await activeUpload.task.value
        }
        let token = UUID()
        let task = Task {
            try await self.performUpload(id: id)
        }
        activeUploads[id] = ActiveUpload(token: token, task: task)
        do {
            let item = try await task.value
            if activeUploads[id]?.token == token {
                activeUploads[id] = nil
            }
            return item
        } catch {
            if activeUploads[id]?.token == token {
                activeUploads[id] = nil
            }
            throw error
        }
    }

    public func retry(id: UUID) async throws -> NoteMediaUploadItem {
        try await uploadQueue.retry(id: id)
        return try await upload(id: id)
    }

    public func cancel(id: UUID) async throws {
        let upload = activeUploads[id]
        upload?.task.cancel()
        guard let item = await uploadQueue.item(id: id) else {
            return
        }
        switch item.state {
        case .waiting, .uploading, .failed:
            try await uploadQueue.cancel(id: id)
        case .cancelled, .uploaded:
            break
        }
        _ = try? await upload?.task.value
        if let upload, activeUploads[id]?.token == upload.token {
            activeUploads[id] = nil
        }
    }

    public func pendingReferences(
        in markdown: String
    ) async -> [NoteMediaReference] {
        let referencedKeys = NoteMediaReferenceScanner.objectKeys(in: markdown)
        return await uploadQueue.items().compactMap { item in
            guard referencedKeys.contains(item.reference.objectKey),
                  item.state != .uploaded else {
                return nil
            }
            return item.reference
        }
    }

    public func hasPendingMedia(in markdown: String) async -> Bool {
        !(await pendingReferences(in: markdown)).isEmpty
    }

    public func downloadURL(
        for reference: NoteMediaReference
    ) async throws -> NoteMediaDownloadURLResponse {
        try await makeClient().downloadURL(for: reference)
    }

    public func viewableURL(
        for reference: NoteMediaReference
    ) async throws -> URL {
        let cachedURL = await cache.fileURL(for: reference)
        if FileManager.default.fileExists(atPath: cachedURL.path) {
            return cachedURL
        }
        let response = try await downloadURL(for: reference)
        guard let url = URL(string: response.url) else {
            throw NoteMediaClientError.invalidResponse
        }
        let (data, remoteResponse) = try await downloadTransport(url)
        guard let httpResponse = remoteResponse as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw NoteMediaCoordinatorError.uploadFailed
        }
        try NoteMediaPolicy.validate(byteCount: data.count)
        try await cache.write(data, for: reference)
        return await cache.fileURL(for: reference)
    }

    public func inlineDataURL(
        for reference: NoteMediaReference
    ) async throws -> URL {
        let fileURL = try await viewableURL(for: reference)
        let data = try Data(contentsOf: fileURL)
        try NoteMediaPolicy.validate(byteCount: data.count)
        let fileExtension = URL(fileURLWithPath: reference.objectKey)
            .pathExtension
        let contentType = NoteMediaPolicy.contentType(
            forFileExtension: fileExtension
        ) ?? "application/octet-stream"
        guard let url = URL(
            string: "data:\(contentType);base64,\(data.base64EncodedString())"
        ) else {
            throw NoteMediaClientError.invalidResponse
        }
        return url
    }

    public func inlineURLMap(
        for objectKeys: Set<String>
    ) async -> [String: URL] {
        let maximumInlineByteCount = 64 * 1_024 * 1_024
        var result: [String: URL] = [:]
        var totalByteCount = 0
        for objectKey in objectKeys {
            guard let reference = try? NoteMediaReference(objectKey: objectKey),
                  let fileURL = await previewFileURL(for: reference),
                  let size = try? fileURL.resourceValues(
                      forKeys: [.fileSizeKey]
                  ).fileSize,
                  totalByteCount + size <= maximumInlineByteCount,
                  let data = try? Data(contentsOf: fileURL) else {
                continue
            }
            totalByteCount += size
            let contentType = NoteMediaPolicy.contentType(
                forFileExtension: fileURL.pathExtension
            ) ?? "application/octet-stream"
            guard let url = URL(
                string: "data:\(contentType);base64,\(data.base64EncodedString())"
            ) else {
                continue
            }
            result[objectKey] = url
        }
        return result
    }

    public func cacheSize() async throws -> Int {
        try await cache.size()
    }

    public func clearCache() async throws {
        try await cache.clear()
    }

    public func scan(
        sourceId: String,
        currentMarkdown: String,
        historicalMarkdowns: [String],
        historicalLocalMedia: [NoteMediaHistoricalLocalReference] = []
    ) async throws -> NoteMediaReferenceScanResponse {
        let currentKeys = NoteMediaReferenceScanner.objectKeys(
            in: currentMarkdown
        )
        let historicalKeys = Set(
            historicalMarkdowns.flatMap {
                NoteMediaReferenceScanner.objectKeys(in: $0)
            }
        )
        let references = currentKeys.sorted().map {
            NoteMediaReferenceInput(
                scope: .current,
                objectKey: $0,
                reference: "media://qiniu/\($0)"
            )
        } + historicalKeys.subtracting(currentKeys).sorted().map {
            NoteMediaReferenceInput(
                scope: .history,
                objectKey: $0,
                reference: "media://qiniu/\($0)"
            )
        }
        return try await makeClient().scanReferences(
            NoteMediaReferenceScanRequest(
                sourceId: sourceId,
                references: references,
                historicalLocalMedia: historicalLocalMedia
            )
        )
    }

    public func cleanup(
        objectKeys: [String],
        confirmed: Bool
    ) async throws -> NoteMediaCleanupResponse {
        try await makeClient().cleanup(
            NoteMediaCleanupRequest(
                objectKeys: objectKeys,
                confirmed: confirmed
            )
        )
    }

    public static func historicalLocalFiles(
        in directory: URL
    ) throws -> [NoteMediaHistoricalLocalFile] {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return []
        }
        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: keys
        ) else {
            return []
        }
        var files: [NoteMediaHistoricalLocalFile] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(keys))
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true else {
                continue
            }
            let directoryPath = directory.standardizedFileURL.path
            let filePath = url.standardizedFileURL.path
            guard filePath.hasPrefix(directoryPath + "/") else {
                continue
            }
            let relativePath = String(
                filePath.dropFirst(directoryPath.count + 1)
            )
            files.append(
                NoteMediaHistoricalLocalFile(
                    reference: relativePath,
                    fileURL: url,
                    size: values.fileSize ?? 0
                )
            )
        }
        return files.sorted { $0.reference < $1.reference }
    }

    public func migrateHistoricalLocalFiles(
        _ files: [NoteMediaHistoricalLocalFile],
        confirmed: Bool
    ) async throws -> [NoteMediaReference] {
        guard confirmed else {
            throw NoteMediaCoordinatorError.migrationNotConfirmed
        }
        var references: [NoteMediaReference] = []
        for file in files {
            guard let contentType = NoteMediaPolicy.contentType(
                forFileExtension: file.fileURL.pathExtension
            ) else {
                continue
            }
            let decision = try await prepareInsertion(
                fileAt: file.fileURL,
                contentType: contentType,
                connection: .unknown,
                confirmedCellularUpload: false
            )
            if case let .inserted(insertion) = decision {
                references.append(insertion.reference)
            }
        }
        return references
    }

    private func performUpload(id: UUID) async throws -> NoteMediaUploadItem {
        guard let item = await uploadQueue.item(id: id) else {
            throw NoteMediaUploadQueueError.itemNotFound
        }
        guard let sourceURL = await uploadQueue.localFileURL(for: id) else {
            throw NoteMediaCoordinatorError.missingQueuedFile
        }
        let data = try Data(contentsOf: sourceURL)
        try NoteMediaPolicy.validate(byteCount: data.count)
        guard data.count == item.byteCount,
              "sha256:\(ContentFingerprint.sha256(data))"
                == item.contentHash else {
            throw NoteMediaUploadQueueError.contentChanged
        }
        try Task.checkCancellation()

        do {
            let client = try makeClient()
            let credential = try await client.uploadCredential(
                NoteMediaUploadCredentialRequest(
                    contentHash: item.contentHash,
                    contentType: item.contentType,
                    size: item.byteCount
                )
            )
            guard credential.objectKey == item.reference.objectKey else {
                throw NoteMediaCoordinatorError.invalidUploadCredential
            }
            if credential.alreadyExists,
               let completed = try? await client.completeUpload(
                   NoteMediaCompleteRequest(objectKey: credential.objectKey)
               ),
               completeResponse(
                   completed,
                   matches: item
               ) {
                try await uploadQueue.updateProgress(id: id, progress: 1)
                try await uploadQueue.markUploaded(id: id)
                return await uploadQueue.item(id: id) ?? item
            }
            let request = try uploadRequest(
                credential: credential,
                item: item,
                data: data
            )
            try await uploadQueue.updateProgress(id: id, progress: 0)
            let (_, response) = try await uploadTransport(request) {
                progress in
                Task {
                    try? await self.uploadQueue.updateProgress(
                        id: id,
                        progress: progress
                    )
                }
            }
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode) else {
                throw NoteMediaCoordinatorError.uploadFailed
            }
            try Task.checkCancellation()
            try await uploadQueue.updateProgress(id: id, progress: 1)
            let completed = try await client.completeUpload(
                NoteMediaCompleteRequest(objectKey: credential.objectKey)
            )
            guard completeResponse(completed, matches: item) else {
                throw NoteMediaClientError.invalidResponse
            }
            try await uploadQueue.markUploaded(id: id)
            return await uploadQueue.item(id: id) ?? item
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if let current = await uploadQueue.item(id: id),
               current.state != .cancelled,
               current.state != .uploaded {
                try? await uploadQueue.markFailed(
                    id: id,
                    message: error.localizedDescription
                )
            }
            throw error
        }
    }

    private func makeClient() throws -> NoteMediaClient {
        let credential = try credentialStore.load()
        return try NoteMediaClient(
            baseURL: baseURL,
            credential: credential,
            transport: serverTransport
        )
    }

    private func uploadRequest(
        credential: NoteMediaUploadCredentialResponse,
        item: NoteMediaUploadItem,
        data: Data
    ) throws -> URLRequest {
        guard let uploadURL = URL(string: credential.uploadUrl) else {
            throw NoteMediaCoordinatorError.invalidUploadCredential
        }
        var request = URLRequest(url: uploadURL)
        request.httpMethod = credential.method.rawValue
        request.timeoutInterval = 120
        switch credential.method {
        case .put:
            request.httpBody = data
            request.setValue(
                "UpToken \(credential.token)",
                forHTTPHeaderField: "Authorization"
            )
            request.setValue(
                item.contentType,
                forHTTPHeaderField: "Content-Type"
            )
        case .post:
            let boundary = "StudyNotes-\(UUID().uuidString)"
            request.setValue(
                "multipart/form-data; boundary=\(boundary)",
                forHTTPHeaderField: "Content-Type"
            )
            request.httpBody = multipartBody(
                boundary: boundary,
                token: credential.token,
                item: item,
                data: data
            )
        }
        return request
    }

    private func multipartBody(
        boundary: String,
        token: String,
        item: NoteMediaUploadItem,
        data: Data
    ) -> Data {
        var body = Data()
        func append(_ value: String) {
            body.append(Data(value.utf8))
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"token\"\r\n\r\n")
        append("\(token)\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"key\"\r\n\r\n")
        append("\(item.reference.objectKey)\r\n")
        append("--\(boundary)\r\n")
        append(
            "Content-Disposition: form-data; name=\"file\"; "
                + "filename=\"\(item.sourceFileName)\"\r\n"
        )
        append("Content-Type: \(item.contentType)\r\n\r\n")
        body.append(data)
        append("\r\n--\(boundary)--\r\n")
        return body
    }

    private func fileByteCount(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(
            atPath: url.path
        )
        guard let value = attributes[.size] as? NSNumber else {
            throw CocoaError(.fileReadUnknown)
        }
        return value.intValue
    }

    private func completeResponse(
        _ response: NoteMediaCompleteResponse,
        matches item: NoteMediaUploadItem
    ) -> Bool {
        response.objectKey == item.reference.objectKey
            && response.contentHash == item.contentHash
            && response.contentType == item.contentType
            && response.size == item.byteCount
    }

    private func normalizedContentType(_ value: String) throws -> String {
        let value = value
            .split(separator: ";", maxSplits: 1)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        guard value.utf8.count <= 128,
              ["image", "application", "audio", "video", "text"]
                .contains(where: { value.hasPrefix("\($0)/") }) else {
            throw NoteMediaCoordinatorError.invalidContentType
        }
        return value
    }

    private static func validate(baseURL: URL) throws {
        guard ["http", "https"].contains(
            baseURL.scheme?.lowercased() ?? ""
        ),
            baseURL.host != nil else {
            throw NoteMediaCoordinatorError.invalidBaseURL
        }
    }

    private static func performUpload(
        _ request: URLRequest,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> (Data, URLResponse) {
        guard let body = request.httpBody else {
            throw NoteMediaCoordinatorError.uploadFailed
        }
        let delegate = NoteMediaUploadProgressDelegate(progress: progress)
        return try await URLSession.shared.upload(
            for: request,
            from: body,
            delegate: delegate
        )
    }
}

private final class NoteMediaUploadProgressDelegate:
    NSObject,
    URLSessionTaskDelegate,
    @unchecked Sendable {
    private let progress: @Sendable (Double) -> Void

    init(progress: @escaping @Sendable (Double) -> Void) {
        self.progress = progress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else {
            return
        }
        progress(
            min(
                max(
                    Double(totalBytesSent)
                        / Double(totalBytesExpectedToSend),
                    0
                ),
                1
            )
        )
    }
}
