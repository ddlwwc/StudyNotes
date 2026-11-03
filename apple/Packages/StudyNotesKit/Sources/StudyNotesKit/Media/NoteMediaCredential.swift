import Foundation

public struct NoteMediaCredential: Equatable, Sendable {
    public let secret: String

    public init(secret: String) {
        self.secret = secret
    }

    var isValid: Bool {
        guard (32...256).contains(secret.utf8.count) else {
            return false
        }
        return secret.utf8.allSatisfy {
            ($0 >= 0x30 && $0 <= 0x39)
                || ($0 >= 0x41 && $0 <= 0x5a)
                || ($0 >= 0x61 && $0 <= 0x7a)
                || $0 == 0x5f
                || $0 == 0x2d
        }
    }
}

extension NoteMediaCredential: CustomStringConvertible {
    public var description: String {
        "NoteMediaCredential(secret: <redacted>)"
    }
}

public struct KeychainNoteMediaCredentialStore: Sendable {
    private static let account = "note-media-bearer"
    private let secretStore: any SecretStoring

    public init(
        secretStore: any SecretStoring = KeychainSecretStore(
            service: "com.studynotes.note-media"
        )
    ) {
        self.secretStore = secretStore
    }

    public func load() throws -> NoteMediaCredential? {
        guard let secret = try secretStore.load(account: Self.account) else {
            return nil
        }
        let credential = NoteMediaCredential(secret: secret)
        guard credential.isValid else {
            throw BearerHTTPClientError.invalidCredential
        }
        return credential
    }

    public func save(_ credential: NoteMediaCredential) throws {
        guard credential.isValid else {
            throw BearerHTTPClientError.invalidCredential
        }
        try secretStore.save(credential.secret, account: Self.account)
    }

    public func delete() throws {
        try secretStore.delete(account: Self.account)
    }
}

public enum BearerHTTPClientError:
    Error,
    Equatable,
    Sendable,
    LocalizedError {
    case missingCredential
    case invalidCredential

    public var errorDescription: String? {
        switch self {
        case .missingCredential:
            "尚未配置笔记媒体 Bearer 密钥。"
        case .invalidCredential:
            "笔记媒体 Bearer 密钥无效。"
        }
    }
}

public struct BearerHTTPClient: Sendable {
    public typealias Transport = @Sendable (URLRequest) async throws -> (
        Data,
        URLResponse
    )

    private let credential: NoteMediaCredential?
    private let transport: Transport

    public init(
        credential: NoteMediaCredential?,
        transport: @escaping Transport = { request in
            try await URLSession.shared.data(for: request)
        }
    ) {
        self.credential = credential
        self.transport = transport
    }

    public func send(
        _ request: URLRequest
    ) async throws -> (Data, URLResponse) {
        guard let credential else {
            throw BearerHTTPClientError.missingCredential
        }
        guard credential.isValid else {
            throw BearerHTTPClientError.invalidCredential
        }
        var request = request
        request.setValue(
            "Bearer \(credential.secret)",
            forHTTPHeaderField: "Authorization"
        )
        return try await transport(request)
    }
}
