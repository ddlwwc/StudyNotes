import Foundation

@MainActor
public final class WorkspaceTreeExpansionStore {
    private static let key = "StudyNotesMac.directoryExpansion.v1"

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func load(knowledgeBaseID: UUID) -> Set<String>? {
        guard let values = userDefaults.dictionary(
            forKey: Self.key
        ) as? [String: [String]] else {
            return nil
        }
        return values[knowledgeBaseID.uuidString].map(Set.init)
    }

    public func save(
        _ paths: Set<String>,
        knowledgeBaseID: UUID
    ) {
        var values = userDefaults.dictionary(
            forKey: Self.key
        ) as? [String: [String]] ?? [:]
        values[knowledgeBaseID.uuidString] = paths.sorted()
        userDefaults.set(values, forKey: Self.key)
    }
}
