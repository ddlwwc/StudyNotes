import Foundation
import Testing
import StudyNotesKit

@Suite("Media HTTP client", .serialized)
struct MediaHTTPClientTests {
    @Test("credential store keeps the Bearer key behind SecretStoring")
    func credentialStore() throws {
        let secrets = MediaMemorySecretStore()
        let store = KeychainNoteMediaCredentialStore(secretStore: secrets)
        #expect(try store.load() == nil)

        try store.save(NoteMediaCredential(secret: "shared-secret-0123456789abcdefghijklmn"))

        #expect(
            try store.load()?.secret
                == "shared-secret-0123456789abcdefghijklmn"
        )
        try store.delete()
        #expect(try store.load() == nil)
    }

    @Test("Bearer client rejects a missing key without sending a request")
    func missingBearer() async {
        let sent = MediaLocked(false)
        let client = BearerHTTPClient(
            credential: nil,
            transport: { request in
                sent.set(true)
                return (
                    Data(),
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                )
            }
        )

        await #expect(throws: BearerHTTPClientError.self) {
            _ = try await client.send(URLRequest(
                url: URL(string: "https://media.example/status")!
            ))
        }
        #expect(!sent.value)
    }

    @Test("Bearer client adds the key to every request and replaces stale auth")
    func bearerHeader() async throws {
        let captured = MediaLocked<URLRequest?>(nil)
        let client = BearerHTTPClient(
            credential: NoteMediaCredential(secret: "shared-secret-0123456789abcdefghijklmn"),
            transport: { request in
                captured.set(request)
                return (
                    Data(),
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                )
            }
        )
        var request = URLRequest(
            url: URL(string: "https://media.example/status")!
        )
        request.setValue("stale", forHTTPHeaderField: "Authorization")

        _ = try await client.send(request)

        #expect(
            captured.value?.value(forHTTPHeaderField: "Authorization")
                == "Bearer shared-secret-0123456789abcdefghijklmn"
        )
    }

    @Test("Bearer client rejects whitespace injection and redacts the key")
    func bearerValidation() async {
        let credential = NoteMediaCredential(
            secret: "shared-secret\r\nX-Injected: yes"
        )
        let sent = MediaLocked(false)
        let client = BearerHTTPClient(
            credential: credential,
            transport: { request in
                sent.set(true)
                return (
                    Data(),
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                )
            }
        )

        await #expect(throws: BearerHTTPClientError.invalidCredential) {
            _ = try await client.send(URLRequest(
                url: URL(string: "https://media.example/status")!
            ))
        }
        #expect(!sent.value)
        #expect(!String(describing: credential).contains("shared-secret"))
    }

    @Test("upload token uses the library-media contract")
    func uploadTokenContract() async throws {
        let reference = try NoteMediaReference.make(
            data: Data("hello".utf8),
            fileExtension: "txt"
        )
        let captured = MediaLocked<URLRequest?>(nil)
        let client = try NoteMediaClient(
            baseURL: URL(string: "https://media.example")!,
            credential: NoteMediaCredential(secret: "shared-secret-0123456789abcdefghijklmn"),
            transport: { request in
                captured.set(request)
                return (
                    Data(
                        """
                        {"uploadUrl":"https://upload.example/file",
                         "token":"token","objectKey":"\(reference.objectKey)",
                         "expiresAt":"2099-11-03T01:00:00.000Z",
                         "method":"POST","alreadyExists":false}
                        """.utf8
                    ),
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"]
                    )!
                )
            }
        )

        let response = try await client.uploadCredential(
            NoteMediaUploadCredentialRequest(
                contentHash:
                    "sha256:\(ContentFingerprint.sha256(Data("hello".utf8)))",
                contentType: "text/plain",
                size: 5
            )
        )
        let body = try #require(
            captured.value?.httpBody.flatMap {
                try JSONSerialization.jsonObject(with: $0)
                    as? [String: Any]
            }
        )

        #expect(response.objectKey == reference.objectKey)
        #expect(!response.alreadyExists)
        #expect(captured.value?.httpMethod == "POST")
        #expect(
            captured.value?.url?.path
                == "/api/v1/library-media/upload-token"
        )
        #expect(
            Set(body.keys) == Set(["contentHash", "contentType", "size"])
        )
    }

    @Test("complete and read-url use exact library-media payloads")
    func completeAndReadURLContracts() async throws {
        let reference = try NoteMediaReference.make(
            data: Data("hello".utf8),
            fileExtension: "txt"
        )
        let captured = MediaLocked<[URLRequest]>([])
        let client = try NoteMediaClient(
            baseURL: URL(string: "https://media.example")!,
            credential: NoteMediaCredential(secret: "shared-secret-0123456789abcdefghijklmn"),
            transport: { request in
                captured.set(captured.value + [request])
                let payload: String
                switch request.url?.lastPathComponent {
                case "complete":
                    payload = """
                    {"objectKey":"\(reference.objectKey)","status":"READY",
                     "contentHash":"sha256:abc","contentType":"text/plain",
                     "size":5}
                    """
                default:
                    payload = """
                    {"url":"https://media.example/read",
                     "expiresAt":"2099-11-03T01:00:00.000Z"}
                    """
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
        )

        let completed = try await client.completeUpload(
            NoteMediaCompleteRequest(objectKey: reference.objectKey)
        )
        let read = try await client.downloadURL(for: reference)
        let requests = captured.value
        let completeBody = try #require(
            requests.first?.httpBody.flatMap {
                try JSONSerialization.jsonObject(with: $0)
                    as? [String: Any]
            }
        )
        let readBody = try #require(
            requests.last?.httpBody.flatMap {
                try JSONSerialization.jsonObject(with: $0)
                    as? [String: Any]
            }
        )

        #expect(completed.status == "READY")
        #expect(completed.objectKey == reference.objectKey)
        #expect(read.url == "https://media.example/read")
        #expect(requests.map(\.url?.path) == [
            "/api/v1/library-media/complete",
            "/api/v1/library-media/read-url"
        ])
        #expect(completeBody.keys.sorted() == ["objectKey"])
        #expect(readBody.keys.sorted() == ["objectKey"])
    }

    @Test("scan and cleanup use the exact library-media contract")
    func scanAndCleanupContracts() async throws {
        let reference = try NoteMediaReference.make(
            data: Data("scan".utf8),
            fileExtension: "png"
        )
        let captured = MediaLocked<[URLRequest]>([])
        let client = try NoteMediaClient(
            baseURL: URL(string: "https://media.example")!,
            credential: NoteMediaCredential(secret: "shared-secret-0123456789abcdefghijklmn"),
            transport: { request in
                captured.set(captured.value + [request])
                let payload: String
                switch request.url?.lastPathComponent {
                case "scan":
                    payload = """
                    {"sourceId":"source-1",
                     "summary":{"currentCount":1,"historyCount":1,
                     "totalSize":10,"missingCount":0,
                     "historicalLocalCount":1,"historicalLocalSize":20},
                     "media":[{"objectKey":"\(reference.objectKey)",
                     "scopes":["CURRENT","HISTORY"],
                     "references":["media://qiniu/\(reference.objectKey)"],
                     "status":"READY","contentHash":"sha256:abc",
                     "contentType":"image/png","size":10}]}
                    """
                default:
                    payload = """
                    {"queued":[{"objectKey":"\(reference.objectKey)",
                     "availableAt":"2099-11-03T01:00:00.000Z"}],
                     "skipped":[{"objectKey":"\(reference.objectKey)",
                     "reason":"REFERENCED"}]}
                    """
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
        )

        let scan = try await client.scanReferences(
            NoteMediaReferenceScanRequest(
                sourceId: "source-1",
                references: [
                    NoteMediaReferenceInput(
                        scope: .current,
                        objectKey: reference.objectKey,
                        reference: reference.stringValue
                    )
                ],
                historicalLocalMedia: [
                    NoteMediaHistoricalLocalReference(
                        reference: "legacy/a.png",
                        size: 20
                    )
                ]
            )
        )
        let cleanup = try await client.cleanup(
            NoteMediaCleanupRequest(
                objectKeys: [reference.objectKey],
                confirmed: true
            )
        )
        let requests = captured.value
        let scanBody = try #require(
            requests.first?.httpBody.flatMap {
                try JSONSerialization.jsonObject(with: $0)
                    as? [String: Any]
            }
        )
        let cleanupBody = try #require(
            requests.last?.httpBody.flatMap {
                try JSONSerialization.jsonObject(with: $0)
                    as? [String: Any]
            }
        )

        #expect(scan.summary.historicalLocalSize == 20)
        #expect(cleanup.skipped.first?.reason == .referenced)
        #expect(requests.map(\.url?.path) == [
            "/api/v1/library-media/scan",
            "/api/v1/library-media/cleanup"
        ])
        #expect(
            Set(scanBody.keys) == Set([
                "sourceId", "references", "historicalLocalMedia"
            ])
        )
        #expect(Set(cleanupBody.keys) == Set(["objectKeys", "confirmed"]))
    }

    @Test("status uses the configured URL and exposes an HTTP warning")
    func statusAndInsecureWarning() async throws {
        let captured = MediaLocked<URLRequest?>(nil)
        let client = try NoteMediaClient(
            baseURL: URL(string: "http://media.example")!,
            credential: NoteMediaCredential(secret: "shared-secret-0123456789abcdefghijklmn"),
            transport: { request in
                captured.set(request)
                return (
                    Data(
                        """
                        {"ok":true,"bucket":"private","domain":"media.example",
                         "uploadUrl":"https://upload.example",
                         "httpWarning":true,"message":"degraded"}
                        """.utf8
                    ),
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"]
                    )!
                )
            }
        )

        let status = try await client.status()

        #expect(status.ok)
        #expect(status.bucket == "private")
        #expect(status.domain == "media.example")
        #expect(status.uploadUrl == "https://upload.example")
        #expect(status.httpWarning)
        #expect(status.message == "degraded")
        #expect(captured.value?.httpMethod == "GET")
        #expect(
            captured.value?.url?.path == "/api/v1/library-media/status"
        )
        #expect(
            captured.value?.value(forHTTPHeaderField: "Authorization")
                == "Bearer shared-secret-0123456789abcdefghijklmn"
        )
        #expect(client.insecureHTTPWarning != nil)
    }
}
