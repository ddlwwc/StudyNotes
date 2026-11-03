import Foundation

public enum WorkspaceStorageKind: String, Sendable {
    case local
    case iCloud

    public var label: String {
        switch self {
        case .local:
            "本地目录"
        case .iCloud:
            "iCloud 目录"
        }
    }

    public var systemImage: String {
        switch self {
        case .local:
            "internaldrive"
        case .iCloud:
            "icloud"
        }
    }
}

public struct WorkspaceLocation: Equatable, Sendable {
    public let url: URL
    public let storageKind: WorkspaceStorageKind

    public init(url: URL, storageKind: WorkspaceStorageKind) {
        self.url = url
        self.storageKind = storageKind
    }

    public var displayName: String {
        url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
    }
}

public enum WorkspaceConnectionState: Equatable, Sendable {
    case disconnected
    case restoring
    case connecting
    case connected(WorkspaceLocation)
    case failed(String)

    public var location: WorkspaceLocation? {
        guard case let .connected(location) = self else {
            return nil
        }
        return location
    }
}

public enum StudyPanelTab: String, CaseIterable, Identifiable, Sendable {
    case annotations
    case ai

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .annotations:
            "标注"
        case .ai:
            "AI 研读"
        }
    }
}
