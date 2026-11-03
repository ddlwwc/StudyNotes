import Foundation

/// Stores device-local appearance settings in `UserDefaults`.
///
/// This store intentionally has no iCloud, container URL, or file adapter.
@MainActor
public final class DevicePreferencesStore {
    private static let storageVersion = 1
    private static let readingKey =
        "StudyNotes.DevicePreferences.v\(storageVersion).reading"
    private static let workspaceKey =
        "StudyNotes.DevicePreferences.v\(storageVersion).workspace"

    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func loadReadingPreferences() -> ReadingPreferences {
        decode(
            ReadingPreferences.self,
            forKey: Self.readingKey,
            fallback: ReadingPreferences()
        )
    }

    public func save(readingPreferences: ReadingPreferences) throws {
        try encode(readingPreferences, forKey: Self.readingKey)
    }

    public func loadWorkspacePreferences() -> WorkspacePreferences {
        decode(
            WorkspacePreferences.self,
            forKey: Self.workspaceKey,
            fallback: WorkspacePreferences()
        )
    }

    public func save(workspacePreferences: WorkspacePreferences) throws {
        try encode(workspacePreferences, forKey: Self.workspaceKey)
    }

    public func clear() {
        userDefaults.removeObject(forKey: Self.readingKey)
        userDefaults.removeObject(forKey: Self.workspaceKey)
    }

    private func encode<Value: Encodable>(
        _ value: Value,
        forKey key: String
    ) throws {
        userDefaults.set(try encoder.encode(value), forKey: key)
    }

    private func decode<Value: Decodable>(
        _ type: Value.Type,
        forKey key: String,
        fallback: @autoclosure () -> Value
    ) -> Value {
        guard let data = userDefaults.data(forKey: key),
              let value = try? decoder.decode(type, from: data) else {
            return fallback()
        }
        return value
    }
}
