import CryptoKit
import Foundation

public protocol PublishingCredentialStoring: Sendable {
    func load() throws -> PublishingCredential?
    func save(_ credential: PublishingCredential) throws
    func delete() throws
}

public struct PublishingCredential: Codable, Equatable, Sendable {
    public let kid: String
    public let publicKeyX: String
    let privateKeyBase64URL: String

    public static func generate() throws -> PublishingCredential {
        let privateKey = Curve25519.Signing.PrivateKey()
        return try PublishingCredential(
            privateKeyRepresentation: privateKey.rawRepresentation
        )
    }

    init(privateKeyRepresentation: Data) throws {
        guard privateKeyRepresentation.count == 32 else {
            throw PublishingClientError.invalidCredential
        }
        let privateKey: Curve25519.Signing.PrivateKey
        do {
            privateKey = try Curve25519.Signing.PrivateKey(
                rawRepresentation: privateKeyRepresentation
            )
        } catch {
            throw PublishingClientError.invalidCredential
        }
        let publicKey = privateKey.publicKey.rawRepresentation
        let publicX = PublishingBase64URL.encode(publicKey)
        let digest = SHA256.hash(data: publicKey)
            .map { String(format: "%02x", $0) }
            .joined()
        self.kid = "mac-\(digest.prefix(40))"
        self.publicKeyX = publicX
        self.privateKeyBase64URL = PublishingBase64URL.encode(
            privateKey.rawRepresentation
        )
    }

    public var publicKeyJWK: PublishingPublicKeyJWK {
        PublishingPublicKeyJWK(x: publicKeyX, kid: kid)
    }

    func signingPrivateKey() throws -> Curve25519.Signing.PrivateKey {
        guard let data = PublishingBase64URL.decode(privateKeyBase64URL),
              data.count == 32 else {
            throw PublishingClientError.invalidCredential
        }
        do {
            return try Curve25519.Signing.PrivateKey(rawRepresentation: data)
        } catch {
            throw PublishingClientError.invalidCredential
        }
    }

    func validated() throws -> PublishingCredential {
        let privateKey = try signingPrivateKey()
        let expectedX = PublishingBase64URL.encode(
            privateKey.publicKey.rawRepresentation
        )
        guard expectedX == publicKeyX else {
            throw PublishingClientError.invalidCredential
        }
        return self
    }
}

public struct KeychainPublishingCredentialStore: PublishingCredentialStoring {
    private static let account = "ed25519-publishing-credential"

    private let secretStore: any SecretStoring

    public init(
        secretStore: any SecretStoring = KeychainSecretStore(
            service: "com.studynotes.publishing"
        )
    ) {
        self.secretStore = secretStore
    }

    public func load() throws -> PublishingCredential? {
        guard let value = try secretStore.load(account: Self.account),
              let data = value.data(using: .utf8) else {
            return nil
        }
        let decoder = JSONDecoder()
        return try decoder.decode(PublishingCredential.self, from: data)
            .validated()
    }

    public func save(_ credential: PublishingCredential) throws {
        let credential = try credential.validated()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(credential)
        guard let value = String(data: data, encoding: .utf8) else {
            throw PublishingClientError.invalidCredential
        }
        try secretStore.save(value, account: Self.account)
    }

    public func delete() throws {
        try secretStore.delete(account: Self.account)
    }
}

public struct PublishingKeyService: Sendable {
    public let store: any PublishingCredentialStoring

    public init(store: any PublishingCredentialStoring) {
        self.store = store
    }

    public func current() throws -> PublishingCredential? {
        try store.load()
    }

    public func ensureCredential() throws -> (
        credential: PublishingCredential,
        created: Bool
    ) {
        if let credential = try store.load() {
            return (credential, false)
        }
        let credential = try PublishingCredential.generate()
        try store.save(credential)
        return (credential, true)
    }

    public func rotate() throws -> (
        previous: PublishingCredential?,
        credential: PublishingCredential
    ) {
        let previous = try store.load()
        let credential = try PublishingCredential.generate()
        try store.save(credential)
        return (previous, credential)
    }
}

enum PublishingBase64URL {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }
}
