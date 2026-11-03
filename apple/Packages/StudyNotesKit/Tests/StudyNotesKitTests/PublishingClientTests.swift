import CryptoKit
import Foundation
import Testing
@testable import StudyNotesKit

@Suite("Publishing client", .serialized)
struct PublishingClientTests {
    @Test("Ed25519 signs the canonical request and registration never uploads d")
    func signatureAndRegistration() async throws {
        let credential = try PublishingCredential.generate()
        let fixedDate = Date(timeIntervalSince1970: 1_760_000_000)
        let captured = Locked<URLRequest?>(nil)
        let configuration = makeConfiguration { request in
            captured.set(request)
            #expect(
                request.value(
                    forHTTPHeaderField: "x-studynotes-registration-secret"
                ) == "registration-secret-123"
            )
            return (
                201,
                ["Content-Type": "application/json"],
                Data(
                    """
                    {"kid":"\(credential.kid)","status":"ACTIVE","createdAt":"2026-11-03T00:00:00.000Z"}
                    """.utf8
                )
            )
        }
        let client = try PublishingClient(
            baseURL: URL(string: "https://publish.example")!,
            transport: transport(configuration),
            clock: { fixedDate },
            nonce: { "nonce-1234567890" }
        )

        let response = try await client.registerKey(
            credential: credential,
            registrationSecret: "registration-secret-123"
        )
        #expect(response.status == "ACTIVE")
        let request = try #require(captured.value)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/api/v1/publish-keys")
        let body = try #require(requestBody(request))
        let bodyText = try #require(String(data: body, encoding: .utf8))
        #expect(!bodyText.contains("\"d\""))
        #expect(!bodyText.contains(credential.privateKeyBase64URL))
        #expect(bodyText.contains(credential.publicKeyX))
        #expect(
            request.value(forHTTPHeaderField: "x-studynotes-signature") == nil
        )

        let signedURL = URL(
            string: "https://publish.example/api/v1/publish?z=2&a=1&a=0"
        )!
        let signedBody = Data("{\"title\":\"你好\"}".utf8)
        let headers = try PublishingCanonicalSigner.headers(
            method: "post",
            url: signedURL,
            body: signedBody,
            credential: credential,
            timestamp: "1760000000",
            nonce: "nonce-1234567890"
        )
        let bodyHash = try #require(
            headers["x-studynotes-content-sha256"]
        )
        let canonical = PublishingCanonicalSigner.canonicalString(
            method: "POST",
            url: signedURL,
            timestamp: "1760000000",
            nonce: "nonce-1234567890",
            bodyHash: bodyHash
        )
        #expect(
            canonical.contains(
                "/api/v1/publish?a=0&a=1&z=2\n1760000000"
            )
        )
        let publicKeyData = try #require(
            PublishingBase64URL.decode(credential.publicKeyX)
        )
        let publicKey = try Curve25519.Signing.PublicKey(
            rawRepresentation: publicKeyData
        )
        let signatureText = try #require(
            headers["x-studynotes-signature"]
        )
        let signatureData = try #require(
            PublishingBase64URL.decode(signatureText)
        )
        #expect(
            publicKey.isValidSignature(
                signatureData,
                for: Data(canonical.utf8)
            )
        )
    }

    @Test("publish maps idempotent responses and exposes version conflicts")
    func publishAndConflict() async throws {
        let credential = try PublishingCredential.generate()
        let requestBox = Locked<[URLRequest]>([])
        let configuration = makeConfiguration { request in
            requestBox.withValue { $0.append(request) }
            let body = requestBody(request).flatMap {
                try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
            }
            if body?["expectedVersion"] as? Int == 1 {
                return (
                    409,
                    ["Content-Type": "application/json"],
                    Data(
                        """
                        {"code":"VERSION_CONFLICT","message":"发布版本冲突","details":{"expectedVersion":1,"currentVersion":2}}
                        """.utf8
                    )
                )
            }
            return (
                200,
                ["Content-Type": "application/json"],
                Data(publishResponseJSON(version: 1, idempotent: true).utf8)
            )
        }
        let client = try makeClient(configuration)
        let request = PublishingRequest(
            requestId: "request-1234567890",
            sourceMaterialId: UUID().uuidString,
            expectedVersion: 0,
            visibility: .publicArticle,
            title: "标题",
            bodyHtml: "<p>正文</p>",
            publishAnnotations: false,
            publishAi: false
        )

        let published = try await client.publish(
            request,
            credential: credential
        )
        #expect(published.idempotent)
        #expect(published.version == 1)
        let signedRequest = try #require(requestBox.value.first)
        let bodyData = try #require(requestBody(signedRequest))
        let bodyHash = try #require(
            signedRequest.value(
                forHTTPHeaderField: "x-studynotes-content-sha256"
            )
        )
        #expect(bodyHash == PublishingCanonicalSigner.bodyHash(bodyData))

        do {
            _ = try await client.publish(
                PublishingRequest(
                    requestId: "request-1234567891",
                    sourceMaterialId: UUID().uuidString,
                    expectedVersion: 1,
                    visibility: .publicArticle,
                    title: "标题",
                    bodyHtml: "<p>正文</p>",
                    publishAnnotations: false,
                    publishAi: false
                ),
                credential: credential
            )
            Issue.record("Expected a version conflict")
        } catch let error as PublishingAPIError {
            #expect(error.code == "VERSION_CONFLICT")
            #expect(error.currentVersion == 2)
        }
    }

    @Test("lifecycle calls preserve signed paths and request versions")
    func lifecycleCalls() async throws {
        let credential = try PublishingCredential.generate()
        let seen = Locked<[(String, String, [String: Any])]>([])
        let configuration = makeConfiguration { request in
            let object = requestBody(request).flatMap {
                try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
            } ?? [:]
            seen.withValue {
                $0.append(
                    (
                        request.httpMethod ?? "",
                        request.url?.path ?? "",
                        object
                    )
                )
            }
            switch request.url?.path {
            case "/api/v1/articles/article123456789012/rollback":
                return json(
                    """
                    {"articleId":"article123456789012","currentVersion":1,"versionId":"version-1","fingerprint":"sha256:abc","idempotent":false}
                    """
                )
            case "/api/v1/articles/article123456789012/visibility",
                 "/api/v1/articles/article123456789012/withdraw":
                return json(
                    """
                    {"articleId":"article123456789012","visibility":"UNLISTED","currentVersion":2,"idempotent":false}
                    """
                )
            default:
                return json(
                    """
                    {"articleId":"article123456789012","deleted":true}
                    """
                )
            }
        }
        let client = try makeClient(configuration)
        let articleID = "article123456789012"

        let rollback = try await client.rollback(
            articleID: articleID,
            input: PublishingRollbackRequest(
                requestId: "rollback-1234567890",
                expectedVersion: 2,
                targetVersion: 1
            ),
            credential: credential
        )
        #expect(rollback.currentVersion == 1)
        _ = try await client.changeVisibility(
            articleID: articleID,
            input: PublishingVisibilityRequest(
                requestId: "visibility-12345678",
                expectedVersion: 1,
                visibility: .unlisted
            ),
            credential: credential
        )
        _ = try await client.withdraw(
            articleID: articleID,
            input: PublishingWithdrawRequest(
                requestId: "withdraw-1234567890",
                expectedVersion: 2
            ),
            credential: credential
        )
        let deleted = try await client.deleteArticle(
            articleID: articleID,
            input: PublishingDeleteRequest(
                requestId: "delete-1234567890",
                expectedVersion: 2
            ),
            credential: credential
        )
        #expect(deleted.deleted)
        let calls = seen.value
        #expect(calls.map { $0.1 } == [
            "/api/v1/articles/\(articleID)/rollback",
            "/api/v1/articles/\(articleID)/visibility",
            "/api/v1/articles/\(articleID)/withdraw",
            "/api/v1/articles/\(articleID)"
        ])
        #expect(calls.allSatisfy { $0.2["requestId"] != nil })
        #expect(calls[0].2["targetVersion"] as? Int == 1)
        #expect(calls[1].2["visibility"] as? String == "UNLISTED")
        #expect(calls[2].2["expectedVersion"] as? Int == 2)
        #expect(calls[3].0 == "DELETE")
    }

    @Test("media upload retries the same object after a transient failure")
    func mediaRetry() async throws {
        let directory = try PublishingTestDirectory()
        defer { directory.remove() }
        let materialID = UUID()
        let fileURL = directory.url.appending(path: "diagram.png")
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x01, 0x02, 0x03])
        try bytes.write(to: fileURL)
        let item = PublishMediaItem(
            id: "diagram.png",
            fileName: "diagram.png",
            localPath: fileURL.path,
            contentHash: ContentFingerprint.sha256(bytes),
            mediaType: "image/png",
            byteCount: bytes.count,
            state: .pendingCredentials
        )
        let credential = try PublishingCredential.generate()
        let tokenBodies = Locked<[[String: Any]]>([])
        let attempts = Locked(0)
        let configuration = makeConfiguration { request in
            if request.url?.path == "/api/v1/media/upload-token" {
                let body = requestBody(request).flatMap {
                    try? JSONSerialization.jsonObject(with: $0)
                        as? [String: Any]
                } ?? [:]
                tokenBodies.withValue { $0.append(body) }
                let objectKey = body["objectKey"] as? String ?? ""
                return json(
                    """
                    {"uploadUrl":"https://upload.example/file","token":"short-lived-token","objectKey":"\(objectKey)","expiresAt":"2026-11-03T01:00:00.000Z","method":"POST"}
                    """
                )
            }
            let attempt = attempts.withValue {
                $0 += 1
                return $0
            }
            if attempt == 1 {
                return (
                    500,
                    ["Content-Type": "application/json"],
                    Data(#"{"error":"temporary"}"#.utf8)
                )
            }
            return (
                200,
                ["Content-Type": "application/json"],
                Data(#"{"key":"ok"}"#.utf8)
            )
        }
        let client = try makeClient(configuration)

        do {
            _ = try await client.uploadMedia(
                item,
                sourceMaterialID: materialID,
                credential: credential
            )
            Issue.record("Expected the first upload to fail")
        } catch let error as PublishingClientError {
            guard case .uploadRejected = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
        let uploaded = try await client.uploadMedia(
            item,
            sourceMaterialID: materialID,
            credential: credential
        )
        #expect(uploaded.reference.contentHash.hasPrefix("sha256:"))
        #expect(uploaded.reference.contentType == "image/png")
        #expect(uploaded.reference.size == bytes.count)
        #expect(tokenBodies.value.count == 2)
        #expect(tokenBodies.value[0]["objectKey"] as? String
            == tokenBodies.value[1]["objectKey"] as? String)
    }

    @Test("request builder hides private layers and submits only uploaded media")
    func requestBuilder() async throws {
        let directory = try PublishingTestDirectory()
        defer { directory.remove() }
        let fileURL = directory.url.appending(path: "image.png")
        let bytes = Data([0x89, 0x50, 0x4E, 0x47])
        try bytes.write(to: fileURL)
        let media = PublishMediaItem(
            id: "image.png",
            fileName: "image.png",
            localPath: fileURL.path,
            contentHash: ContentFingerprint.sha256(bytes),
            mediaType: "image/png",
            byteCount: bytes.count,
            state: .uploaded
        )
        let annotation = PublishedAnnotation(
            id: UUID(),
            quote: "正文",
            note: "私有备注",
            anchor: AnnotationAnchor(kind: .text, blockPath: [0, 1])
        )
        let html = """
        <!doctype html><html><body><article>
        <h1>标题</h1>
        <p>正文 <img alt="图" data-media-key="image.png" src=""></p>
        <section class="published-annotations"><aside class="published-annotation">私有备注</aside></section>
        <details class="study-appendix"><summary>AI</summary>私有 AI</details>
        </article><script>private()</script></body></html>
        """
        let hidden = PublishPreview(
            materialID: UUID(),
            title: "标题",
            html: html,
            contentFingerprint: "hidden",
            includeAnnotations: false,
            includeAI: false,
            annotations: [],
            aiAppendix: nil,
            media: [media],
            mapping: nil
        )
        let uploaded = UploadedPublishingMedia(
            itemID: media.id,
            reference: PublishingMediaReference(
                objectKey: "materials/source/image.png",
                contentHash: "sha256:\(media.contentHash)",
                contentType: "image/png",
                size: media.byteCount,
                reference: "media://image.png"
            )
        )
        let hiddenRequest = try PublishingRequestBuilder.make(
            preview: hidden,
            tags: [" 标签 ", "标签"],
            visibility: .publicArticle,
            expectedVersion: 0,
            articleID: nil,
            uploadedMedia: [uploaded],
            requestID: "preview-12345678"
        )
        #expect(!hiddenRequest.bodyHtml.contains("私有备注"))
        #expect(!hiddenRequest.bodyHtml.contains("私有 AI"))
        #expect(hiddenRequest.bodyHtml.contains("data-object-key="))
        #expect(!hiddenRequest.bodyHtml.contains("data-media-key="))
        #expect(hiddenRequest.publishAnnotations == false)
        #expect(hiddenRequest.annotations == nil)
        #expect(hiddenRequest.aiAppendix == nil)

        let annotationsOnly = PublishPreview(
            materialID: hidden.materialID,
            title: hidden.title,
            html: html,
            contentFingerprint: "annotations",
            includeAnnotations: true,
            includeAI: false,
            annotations: [annotation],
            aiAppendix: "AI 私有内容",
            media: [media],
            mapping: nil
        )
        let annotationRequest = try PublishingRequestBuilder.make(
            preview: annotationsOnly,
            tags: [],
            visibility: .unlisted,
            expectedVersion: 3,
            articleID: "article123456789012",
            uploadedMedia: [uploaded],
            requestID: "preview-12345679"
        )
        #expect(annotationRequest.publishAnnotations)
        #expect(!annotationRequest.publishAi)
        #expect(annotationRequest.annotations?.count == 1)
        #expect(annotationRequest.aiAppendix == nil)
        #expect(!annotationRequest.bodyHtml.contains("私有备注"))
        #expect(annotationRequest.visibility == .unlisted)

        do {
            _ = try PublishingRequestBuilder.make(
                preview: hidden,
                tags: [],
                visibility: .publicArticle,
                expectedVersion: 0,
                articleID: nil,
                uploadedMedia: [],
                requestID: "preview-12345680"
            )
            Issue.record("Expected a missing media error")
        } catch let error as PublishingClientError {
            guard case .missingMediaReference("image.png") = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }

    @Test("credential store is the only persistence seam for a generated key")
    func credentialStore() throws {
        let secretStore = MemorySecretStore()
        let store = KeychainPublishingCredentialStore(
            secretStore: secretStore
        )
        let service = PublishingKeyService(store: store)
        let first = try service.ensureCredential()
        #expect(first.created)
        #expect(try service.current() == first.credential)
        let second = try service.ensureCredential()
        #expect(!second.created)
        #expect(second.credential == first.credential)
        let rotated = try service.rotate()
        #expect(rotated.previous == first.credential)
        #expect(rotated.credential != first.credential)
        #expect(try service.current() == rotated.credential)
        #expect(secretStore.count == 1)
    }
}

private final class PublishingURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (
        (URLRequest) throws -> (Int, [String: String], Data)
    )?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(
                self,
                didFailWithError: PublishingClientError.invalidResponse
            )
            return
        }
        do {
            let (status, headers, data) = try handler(request)
            guard let url = request.url else {
                throw PublishingClientError.invalidResponse
            }
            let response = HTTPURLResponse(
                url: url,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!
            client?.urlProtocol(
                self,
                didReceive: response,
                cacheStoragePolicy: .notAllowed
            )
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func makeConfiguration(
    handler: @escaping (URLRequest) throws -> (
        Int,
        [String: String],
        Data
    )
) -> URLSessionConfiguration {
    PublishingURLProtocol.handler = handler
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [PublishingURLProtocol.self]
    return configuration
}

private func transport(
    _ configuration: URLSessionConfiguration
) -> PublishingClient.Transport {
    let session = URLSession(configuration: configuration)
    return { request in
        try await session.data(for: request)
    }
}

private func makeClient(
    _ configuration: URLSessionConfiguration
) throws -> PublishingClient {
    try PublishingClient(
        baseURL: URL(string: "https://publish.example")!,
        transport: transport(configuration),
        clock: { Date(timeIntervalSince1970: 1_760_000_000) },
        nonce: { "nonce-1234567890" }
    )
}

private func json(
    _ value: String,
    status: Int = 200
) -> (Int, [String: String], Data) {
    (
        status,
        ["Content-Type": "application/json"],
        Data(value.utf8)
    )
}

private func requestBody(_ request: URLRequest) -> Data? {
    if let body = request.httpBody {
        return body
    }
    guard let stream = request.httpBodyStream else {
        return nil
    }
    if stream.streamStatus == .notOpen {
        stream.open()
    }
    defer { stream.close() }
    var data = Data()
    let bufferSize = 4_096
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }
    while stream.streamStatus == .open || stream.streamStatus == .reading {
        let count = stream.read(buffer, maxLength: bufferSize)
        if count < 0 {
            return nil
        }
        if count == 0 {
            break
        }
        data.append(buffer, count: count)
    }
    return data
}

private func publishResponseJSON(
    version: Int,
    idempotent: Bool
) -> String {
    """
    {"articleId":"article123456789012","visibility":"PUBLIC",
     "publicUrl":"https://publish.example/a/article123456789012",
     "unlistedUrl":"https://publish.example/u/token",
     "version":\(version),"versionId":"version-\(version)",
     "fingerprint":"sha256:abc","publishedAt":"2026-11-03T00:00:00.000Z",
     "createdArticle":\(version == 1),"createdVersion":\(version == 1),
     "reusedVersion":\(idempotent),"idempotent":\(idempotent)}
    """
}

private final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) {
        self.stored = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func set(_ value: Value) {
        lock.lock()
        stored = value
        lock.unlock()
    }

    @discardableResult
    func withValue<Result>(
        _ operation: (inout Value) -> Result
    ) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return operation(&stored)
    }
}

private final class MemorySecretStore:
    SecretStoring,
    @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return values.count
    }

    func save(_ secret: String, account: String) throws {
        lock.lock()
        values[account] = secret
        lock.unlock()
    }

    func load(account: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[account]
    }

    func delete(account: String) throws {
        lock.lock()
        values.removeValue(forKey: account)
        lock.unlock()
    }
}

private struct PublishingTestDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(
                path: "StudyNotesPublishing-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
