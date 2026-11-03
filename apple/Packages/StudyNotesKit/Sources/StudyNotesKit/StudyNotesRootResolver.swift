import Foundation

public enum StudyNotesStoragePreference: Equatable, Sendable {
    case iCloud
    case local
}

public enum StudyNotesStorageLocation: Equatable, Sendable {
    case iCloud(URL)
    case local(URL)

    public var url: URL {
        switch self {
        case .iCloud(let url), .local(let url):
            return url
        }
    }
}

public enum StudyNotesRootStatus: Equatable, Sendable {
    case available(StudyNotesStorageLocation)
    case iCloudNotSignedIn
    case iCloudContainerUnavailable

    public var unavailableReason: StudyNotesStorageUnavailableReason? {
        switch self {
        case .available:
            return nil
        case .iCloudNotSignedIn:
            return .iCloudNotSignedIn
        case .iCloudContainerUnavailable:
            return .iCloudContainerUnavailable
        }
    }
}

public enum StudyNotesStorageUnavailableReason: Equatable, Sendable {
    case iCloudNotSignedIn
    case iCloudContainerUnavailable
}

public struct StudyNotesStorageUnavailableError: Error, Equatable, Sendable, LocalizedError {
    public let reason: StudyNotesStorageUnavailableReason

    public init(reason: StudyNotesStorageUnavailableReason) {
        self.reason = reason
    }

    public var errorDescription: String? {
        switch reason {
        case .iCloudNotSignedIn:
            "尚未登录 iCloud，无法使用 iCloud 学习目录。"
        case .iCloudContainerUnavailable:
            "无法访问 StudyNotes 的 iCloud 容器。"
        }
    }
}

public struct StudyNotesRootResolver: Equatable, Sendable {
    public let preferredStorage: StudyNotesStoragePreference
    public let localRootURL: URL
    public let iCloudContainerURL: URL?
    public let isICloudSignedIn: Bool

    public init(
        preferredStorage: StudyNotesStoragePreference,
        localRootURL: URL,
        iCloudContainerURL: URL?,
        isICloudSignedIn: Bool
    ) {
        self.preferredStorage = preferredStorage
        self.localRootURL = localRootURL
        self.iCloudContainerURL = iCloudContainerURL
        self.isICloudSignedIn = isICloudSignedIn
    }

    public func resolve() -> StudyNotesRootStatus {
        switch preferredStorage {
        case .local:
            return .available(.local(localRootURL))
        case .iCloud:
            guard isICloudSignedIn else {
                return .iCloudNotSignedIn
            }
            guard let iCloudContainerURL else {
                return .iCloudContainerUnavailable
            }
            return .available(.iCloud(iCloudContainerURL))
        }
    }
}

public protocol StudyNotesRootProviding: Sendable {
    func resolveRootStatus() -> StudyNotesRootStatus
}

public struct FixedStudyNotesRootProvider: StudyNotesRootProviding {
    public let status: StudyNotesRootStatus

    public init(status: StudyNotesRootStatus) {
        self.status = status
    }

    public func resolveRootStatus() -> StudyNotesRootStatus {
        status
    }
}

public struct FileManagerStudyNotesRootProvider: StudyNotesRootProviding, @unchecked Sendable {
    public let preferredStorage: StudyNotesStoragePreference
    public let localRootURL: URL
    public let iCloudContainerIdentifier: String

    private let fileManager: FileManager

    public init(
        preferredStorage: StudyNotesStoragePreference,
        localRootURL: URL,
        iCloudContainerIdentifier: String,
        fileManager: FileManager = .default
    ) {
        self.preferredStorage = preferredStorage
        self.localRootURL = localRootURL
        self.iCloudContainerIdentifier = iCloudContainerIdentifier
        self.fileManager = fileManager
    }

    public func resolveRootStatus() -> StudyNotesRootStatus {
        guard preferredStorage == .iCloud else {
            return .available(.local(localRootURL))
        }

        let iCloudContainerURL = fileManager
            .url(forUbiquityContainerIdentifier: iCloudContainerIdentifier)?
            .appending(path: "Documents", directoryHint: .isDirectory)
        let resolver = StudyNotesRootResolver(
            preferredStorage: preferredStorage,
            localRootURL: localRootURL,
            iCloudContainerURL: iCloudContainerURL,
            isICloudSignedIn: fileManager.ubiquityIdentityToken != nil
        )
        return resolver.resolve()
    }
}
