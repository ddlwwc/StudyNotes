import Foundation

public struct PublishingClient: Sendable {
    public typealias Transport = @Sendable (URLRequest) async throws -> (
        Data,
        URLResponse
    )

    private let baseURL: URL
    private let transport: Transport
    private let clock: @Sendable () -> Date
    private let nonce: @Sendable () -> String

    public init(
        baseURL: URL,
        transport: @escaping Transport = { request in
            try await URLSession.shared.data(for: request)
        },
        clock: @escaping @Sendable () -> Date = { Date() },
        nonce: @escaping @Sendable () -> String = PublishingIdentifiers.nonce
    ) throws {
        guard ["http", "https"].contains(baseURL.scheme?.lowercased() ?? ""),
              baseURL.host != nil else {
            throw PublishingClientError.invalidBaseURL
        }
        self.baseURL = baseURL
        self.transport = transport
        self.clock = clock
        self.nonce = nonce
    }

    public func registerKey(
        credential: PublishingCredential,
        registrationSecret: String
    ) async throws -> PublishingKeyResponse {
        guard registrationSecret.count >= 16 else {
            throw PublishingClientError.invalidRegistrationSecret
        }
        let body = try encode(
            PublishingKeyRegistrationRequest(
                kid: credential.kid,
                publicKeyJwk: credential.publicKeyJWK
            )
        )
        var request = URLRequest(
            url: try endpoint(["api", "v1", "publish-keys"])
        )
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.httpBody = body
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue(
            registrationSecret,
            forHTTPHeaderField: "x-studynotes-registration-secret"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await perform(
            request,
            acceptedStatusCodes: [201],
            as: PublishingKeyResponse.self
        )
    }

    public func revokeKey(
        credential: PublishingCredential
    ) async throws {
        let request = try signedRequest(
            method: "DELETE",
            path: ["api", "v1", "publish-keys", credential.kid],
            body: nil,
            credential: credential
        )
        try await performEmpty(request, acceptedStatusCodes: [204])
    }

    public func createMediaUploadToken(
        request input: PublishingUploadTokenRequest,
        credential: PublishingCredential
    ) async throws -> PublishingUploadTokenResponse {
        let body = try encode(input)
        let request = try signedRequest(
            method: "POST",
            path: ["api", "v1", "media", "upload-token"],
            body: body,
            credential: credential
        )
        return try await perform(
            request,
            acceptedStatusCodes: [200],
            as: PublishingUploadTokenResponse.self
        )
    }

    public func uploadMedia(
        _ item: PublishMediaItem,
        sourceMaterialID: UUID,
        credential: PublishingCredential
    ) async throws -> UploadedPublishingMedia {
        let localURL = URL(fileURLWithPath: item.localPath)
        guard FileManager.default.fileExists(atPath: localURL.path) else {
            throw PublishingClientError.mediaFileMissing(item.fileName)
        }
        let data = try Data(contentsOf: localURL)
        guard (1...(50 * 1_024 * 1_024)).contains(data.count) else {
            throw PublishingClientError.mediaTooLarge(item.fileName)
        }
        let actualHash = ContentFingerprint.sha256(data)
        let expectedHash = item.contentHash.hasPrefix("sha256:")
            ? String(item.contentHash.dropFirst("sha256:".count))
            : item.contentHash
        guard actualHash.caseInsensitiveCompare(expectedHash) == .orderedSame else {
            throw PublishingClientError.mediaFileChanged(item.fileName)
        }
        let objectKey = PublishingObjectKey.make(
            materialID: sourceMaterialID,
            item: item,
            contentHash: actualHash
        )
        let contentHash = "sha256:\(actualHash)"
        let token = try await createMediaUploadToken(
            request: PublishingUploadTokenRequest(
                objectKey: objectKey,
                contentHash: contentHash,
                contentType: item.mediaType,
                size: data.count
            ),
            credential: credential
        )
        guard token.objectKey == objectKey else {
            throw PublishingClientError.invalidResponse
        }
        try await upload(
            data: data,
            fileName: item.fileName,
            contentType: item.mediaType,
            credential: token
        )
        return UploadedPublishingMedia(
            itemID: item.id,
            reference: PublishingMediaReference(
                objectKey: objectKey,
                contentHash: contentHash,
                contentType: item.mediaType,
                size: data.count,
                reference: "media://\(item.fileName)"
            )
        )
    }

    public func publish(
        _ input: PublishingRequest,
        credential: PublishingCredential
    ) async throws -> PublishingResponse {
        let body = try encode(input)
        let request = try signedRequest(
            method: "POST",
            path: ["api", "v1", "publish"],
            body: body,
            credential: credential
        )
        return try await perform(
            request,
            acceptedStatusCodes: [200, 201],
            as: PublishingResponse.self
        )
    }

    public func getStatus(
        articleID: String,
        credential: PublishingCredential
    ) async throws -> PublishingStatusResponse {
        let request = try signedRequest(
            method: "GET",
            path: ["api", "v1", "articles", articleID, "status"],
            body: nil,
            credential: credential
        )
        return try await perform(
            request,
            acceptedStatusCodes: [200],
            as: PublishingStatusResponse.self
        )
    }

    public func changeVisibility(
        articleID: String,
        input: PublishingVisibilityRequest,
        credential: PublishingCredential
    ) async throws -> PublishingVisibilityResponse {
        let body = try encode(input)
        let request = try signedRequest(
            method: "POST",
            path: ["api", "v1", "articles", articleID, "visibility"],
            body: body,
            credential: credential
        )
        return try await perform(
            request,
            acceptedStatusCodes: [200],
            as: PublishingVisibilityResponse.self
        )
    }

    public func withdraw(
        articleID: String,
        input: PublishingWithdrawRequest,
        credential: PublishingCredential
    ) async throws -> PublishingVisibilityResponse {
        let body = try encode(input)
        let request = try signedRequest(
            method: "POST",
            path: ["api", "v1", "articles", articleID, "withdraw"],
            body: body,
            credential: credential
        )
        return try await perform(
            request,
            acceptedStatusCodes: [200],
            as: PublishingVisibilityResponse.self
        )
    }

    public func rollback(
        articleID: String,
        input: PublishingRollbackRequest,
        credential: PublishingCredential
    ) async throws -> PublishingRollbackResponse {
        let body = try encode(input)
        let request = try signedRequest(
            method: "POST",
            path: ["api", "v1", "articles", articleID, "rollback"],
            body: body,
            credential: credential
        )
        return try await perform(
            request,
            acceptedStatusCodes: [200],
            as: PublishingRollbackResponse.self
        )
    }

    public func deleteArticle(
        articleID: String,
        input: PublishingDeleteRequest,
        credential: PublishingCredential
    ) async throws -> PublishingDeleteResponse {
        let body = try encode(input)
        let request = try signedRequest(
            method: "DELETE",
            path: ["api", "v1", "articles", articleID],
            body: body,
            credential: credential
        )
        return try await perform(
            request,
            acceptedStatusCodes: [200],
            as: PublishingDeleteResponse.self
        )
    }

    private func upload(
        data: Data,
        fileName: String,
        contentType: String,
        credential: PublishingUploadTokenResponse
    ) async throws {
        guard let uploadURL = URL(string: credential.uploadUrl) else {
            throw PublishingClientError.invalidResponse
        }
        var request = URLRequest(url: uploadURL)
        request.timeoutInterval = 120
        switch credential.method {
        case .post:
            let boundary = "StudyNotes-\(UUID().uuidString)"
            request.httpMethod = "POST"
            request.httpBody = multipartBody(
                boundary: boundary,
                token: credential.token,
                fileName: fileName,
                contentType: contentType,
                data: data
            )
            request.setValue(
                "multipart/form-data; boundary=\(boundary)",
                forHTTPHeaderField: "Content-Type"
            )
        case .put:
            request.httpMethod = "PUT"
            request.httpBody = data
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            request.setValue(
                "UpToken \(credential.token)",
                forHTTPHeaderField: "Authorization"
            )
        }
        let (responseData, response) = try await transport(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PublishingClientError.invalidResponse
        }
        if (200..<300).contains(httpResponse.statusCode) {
            return
        }
        if httpResponse.statusCode == 614 || uploadErrorCode(responseData) == 614 {
            return
        }
        throw PublishingClientError.uploadRejected(
            httpResponse.statusCode,
            String(data: responseData.prefix(1_000), encoding: .utf8) ?? ""
        )
    }

    private func signedRequest(
        method: String,
        path: [String],
        body: Data?,
        credential: PublishingCredential
    ) throws -> URLRequest {
        let url = try endpoint(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let requestBody = body ?? Data()
        if let body {
            request.httpBody = body
            request.setValue(
                "application/json",
                forHTTPHeaderField: "Content-Type"
            )
        }
        let timestamp = String(
            Int(clock().timeIntervalSince1970)
        )
        let headers = try PublishingCanonicalSigner.headers(
            method: method,
            url: url,
            body: requestBody,
            credential: credential,
            timestamp: timestamp,
            nonce: nonce()
        )
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return request
    }

    private func endpoint(_ path: [String]) throws -> URL {
        var url = baseURL
        for component in path {
            url.append(path: component)
        }
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else {
            throw PublishingClientError.invalidBaseURL
        }
        return url
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private func perform<T: Decodable>(
        _ request: URLRequest,
        acceptedStatusCodes: Set<Int>,
        as type: T.Type
    ) async throws -> T {
        let (data, response) = try await transport(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PublishingClientError.invalidResponse
        }
        guard acceptedStatusCodes.contains(httpResponse.statusCode) else {
            throw apiError(statusCode: httpResponse.statusCode, data: data)
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw PublishingClientError.invalidResponse
        }
    }

    private func performEmpty(
        _ request: URLRequest,
        acceptedStatusCodes: Set<Int>
    ) async throws {
        let (data, response) = try await transport(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PublishingClientError.invalidResponse
        }
        guard acceptedStatusCodes.contains(httpResponse.statusCode) else {
            throw apiError(statusCode: httpResponse.statusCode, data: data)
        }
    }

    private func apiError(
        statusCode: Int,
        data: Data
    ) -> PublishingAPIError {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return PublishingAPIError(
                statusCode: statusCode,
                code: "HTTP_\(statusCode)",
                message: "发布请求失败"
            )
        }
        let details = dictionary["details"] as? [String: Any]
        return PublishingAPIError(
            statusCode: statusCode,
            code: dictionary["code"] as? String ?? "HTTP_\(statusCode)",
            message: dictionary["message"] as? String ?? "发布请求失败",
            expectedVersion: details?["expectedVersion"] as? Int,
            currentVersion: details?["currentVersion"] as? Int
        )
    }

    private func multipartBody(
        boundary: String,
        token: String,
        fileName: String,
        contentType: String,
        data: Data
    ) -> Data {
        var body = Data()
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"token\"\r\n\r\n")
        body.appendUTF8("\(token)\r\n")
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(multipartFileName(fileName))\"\r\n"
        )
        body.appendUTF8("Content-Type: \(contentType)\r\n\r\n")
        body.append(data)
        body.appendUTF8("\r\n--\(boundary)--\r\n")
        return body
    }

