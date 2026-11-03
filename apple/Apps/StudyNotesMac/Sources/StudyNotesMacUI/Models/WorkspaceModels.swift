import Foundation
import StudyNotesKit

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

public enum WorkspaceTagMutationMode: String, CaseIterable, Identifiable, Sendable {
    case add
    case remove
    case replace

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .add:
            "添加"
        case .remove:
            "移除"
        case .replace:
            "替换"
        }
    }
}

public enum WorkspaceCollection: Hashable, Sendable {
    case all
    case knowledgeBase(UUID)
    case folder(knowledgeBaseID: UUID, path: String)
    case inbox
    case recycleBin
    case tag(String)
}

public enum WorkspaceRenameTarget: Identifiable, Equatable, Sendable {
    case knowledgeBase(KnowledgeBase)
    case folder(KnowledgeFolder)

    public var id: String {
        switch self {
        case let .knowledgeBase(knowledgeBase):
            "knowledge-base-\(knowledgeBase.id.uuidString)"
        case let .folder(folder):
            "folder-\(folder.id)"
        }
    }
}

public struct WorkspaceCreateFolderRequest: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let knowledgeBaseID: UUID
    public let parentPath: String

    public init(id: UUID = UUID(), knowledgeBaseID: UUID, parentPath: String) {
        self.id = id
        self.knowledgeBaseID = knowledgeBaseID
        self.parentPath = parentPath
    }
}

public struct WorkspaceMoveFolderRequest: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let folder: KnowledgeFolder

    public init(id: UUID = UUID(), folder: KnowledgeFolder) {
        self.id = id
        self.folder = folder
    }
}
