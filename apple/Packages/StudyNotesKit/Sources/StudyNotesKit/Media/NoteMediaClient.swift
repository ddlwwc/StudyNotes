import Foundation

public struct NoteMediaAPIError:
    Error,
    Equatable,
    Sendable,
    LocalizedError {
    public let statusCode: Int
    public let code: String
    public let message: String

    public init(statusCode: Int, code: String, message: String) {
        self.statusCode = statusCode
        self.code = code
        self.message = message
    }

    public var errorDescription: String? {
        "\(message)（HTTP \(statusCode)，\(code)）"
    }
}

public enum NoteMediaClientError:
    Error,
    Equatable,
    Sendable,
    LocalizedError {
    case invalidBaseURL
    case invalidRequest
    case invalidResponse
    case cleanupNotConfirmed

    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "笔记媒体服务地址无效。"
        case .invalidRequest:
            "笔记媒体请求不符合服务端契约。"
        case .invalidResponse:
            "笔记媒体服务返回了无效响应。"
        case .cleanupNotConfirmed:
            "清理媒体对象前必须明确确认。"
        }
    }
}

public struct NoteMediaClient: Sendable {
    private let baseURL: URL
    private let bearer: BearerHTTPClient

    public var insecureHTTPWarning: String? {
        guard baseURL.scheme?.lowercased() == "http" else {
            return nil
        }
        return "当前媒体服务使用 HTTP，Bearer 密钥可能在传输中被截获。"
    }

    public init(
        baseURL: URL,
        credential: NoteMediaCredential?,
        transport: @escaping BearerHTTPClient.Transport = { request in
            try await URLSession.shared.data(for: request)
        }
    ) throws {
        try Self.validate(baseURL: baseURL)
        self.baseURL = baseURL
        bearer = BearerHTTPClient(
            credential: credential,
            transport: transport
        )
    }

    public init(baseURL: URL, bearer: BearerHTTPClient) throws {
        try Self.validate(baseURL: baseURL)
        self.baseURL = baseURL
        self.bearer = bearer
    }

    public func status() async throws -> NoteMediaStatusResponse {
        try await perform(
            request(
                method: "GET",
                path: ["api", "v1", "library-media", "status"]
            ),
            acceptedStatusCodes: [200, 503]
        )
    }

    public func uploadCredential(
        _ input: NoteMediaUploadCredentialRequest
    ) async throws -> NoteMediaUploadCredentialResponse {
        try NoteMediaPolicy.validate(byteCount: input.size)
        guard Self.isSHA256(input.contentHash),
              Self.isValidContentType(input.contentType) else {
            throw NoteMediaClientError.invalidRequest
        }
        let response: NoteMediaUploadCredentialResponse = try await perform(
            request(
                method: "POST",
                path: ["api", "v1", "library-media", "upload-token"],
                body: input
            )
        )
        guard (try? NoteMediaReference(objectKey: response.objectKey)) != nil,
              !response.token.isEmpty,
              let uploadURL = URL(string: response.uploadUrl),
              ["http", "https"].contains(uploadURL.scheme?.lowercased() ?? ""),
              uploadURL.host != nil,
              response.expiresAt > Date() else {
            throw NoteMediaClientError.invalidResponse
        }
        return response
    }

    public func completeUpload(
        _ input: NoteMediaCompleteRequest
    ) async throws -> NoteMediaCompleteResponse {
        let response: NoteMediaCompleteResponse = try await perform(
            request(
                method: "POST",
                path: ["api", "v1", "library-media", "complete"],
                body: input
            )
        )
        guard response.objectKey == input.objectKey,
              response.status == "READY",
              (try? NoteMediaReference(objectKey: response.objectKey)) != nil else {
            throw NoteMediaClientError.invalidResponse
        }
        return response
    }

    public func downloadURL(
        for reference: NoteMediaReference
    ) async throws -> NoteMediaDownloadURLResponse {
        let response: NoteMediaDownloadURLResponse = try await perform(
            request(
                method: "POST",
                path: ["api", "v1", "library-media", "read-url"],
                body: NoteMediaDownloadURLRequest(
                    objectKey: reference.objectKey
                )
            )
        )
        guard let url = URL(string: response.url),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil,
              response.expiresAt > Date() else {
            throw NoteMediaClientError.invalidResponse
        }
        return response
    }