    private func multipartFileName(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "_")
            .replacingOccurrences(of: "\r", with: "_")
            .replacingOccurrences(of: "\n", with: "_")
    }

    private func uploadErrorCode(_ data: Data) -> Int? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return nil
        }
        return dictionary["code"] as? Int
    }
}

enum PublishingObjectKey {
    static func make(
        materialID: UUID,
        item: PublishMediaItem,
        contentHash: String
    ) -> String {
        let fileURL = URL(fileURLWithPath: item.fileName)
        let rawExtension = fileURL.pathExtension.lowercased()
        let fileExtension = rawExtension.filter(isASCIIAlphaNumeric)
        let rawName = fileURL.deletingPathExtension().lastPathComponent
        var safeName = rawName.map { character in
            character.isASCII && (character.isLetter || character.isNumber
                || character == "-" || character == "_" || character == ".")
                ? character
                : "-"
        }
        while safeName.first == "-" {
            safeName.removeFirst()
        }
        while safeName.last == "-" {
            safeName.removeLast()
        }
        let base = String(safeName.prefix(120))
        let fileName = base.isEmpty ? "media" : base
        let suffix = fileExtension.isEmpty ? "" : ".\(fileExtension)"
        return "materials/\(materialID.uuidString.lowercased())/\(contentHash.prefix(20))-\(fileName)\(suffix)"
    }

    private static func isASCIIAlphaNumeric(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber)
    }
}

private extension Data {
    mutating func appendUTF8(_ value: String) {
        append(Data(value.utf8))
    }
}
