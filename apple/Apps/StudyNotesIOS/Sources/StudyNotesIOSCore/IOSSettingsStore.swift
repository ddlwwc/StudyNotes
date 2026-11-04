import Foundation
import StudyNotesKit

public typealias IOSReadingPreferences = ReadingPreferences
public typealias IOSReadingTheme = ReadingTheme

public struct IOSSettingsSnapshot: Equatable, Sendable {
    public let readingPreferences: IOSReadingPreferences
    public let publishingServerURL: String
    public let hasMediaKey: Bool

    public init(
        readingPreferences: IOSReadingPreferences,
        publishingServerURL: String,
        hasMediaKey: Bool
    ) {
        self.readingPreferences = readingPreferences
        self.publishingServerURL = publishingServerURL
        self.hasMediaKey = hasMediaKey
    }
}

public struct IOSPublicationDefaults: Equatable, Sendable {
    public let visibilityLabel: String
    public let publishesAnnotations: Bool
    public let publishesAIAppendix: Bool
    public let isPublishingAvailable: Bool

    public init(
        visibilityLabel: String = "未列出",
        publishesAnnotations: Bool = false,
        publishesAIAppendix: Bool = false,
        isPublishingAvailable: Bool = false
    ) {
        self.visibilityLabel = visibilityLabel
        self.publishesAnnotations = publishesAnnotations
        self.publishesAIAppendix = publishesAIAppendix
        self.isPublishingAvailable = isPublishingAvailable
    }
}

@MainActor
public final class IOSSettingsStore {
    public static let defaultPublishingServerURL = "http://127.0.0.1:8090"
    public static let publicationDefaults = IOSPublicationDefaults()

    private static let publishingServerURLKey =
        "StudyNotes.Publishing.ServerURL"
    private static let expandedFolderPathsPrefix =
        "StudyNotes.LibraryTree.Expanded."
    private let userDefaults: UserDefaults
    private let preferences: DevicePreferencesStore

    public let mediaCredentialStore: KeychainNoteMediaCredentialStore

    public init(
        userDefaults: UserDefaults = .standard,
        secretStore: any SecretStoring = KeychainSecretStore(
            service: "com.studynotes.note-media"
        )
    ) {
        self.userDefaults = userDefaults
        mediaCredentialStore = KeychainNoteMediaCredentialStore(
            secretStore: secretStore
        )
        self.preferences = DevicePreferencesStore(userDefaults: userDefaults)
    }

    public func load() -> IOSSettingsSnapshot {
        IOSSettingsSnapshot(
            readingPreferences: preferences.loadReadingPreferences(),
            publishingServerURL: loadPublishingServerURL(),
            hasMediaKey: hasMediaKey()
        )
    }

    public func loadReadingPreferences() -> IOSReadingPreferences {
        preferences.loadReadingPreferences()
    }

    public func save(readingPreferences: IOSReadingPreferences) throws {
        try preferences.save(readingPreferences: readingPreferences)
    }

    public func loadPublishingServerURL() -> String {
        userDefaults.string(forKey: Self.publishingServerURLKey)
            ?? Self.defaultPublishingServerURL
    }

    public func savePublishingServerURL(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        userDefaults.set(trimmed, forKey: Self.publishingServerURLKey)
    }

    public func hasMediaKey() -> Bool {
        (try? mediaCredentialStore.load()) != nil
    }

    public func saveMediaKey(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try removeMediaKey()
        } else {
            try mediaCredentialStore.save(
                NoteMediaCredential(secret: trimmed)
            )
        }
    }

    public func removeMediaKey() throws {
        try mediaCredentialStore.delete()
    }

    public func loadExpandedFolderPaths(
        for knowledgeBaseID: UUID
    ) -> Set<String> {
        let paths = userDefaults.stringArray(
            forKey: Self.expandedFolderPathsKey(
                knowledgeBaseID: knowledgeBaseID
            )
        ) ?? []
        return Set(paths + [""])
    }

    public func saveExpandedFolderPaths(
        _ paths: Set<String>,
        for knowledgeBaseID: UUID
    ) {
        let values = Array(paths.union([""])).sorted()
        userDefaults.set(
            values,
            forKey: Self.expandedFolderPathsKey(
                knowledgeBaseID: knowledgeBaseID
            )
        )
    }

    private static func expandedFolderPathsKey(
        knowledgeBaseID: UUID
    ) -> String {
        expandedFolderPathsPrefix + knowledgeBaseID.uuidString
    }
}
