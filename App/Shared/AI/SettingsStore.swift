import Foundation
import StudyCore
import Observation
import Security

@MainActor
@Observable
public final class SettingsStore {
    public var apiKey: String = ""
    public var model: String = "deepseek-chat"
    public var baseURLString: String = "https://api.deepseek.com"

    public init() {
        load()
    }

    public func load() {
        apiKey = (try? Keychain.read(key: "deepseek.apiKey")) ?? ""
        model = UserDefaults.standard.string(forKey: "deepseek.model") ?? "deepseek-chat"
        baseURLString = UserDefaults.standard.string(forKey: "deepseek.baseURL") ?? "https://api.deepseek.com"
    }

    public func save() throws {
        if apiKey.isEmpty {
            try? Keychain.delete(key: "deepseek.apiKey")
        } else {
            try Keychain.write(apiKey, key: "deepseek.apiKey")
        }
        UserDefaults.standard.set(model, forKey: "deepseek.model")
        UserDefaults.standard.set(baseURLString, forKey: "deepseek.baseURL")
    }

    public var hasAPIKey: Bool {
        !apiKey.isEmpty
    }

    public func makeClient() -> DeepSeekClient? {
        guard !apiKey.isEmpty, let url = URL(string: baseURLString) else { return nil }
        return DeepSeekClient(config: DeepSeekConfig(apiKey: apiKey, baseURL: url, model: model))
    }
}

public enum KeychainError: LocalizedError {
    case status(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .status(let code):
            return "钥匙串操作失败（OSStatus \(code)）"
        }
    }
}

public enum Keychain {
    private static let service = "study-notes"

    static func write(_ value: String, key: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    static func read(key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
        guard let data = item as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }
}