    public func scanReferences(
        _ input: NoteMediaReferenceScanRequest
    ) async throws -> NoteMediaReferenceScanResponse {
        guard (1...128).contains(input.sourceId.count),
              input.references.count <= 5_000,
              input.historicalLocalMedia.count <= 5_000,
              input.references.allSatisfy({
                  (try? NoteMediaReference(objectKey: $0.objectKey)) != nil
                      && (1...1_024).contains($0.reference.count)
              }),
              input.historicalLocalMedia.allSatisfy({
                  (1...1_024).contains($0.reference.count)
                      && (0...NoteMediaPolicy.maximumByteCount)
                          .contains($0.size)
              }) else {
            throw NoteMediaClientError.invalidRequest
        }
        return try await perform(
            request(
                method: "POST",
                path: ["api", "v1", "library-media", "scan"],
                body: input
            )
        )
    }

    public func cleanup(
        _ input: NoteMediaCleanupRequest
    ) async throws -> NoteMediaCleanupResponse {
        guard input.confirmed else {
            throw NoteMediaClientError.cleanupNotConfirmed
        }
        guard (1...1_000).contains(input.objectKeys.count),
              input.objectKeys.allSatisfy({
                  (try? NoteMediaReference(objectKey: $0)) != nil
              }) else {
            throw NoteMediaClientError.invalidRequest
        }
        return try await perform(
            request(
                method: "POST",
                path: ["api", "v1", "library-media", "cleanup"],
                body: input
            )
        )
    }

    private func request<T: Encodable>(
        method: String,
        path: [String],
        body: T
    ) throws -> URLRequest {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try request(
            method: method,
            path: path,
            bodyData: encoder.encode(body)
        )
    }

    private func request(
        method: String,
        path: [String],
        bodyData: Data? = nil
    ) throws -> URLRequest {
        var url = baseURL
        for component in path {
            url.append(path: component)
        }
        try Self.validate(baseURL: url)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bodyData {
            request.httpBody = bodyData
            request.setValue(
                "application/json",
                forHTTPHeaderField: "Content-Type"
            )
        }
        return request
    }

    private func perform<T: Decodable>(
        _ request: URLRequest,
        acceptedStatusCodes: Set<Int> = Set(200..<300)
    ) async throws -> T {
        let (data, response) = try await bearer.send(request)
        guard let response = response as? HTTPURLResponse else {
            throw NoteMediaClientError.invalidResponse
        }
        guard acceptedStatusCodes.contains(response.statusCode) else {
            throw apiError(statusCode: response.statusCode, data: data)
        }
        do {
            return try Self.decoder().decode(T.self, from: data)
        } catch {
            throw NoteMediaClientError.invalidResponse
        }
    }

    private func apiError(
        statusCode: Int,
        data: Data
    ) -> NoteMediaAPIError {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return NoteMediaAPIError(
                statusCode: statusCode,
                code: "HTTP_\(statusCode)",
                message: "笔记媒体请求失败"
            )
        }
        return NoteMediaAPIError(
            statusCode: statusCode,
            code: dictionary["code"] as? String ?? "HTTP_\(statusCode)",
            message: dictionary["message"] as? String ?? "笔记媒体请求失败"
        )
    }

    private static func validate(baseURL: URL) throws {
        guard ["http", "https"].contains(
            baseURL.scheme?.lowercased() ?? ""
        ),
            baseURL.host != nil else {
            throw NoteMediaClientError.invalidBaseURL
        }
    }

    private static func isSHA256(_ value: String) -> Bool {
        let prefix = "sha256:"
        guard value.hasPrefix(prefix) else {
            return false
        }
        let digest = value.dropFirst(prefix.count)
        return digest.count == 64
            && digest.allSatisfy {
                $0.isASCII && ($0.isNumber || ("a"..."f").contains($0))
            }
    }

    private static func isValidContentType(_ value: String) -> Bool {
        guard (1...128).contains(value.utf8.count) else {
            return false
        }
        return ["image", "application", "audio", "video", "text"]
            .contains { value.hasPrefix("\($0)/") }
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date =
                (try? Date(
                    value,
                    strategy: Date.ISO8601FormatStyle(
                        includingFractionalSeconds: true
                    )
                ))
                ?? (try? Date(
                    value,
                    strategy: Date.ISO8601FormatStyle()
                )) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid ISO 8601 date."
                )
            }
            return date
        }
        return decoder
    }
}
