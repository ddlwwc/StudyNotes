import Foundation

public enum StudyNotesKit {
    public static let schemaVersion = 1
}

public struct KnowledgeBase: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public let createdAt: Date

    public init(id: UUID, name: String, createdAt: Date) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

public enum StudyMaterialKind: String, Codable, Equatable, Sendable {
    case note
}

public struct ConflictCopy: Identifiable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let relativePath: String

    public init(id: String, displayName: String, relativePath: String) {
        self.id = id
        self.displayName = displayName
        self.relativePath = relativePath
    }
}

public struct StudyMaterialSummary: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let knowledgeBaseID: UUID
    public let kind: StudyMaterialKind
    public let title: String
    public let updatedAt: Date
    public let conflictCopies: [ConflictCopy]

    public init(
        id: UUID,
        knowledgeBaseID: UUID,
        kind: StudyMaterialKind,
        title: String,
        updatedAt: Date,
        conflictCopies: [ConflictCopy]
    ) {
        self.id = id
        self.knowledgeBaseID = knowledgeBaseID
        self.kind = kind
        self.title = title
        self.updatedAt = updatedAt
        self.conflictCopies = conflictCopies
    }
}

public struct LibraryIndex: Equatable, Sendable {
    public let knowledgeBases: [KnowledgeBase]
    public let materials: [StudyMaterialSummary]

    public init(knowledgeBases: [KnowledgeBase], materials: [StudyMaterialSummary]) {
        self.knowledgeBases = knowledgeBases
        self.materials = materials
    }
}

public struct MarkdownNote: Equatable, Sendable {
    public let summary: StudyMaterialSummary
    public let markdown: String

    public init(summary: StudyMaterialSummary, markdown: String) {
        self.summary = summary
        self.markdown = markdown
    }
}
