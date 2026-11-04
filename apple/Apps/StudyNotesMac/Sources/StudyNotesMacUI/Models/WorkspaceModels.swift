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

public enum WorkspaceTreeSelectionMode: Sendable {
    case replace
    case toggle
    case extendRange
}

public enum WorkspacePane: String, CaseIterable, Identifiable, Sendable {
    case library
    case materials
    case study

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .library:
            "知识库栏"
        case .materials:
            "材料目录栏"
        case .study:
            "研读层"
        }
    }
}

public struct WorkspaceDestination: Equatable, Sendable {
    public let knowledgeBaseID: UUID?
    public let folderPath: String

    public init(knowledgeBaseID: UUID?, folderPath: String) {
        self.knowledgeBaseID = knowledgeBaseID
        self.folderPath = knowledgeBaseID == nil ? "" : folderPath
    }
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

public struct ReaderSelection: Equatable, Sendable {
    public let quote: String
    public let prefix: String
    public let suffix: String
    public let offset: Int
    public let blockPath: [Int]
    public let pageIndex: Int?
    public let rect: NormalizedRect?
    public let anchorKind: AnnotationAnchorKind?
    public let elementType: AnnotationElementType?
    public let contentFingerprint: String
    public let contentSummary: String
    public let viewportY: CGFloat?

    public init(
        quote: String,
        prefix: String = "",
        suffix: String = "",
        offset: Int = 0,
        blockPath: [Int] = [],
        pageIndex: Int? = nil,
        rect: NormalizedRect? = nil,
        anchorKind: AnnotationAnchorKind? = .text,
        elementType: AnnotationElementType? = nil,
        contentFingerprint: String = "",
        contentSummary: String = "",
        viewportY: CGFloat? = nil
    ) {
        self.quote = quote
        self.prefix = prefix
        self.suffix = suffix
        self.offset = offset
        self.blockPath = blockPath
        self.pageIndex = pageIndex
        self.rect = rect
        self.anchorKind = anchorKind
        self.elementType = elementType
        self.contentFingerprint = contentFingerprint
        self.contentSummary = contentSummary
        self.viewportY = viewportY
    }

    public var anchor: AnnotationAnchor {
        AnnotationAnchor(
            kind: anchorKind ?? .text,
            excerpt: quote,
            prefix: prefix,
            suffix: suffix,
            offset: offset,
            blockPath: blockPath,
            pageIndex: pageIndex,
            rect: rect,
            elementType: elementType,
            contentFingerprint: contentFingerprint,
            contentSummary: contentSummary
        )
    }
}

public struct AnnotationDraftRequest: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let materialID: UUID
    public let annotationID: UUID?
    public let quote: String
    public let anchor: AnnotationAnchor
    public let initialNote: String

    public init(
        id: UUID = UUID(),
        materialID: UUID,
        annotationID: UUID? = nil,
        quote: String,
        anchor: AnnotationAnchor,
        initialNote: String = ""
    ) {
        self.id = id
        self.materialID = materialID
        self.annotationID = annotationID
        self.quote = quote
        self.anchor = anchor
        self.initialNote = initialNote
    }
}

public struct InlineAnnotationDraft: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let materialID: UUID
    public let annotationID: UUID?
    public let quote: String
    public let anchor: AnnotationAnchor
    public let initialNote: String
    public let viewportY: CGFloat?

    public init(
        id: UUID = UUID(),
        materialID: UUID,
        annotationID: UUID? = nil,
        quote: String,
        anchor: AnnotationAnchor,
        initialNote: String = "",
        viewportY: CGFloat? = nil
    ) {
        self.id = id
        self.materialID = materialID
        self.annotationID = annotationID
        self.quote = quote
        self.anchor = anchor
        self.initialNote = initialNote
        self.viewportY = viewportY
    }
}

public enum StudyAnnotationLayout {
    public static func positions(
        annotations: [MaterialAnnotation],
        targetY: [UUID: CGFloat],
        cardHeights: [UUID: CGFloat],
        availableHeight: CGFloat,
        gap: CGFloat = 8
    ) -> [UUID: CGFloat] {
        let resolved = annotations
            .filter { $0.status == .active }
            .sorted {
                let leftY = targetY[$0.id] ?? .greatestFiniteMagnitude
                let rightY = targetY[$1.id] ?? .greatestFiniteMagnitude
                return leftY == rightY
                    ? $0.createdAt < $1.createdAt
                    : leftY < rightY
            }
        let unresolved = annotations
            .filter { $0.status == .unresolved }
            .sorted { $0.updatedAt < $1.updatedAt }
        var result: [UUID: CGFloat] = [:]
        var cursor: CGFloat = 0

        for annotation in resolved + unresolved {
            let height = cardHeights[annotation.id] ?? 88
            let desired = annotation.status == .active
                ? max(0, targetY[annotation.id] ?? cursor)
                : cursor
            let position = max(cursor, desired)
            result[annotation.id] = position
            cursor = position + height + gap
        }

        guard availableHeight > 0,
              let lastY = result.values.max() else {
            return result
        }
        let lastHeight = result.keys
            .compactMap { id in result[id].map { ($0, cardHeights[id] ?? 88) } }
            .max { $0.0 < $1.0 }?.1 ?? 88
        let overflow = max(0, lastY + lastHeight - availableHeight)
        guard overflow > 0 else {
            return result
        }
        return result.mapValues { max(0, $0 - overflow) }
    }
}

public struct AIContextPreview: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let profile: AIProviderProfile
    public let prompt: String
    public let context: String
    public let origin: AIConversationOrigin
    public let anchor: AnnotationAnchor?

    public init(
        id: UUID = UUID(),
        profile: AIProviderProfile,
        prompt: String,
        context: String,
        origin: AIConversationOrigin,
        anchor: AnnotationAnchor?
    ) {
        self.id = id
        self.profile = profile
        self.prompt = prompt
        self.context = context
        self.origin = origin
        self.anchor = anchor
    }

    public var approximateCharacterCount: Int {
        prompt.count + context.count
    }
}

public enum AIRequestPhase: Equatable, Sendable {
    case idle
    case streaming
    case stopped
    case failed(String)

    public var isStreaming: Bool {
        self == .streaming
    }
}
