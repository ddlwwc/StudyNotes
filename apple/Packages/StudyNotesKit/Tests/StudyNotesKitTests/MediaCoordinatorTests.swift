import Foundation
import Testing
import StudyNotesKit

@Suite("Media coordinator", .serialized)
struct MediaCoordinatorTests {
    @Test("cellular uploads above 10MB require explicit confirmation")
    func cellularConfirmation() async throws {
        let directory = try MediaTestDirectory()
        defer { directory.remove() }
        let source = directory.url.appending(path: "large.bin")
        try Data(repeating: 1, count: 10 * 1_024 * 1_024 + 1)
            .write(to: source)
        let coordinator = try makeCoordinator(directory: directory.url)

        let pending = try await coordinator.prepareInsertion(
            fileAt: source,
            contentType: "application/octet-stream",
            connection: .cellular,
            confirmedCellularUpload: false
        )

        #expect(
            pending == .requiresCellularConfirmation(
                byteCount: 10 * 1_024 * 1_024 + 1
            )
        )
        #expect(await coordinator.items().isEmpty)

        let inserted = try await coordinator.prepareInsertion(
            fileAt: source,
            contentType: "application/octet-stream",
            connection: .cellular,
            confirmedCellularUpload: true
        )
        guard case let .inserted(insertion) = inserted else {
            Issue.record("Expected insertion after confirmation")
            return
        }
        #expect(insertion.reference.objectKey.hasPrefix("library-media/"))
        #expect(FileManager.default.fileExists(atPath: insertion.localURL.path))
        #expect(insertion.localURL != source)
    }

    @Test("upload obtains a token, uploads bytes, and verifies completion")
    func uploadLifecycle() async throws {
        let directory = try MediaTestDirectory()
        defer { directory.remove() }
        let bytes = Data("coordinator".utf8)
        let source = directory.url.appending(path: "note.txt")
        try bytes.write(to: source)
        let credentialStore = KeychainNoteMediaCredentialStore(
            secretStore: MediaMemorySecretStore()
        )
        try credentialStore.save(
            NoteMediaCredential(secret: "shared-secret-0123456789abcdefghijklmn")
        )
        let capturedUpload = MediaLocked<URLRequest?>(nil)
        let contentHash =
            "sha256:\(ContentFingerprint.sha256(bytes))"
        let reference = try NoteMediaReference.make(
            data: bytes,
            fileExtension: "txt"
        )
        let coordinator = try NoteMediaCoordinator(
            applicationSupportRoot: directory.url,
            baseURL: URL(string: "https://media.example")!,
            credentialStore: credentialStore,
            serverTransport: { request in
                let payload: String
                switch request.url?.lastPathComponent {
                case "upload-token":
                    payload = """
                    {"uploadUrl":"https://upload.example/file",
                     "token":"upload-token","objectKey":"\(reference.objectKey)",
                     "expiresAt":"2099-11-03T01:00:00.000Z",
                     "method":"POST","alreadyExists":false}
                    """
                case "complete":
                    payload = """
                    {"objectKey":"\(reference.objectKey)","status":"READY",
                     "contentHash":"\(contentHash)",
                     "contentType":"text/plain","size":\(bytes.count)}
                    """
                default:
                    Issue.record("Unexpected server path")
                    payload = "{}"
                }
                return (
                    Data(payload.utf8),
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"]
                    )!
                )
            },
            uploadTransport: { request, progress in
                capturedUpload.set(request)
                progress(0.5)
                progress(1)
                return (
                    Data("{}".utf8),
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                )
            }
        )
        let prepared = try await coordinator.prepareInsertion(
            fileAt: source,
            contentType: "text/plain",
            connection: .wifi,
            confirmedCellularUpload: false
        )
        guard case let .inserted(insertion) = prepared else {
            Issue.record("Expected insertion")
            return
        }

        let uploaded = try await coordinator.upload(id: insertion.item.id)
        let request = try #require(capturedUpload.value)
        let body = try #require(request.httpBody)

        #expect(uploaded.state == .uploaded)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://upload.example/file")
        #expect(String(decoding: body, as: UTF8.self).contains("upload-token"))
        #expect(
            String(decoding: body, as: UTF8.self)
                .contains(reference.objectKey)
        )
    }

    @Test("queue and cache survive coordinator recreation")
    func restartAndCache() async throws {
        let directory = try MediaTestDirectory()
        defer { directory.remove() }
        let data = Data("cached-media".utf8)
        let source = directory.url.appending(path: "cached.txt")
        try data.write(to: source)
        let credentialStore = KeychainNoteMediaCredentialStore(
            secretStore: MediaMemorySecretStore()
        )
        try credentialStore.save(
            NoteMediaCredential(secret: "shared-secret-0123456789abcdefghijklmn")
        )
        let downloadCount = MediaLocked(0)
        let serverTransport: NoteMediaCoordinator.ServerTransport = {
            request in
            let payload = """
            {"url":"https://media.example/read",
             "expiresAt":"2099-11-03T01:00:00.000Z"}
            """
            if request.url?.lastPathComponent != "read-url" {
                Issue.record("unexpected request \(request.url as Any)")
            }
            return (
                Data(payload.utf8),
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
            )
        }
        let downloadTransport:
            NoteMediaCoordinator.DownloadTransport = { url in
                downloadCount.set(downloadCount.value + 1)
                return (
                    data,
                    HTTPURLResponse(
                        url: url,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                )
            }
        let first = try NoteMediaCoordinator(
            applicationSupportRoot: directory.url,
            baseURL: URL(string: "https://media.example")!,
            credentialStore: credentialStore,
            serverTransport: serverTransport,
            downloadTransport: downloadTransport
        )
        let inserted = try await first.prepareInsertion(
            fileAt: source,
            contentType: "text/plain",
            connection: .wifi,
            confirmedCellularUpload: false
        )
        guard case let .inserted(insertion) = inserted else {
            Issue.record("Expected insertion")
            return
        }

        let second = try NoteMediaCoordinator(
            applicationSupportRoot: directory.url,
            baseURL: URL(string: "https://media.example")!,
            credentialStore: credentialStore,
            serverTransport: serverTransport,
            downloadTransport: downloadTransport
        )
        #expect(await second.items().map(\.id) == [insertion.item.id])

        let cached = try await second.viewableURL(
            for: insertion.reference
        )
        let cachedAgain = try await second.viewableURL(
            for: insertion.reference
        )
        #expect(try Data(contentsOf: cached) == data)
        #expect(cachedAgain == cached)
        #expect(downloadCount.value == 1)
        #expect(try await second.cacheSize() == data.count)
    }

    @Test("scan splits current and historical scopes and cleanup needs confirmation")
    func scanAndConfirmedCleanup() async throws {
        let directory = try MediaTestDirectory()
        defer { directory.remove() }
        let credentialStore = KeychainNoteMediaCredentialStore(
            secretStore: MediaMemorySecretStore()
        )
        try credentialStore.save(
            NoteMediaCredential(secret: "shared-secret-0123456789abcdefghijklmn")
        )
        let current = try NoteMediaReference.make(
            data: Data("current".utf8),
            fileExtension: "txt"
        )
        let historical = try NoteMediaReference.make(
            data: Data("history".utf8),
            fileExtension: "txt"
        )
        let requestBody = MediaLocked<[String: Any]?>(nil)
        let coordinator = try NoteMediaCoordinator(
            applicationSupportRoot: directory.url,
            baseURL: URL(string: "https://media.example")!,
            credentialStore: credentialStore,
            serverTransport: { request in
                if request.url?.lastPathComponent == "scan" {
                    requestBody.set(
                        request.httpBody.flatMap {
                            try? JSONSerialization.jsonObject(with: $0)
                                as? [String: Any]
                        }
                    )
                    let payload = """
                    {"sourceId":"note-1",
                     "summary":{"currentCount":1,"historyCount":1,
                     "totalSize":0,"missingCount":0,
                     "historicalLocalCount":1,"historicalLocalSize":12},
                     "media":[]}
                    """
                    return (
                        Data(payload.utf8),
                        HTTPURLResponse(
                            url: request.url!,
                            statusCode: 200,
                            httpVersion: nil,
                            headerFields: nil
                        )!
                    )
                }
                let payload = """
                {"queued":[],"skipped":[{"objectKey":"\(current.objectKey)",
                 "reason":"REFERENCED"}]}
                """
                return (
                    Data(payload.utf8),
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                )
            }
        )

        let scan = try await coordinator.scan(
            sourceId: "note-1",
            currentMarkdown: current.stringValue,
            historicalMarkdowns: [historical.stringValue],
            historicalLocalMedia: [
                NoteMediaHistoricalLocalReference(
                    reference: "legacy/file.png",
                    size: 12
                )
            ]
        )
        let references = try #require(
            requestBody.value?["references"] as? [[String: Any]]
        )

        #expect(scan.summary.currentCount == 1)
        #expect(references.compactMap {
            $0["scope"] as? String
        }.sorted() == ["CURRENT", "HISTORY"])
        await #expect(throws: NoteMediaClientError.cleanupNotConfirmed) {
            _ = try await coordinator.cleanup(
                objectKeys: [current.objectKey],
                confirmed: false
            )
        }
        let cleanup = try await coordinator.cleanup(
            objectKeys: [current.objectKey],
            confirmed: true
        )
        #expect(cleanup.skipped.first?.reason == .referenced)
    }

    @Test("failed uploads remain retryable")
    func failedUploadRetries() async throws {
        let directory = try MediaTestDirectory()
        defer { directory.remove() }
        let bytes = Data("retry".utf8)
        let source = directory.url.appending(path: "retry.txt")
        try bytes.write(to: source)
        let credentialStore = KeychainNoteMediaCredentialStore(
            secretStore: MediaMemorySecretStore()
        )
        try credentialStore.save(
            NoteMediaCredential(secret: "shared-secret-0123456789abcdefghijklmn")
        )
        let reference = try NoteMediaReference.make(
            data: bytes,
            fileExtension: "txt"
        )
        let contentHash =
            "sha256:\(ContentFingerprint.sha256(bytes))"
        let shouldFail = MediaLocked(true)
        let coordinator = try NoteMediaCoordinator(
            applicationSupportRoot: directory.url,
            baseURL: URL(string: "https://media.example")!,
            credentialStore: credentialStore,
            serverTransport: { request in
                let payload: String
                if request.url?.lastPathComponent == "upload-token" {
                    payload = """
                    {"uploadUrl":"https://upload.example/file",
                     "token":"token","objectKey":"\(reference.objectKey)",
                     "expiresAt":"2099-11-03T01:00:00.000Z",
                     "method":"POST","alreadyExists":false}
                    """
                } else {
                    payload = """
                    {"objectKey":"\(reference.objectKey)","status":"READY",
                     "contentHash":"\(contentHash)",
                     "contentType":"text/plain","size":\(bytes.count)}
                    """
                }
                return (
                    Data(payload.utf8),
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                )
            },
            uploadTransport: { request, _ in
                if shouldFail.value {
                    throw NoteMediaCoordinatorError.uploadFailed
                }
                return (
                    Data("{}".utf8),
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                )
            }
        )
        let prepared = try await coordinator.prepareInsertion(
            fileAt: source,
            contentType: "text/plain",
            connection: .wifi,
            confirmedCellularUpload: false
        )
        guard case let .inserted(insertion) = prepared else {
            Issue.record("Expected insertion")
            return
        }

        await #expect(throws: NoteMediaCoordinatorError.self) {
            _ = try await coordinator.upload(id: insertion.item.id)
        }
        #expect(
            await coordinator.items().first?.state
                == .failed(message: "七牛云媒体上传失败。")
        )

        shouldFail.set(false)
        let retried = try await coordinator.retry(id: insertion.item.id)
        #expect(retried.state == .uploaded)
    }

    @Test("historical scan does not follow symbolic links")
    func historicalScanSkipsSymlinks() throws {
        let directory = try MediaTestDirectory()
        defer { directory.remove() }
        let legacy = directory.url.appending(
            path: "source/media",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: legacy,
            withIntermediateDirectories: true
        )
        try Data("legacy".utf8).write(
            to: legacy.appending(path: "image.png")
        )
        let secret = directory.url.appending(path: "secret.txt")
        try Data("do-not-upload".utf8).write(to: secret)
        try FileManager.default.createSymbolicLink(
            at: legacy.appending(path: "linked.txt"),
            withDestinationURL: secret
        )

        let files = try NoteMediaCoordinator.historicalLocalFiles(
            in: legacy
        )

        #expect(files.map(\.reference) == ["image.png"])
    }

    @Test("already existing content completes without uploading again")
    func existingContentSkipsUpload() async throws {
        let directory = try MediaTestDirectory()
        defer { directory.remove() }
        let bytes = Data("existing".utf8)
        let source = directory.url.appending(path: "existing.txt")
        try bytes.write(to: source)
        let credentialStore = KeychainNoteMediaCredentialStore(
            secretStore: MediaMemorySecretStore()
        )
        try credentialStore.save(
            NoteMediaCredential(secret: "shared-secret-0123456789abcdefghijklmn")
        )
        let reference = try NoteMediaReference.make(
            data: bytes,
            fileExtension: "txt"
        )
        let contentHash =
            "sha256:\(ContentFingerprint.sha256(bytes))"
        let uploadCount = MediaLocked(0)
        let coordinator = try NoteMediaCoordinator(
            applicationSupportRoot: directory.url,
            baseURL: URL(string: "https://media.example")!,
            credentialStore: credentialStore,
            serverTransport: { request in
                let payload: String
                if request.url?.lastPathComponent == "upload-token" {
                    payload = """
                    {"uploadUrl":"https://upload.example/file",
                     "token":"token","objectKey":"\(reference.objectKey)",
                     "expiresAt":"2099-11-03T01:00:00.000Z",
                     "method":"POST","alreadyExists":true}
                    """
                } else {
                    payload = """
                    {"objectKey":"\(reference.objectKey)","status":"READY",
                     "contentHash":"\(contentHash)",
                     "contentType":"text/plain","size":\(bytes.count)}
                    """
                }
                return (
                    Data(payload.utf8),
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                )
            },
            uploadTransport: { request, _ in
                uploadCount.set(uploadCount.value + 1)
                return (
                    Data("{}".utf8),
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 500,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                )
            }
        )
        let prepared = try await coordinator.prepareInsertion(
            fileAt: source,
            contentType: "text/plain",
            connection: .wifi,
            confirmedCellularUpload: false
        )
        guard case let .inserted(insertion) = prepared else {
            Issue.record("Expected insertion")
            return
        }

        let uploaded = try await coordinator.upload(id: insertion.item.id)

        #expect(uploaded.state == .uploaded)
        #expect(uploadCount.value == 0)
    }

    private func makeCoordinator(
        directory: URL
    ) throws -> NoteMediaCoordinator {
        let credentialStore = KeychainNoteMediaCredentialStore(
            secretStore: MediaMemorySecretStore()
        )
        try credentialStore.save(
            NoteMediaCredential(secret: "shared-secret-0123456789abcdefghijklmn")
        )
        return try NoteMediaCoordinator(
            applicationSupportRoot: directory,
            baseURL: URL(string: "https://media.example")!,
            credentialStore: credentialStore,
            serverTransport: { request in
                (
                    Data("{}".utf8),
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                )
            }
        )
    }
}
