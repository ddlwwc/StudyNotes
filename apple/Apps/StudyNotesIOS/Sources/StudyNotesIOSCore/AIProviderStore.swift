import Foundation
import Security

public struct KeychainStore: Sendable {
    private let service: String

    public init(service: String = "com.studynotes.ai") {
        self.service = service
    }

    public func save(
        apiKey: String,
        account: String
    ) throws {
        let data = Data(apiKey.utf8)
        let baseQuery = Self.baseQuery(service: service, account: account)
        SecItemDelete(baseQuery as CFDictionary)

        var insertQuery = baseQuery
        insertQuery[kSecValueData as String] = data
        insertQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(insertQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw StudyNotesIOSError.keychain(status)
        }
    }

    public func read(
        account: String
    ) throws -> String? {
        var query = Self.baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw StudyNotesIOSError.keychain(status)
        }
        guard let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public func delete(account: String) throws {
        let query = Self.baseQuery(service: service, account: account)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StudyNotesIOSError.keychain(status)
        }
    }

    static func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
    }
}

public actor AIProviderStore {
    private static let storageKey = "StudyNotesIOS.aiProviders"

    private let userDefaults: UserDefaults
    private let keychain: KeychainStore
    private let encoder = StudyNotesFileSupport.encoder()
    private let decoder = StudyNotesFileSupport.decoder()

    public init(
        userDefaults: UserDefaults = .standard,
        keychain: KeychainStore = KeychainStore()
    ) {
        self.userDefaults = userDefaults
        self.keychain = keychain
    }

    public func loadProviders() -> [AIProvider] {
        guard let data = userDefaults.data(forKey: Self.storageKey),
              let providers = try? decoder.decode([AIProvider].self, from: data),
              !providers.isEmpty else {
            let defaults = [
                AIProvider(
                    name: "DeepSeek",
                    baseURL: "https://api.deepseek.com/v1",
                    modelID: "deepseek-chat"
                )
            ]
            try? persist(defaults)
            return defaults
        }
        return providers
    }

    public func upsert(_ provider: AIProvider, apiKey: String?) throws {
        var providers = loadProviders()
        if let index = providers.firstIndex(where: { $0.id == provider.id }) {
            providers[index] = provider
        } else {
            providers.append(provider)
        }
        try persist(providers)
        if let apiKey {
            let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                try keychain.delete(account: provider.id.uuidString)
            } else {
                try keychain.save(
                    apiKey: trimmed,
                    account: provider.id.uuidString
                )
            }
        }
    }

    public func delete(_ providerID: UUID) throws {
        try keychain.delete(account: providerID.uuidString)
        let providers = loadProviders().filter { $0.id != providerID }
        try persist(providers)
    }

    public func apiKey(for providerID: UUID) throws -> String? {
        try keychain.read(account: providerID.uuidString)
    }

    public func hasAPIKey(for providerID: UUID) -> Bool {
        (try? keychain.read(account: providerID.uuidString))?.isEmpty == false
    }

    private func persist(_ providers: [AIProvider]) throws {
        let data = try encoder.encode(providers)
        userDefaults.set(data, forKey: Self.storageKey)
    }
}
