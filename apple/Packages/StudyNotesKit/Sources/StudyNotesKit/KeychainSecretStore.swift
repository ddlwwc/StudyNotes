import Foundation
import Security

public protocol SecretStoring: Sendable {
    func save(_ secret: String, account: String) throws
    func load(account: String) throws -> String?
    func delete(account: String) throws
}

public struct KeychainSecretStore: SecretStoring {
    private let service: String

    public init(service: String = "com.studynotes.ai-provider") {
        self.service = service
    }

    public func save(_ secret: String, account: String) throws {
        let data = Data(secret.utf8)
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(
            query as CFDictionary,
            attributes as CFDictionary
        )
        if status == errSecSuccess {
            return
        }
        guard status == errSecItemNotFound else {
            throw KeychainSecretError.status(status)
        }
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let insertStatus = SecItemAdd(insert as CFDictionary, nil)
        guard insertStatus == errSecSuccess else {
            throw KeychainSecretError.status(insertStatus)
        }
    }

    public func load(account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess,
              let data = result as? Data else {
            throw KeychainSecretError.status(status)
        }
        return String(data: data, encoding: .utf8)
    }

    public func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainSecretError.status(status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

public enum KeychainSecretError: Error, Equatable, Sendable, LocalizedError {
    case status(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .status(let status):
            "钥匙串操作失败（\(status)）。"
        }
    }
}
