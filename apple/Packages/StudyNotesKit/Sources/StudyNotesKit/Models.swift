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

public struct KnowledgeFolder: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let knowledgeBaseID: UUID
    public let name: String
    public let path: String
    public let parentPath: String
    public let depth: Int

    public init(
        knowledgeBaseID: UUID,
        name: String,
        path: String,
        parentPath: String,
        depth: Int
    ) {
        self.id = "\(knowledgeBaseID.uuidString)/\(path)"
        self.knowledgeBaseID = knowledgeBaseID
        self.name = name
        self.path = path
        self.parentPath = parentPath
        self.depth = depth
    }
}

public enum StudyMaterialKind: String, Codable, Equatable, Sendable {
    case note
    case markdown
    case html
    case webArticle
    case pdf
    case image

    public var displayName: String {
        switch self {
        case .note:
            "Markdown 笔记"
        case .markdown:
            "Markdown 文档"
        case .html:
            "HTML 文档"
        case .webArticle:
            "网页文章"
        case .pdf:
            "PDF"
        case .image:
            "图片"
        }
    }

    public var systemImage: String {
        switch self {
        case .note, .markdown:
            "doc.text"
        case .html, .webArticle:
            "globe"
        case .pdf:
            "doc.richtext"
        case .image:
            "photo"
        }
    }

    public var isTextDocument: Bool {
        switch self {
        case .note, .markdown, .html, .webArticle:
            true
        case .pdf, .image:
            false
        }
    }

    public var canPublish: Bool {
        isTextDocument
    }
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
    public let knowledgeBaseID: UUID?
    public let kind: StudyMaterialKind
    public let title: String
    public let updatedAt: Date
    public let conflictCopies: [ConflictCopy]
    public let folderPath: String
    public let tags: [String]
    public let deletedAt: Date?
    public let linkedMaterialIDs: [UUID]
    public let originalSourceURL: URL?
    public let publishMapping: PublishMapping?

    public init(
        id: UUID,
        knowledgeBaseID: UUID?,
        kind: StudyMaterialKind,
        title: String,
        updatedAt: Date,
        conflictCopies: [ConflictCopy],
        folderPath: String = "",
        tags: [String] = [],
        deletedAt: Date? = nil,
        linkedMaterialIDs: [UUID] = [],
        originalSourceURL: URL? = nil,
        publishMapping: PublishMapping? = nil
    ) {
        self.id = id
        self.knowledgeBaseID = knowledgeBaseID
        self.kind = kind
        self.title = title
        self.updatedAt = updatedAt
        self.conflictCopies = conflictCopies
        self.folderPath = folderPath
        self.tags = tags
        self.deletedAt = deletedAt
        self.linkedMaterialIDs = linkedMaterialIDs
        self.originalSourceURL = originalSourceURL
        self.publishMapping = publishMapping
    }
}

public struct LibraryIndex: Equatable, Sendable {
    public let knowledgeBases: [KnowledgeBase]
    public let materials: [StudyMaterialSummary]
    public let folders: [KnowledgeFolder]
    public let inboxMaterials: [StudyMaterialSummary]
    public let recycledMaterials: [StudyMaterialSummary]
    public let tags: [String]

    public init(
        knowledgeBases: [KnowledgeBase],
        materials: [StudyMaterialSummary],
        folders: [KnowledgeFolder] = [],
        inboxMaterials: [StudyMaterialSummary] = [],
        recycledMaterials: [StudyMaterialSummary] = [],
        tags: [String] = []
    ) {
        self.knowledgeBases = knowledgeBases
        self.materials = materials
        self.folders = folders
        self.inboxMaterials = inboxMaterials
        self.recycledMaterials = recycledMaterials
        self.tags = tags
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

public struct MaterialDocument: Identifiable, Equatable, Sendable {
    public let summary: StudyMaterialSummary
    public let markdown: String
    public let renderedHTML: String
    public let headings: [ReaderHeading]
    public let sourceURL: URL
    public let sourceFileURL: URL?
    public let mediaURLs: [String: URL]
    public let pageCount: Int?
    public let hasTextLayer: Bool?
    public let isLocked: Bool
    public let currentGenerationID: UUID?
    public let contentFingerprint: String?
    public let blocks: [EditorDocumentBlockEnvelope]
    public let derivedRebuildPending: Bool

    public var id: UUID { summary.id }

    public init(
        summary: StudyMaterialSummary,
        markdown: String,
        renderedHTML: String,
        headings: [ReaderHeading],
        sourceURL: URL,
        sourceFileURL: URL?,
        mediaURLs: [String: URL] = [:],
        pageCount: Int? = nil,
        hasTextLayer: Bool? = nil,
        isLocked: Bool = false,
        currentGenerationID: UUID? = nil,
        contentFingerprint: String? = nil,
        blocks: [EditorDocumentBlockEnvelope] = [],
        derivedRebuildPending: Bool = false
    ) {
        self.summary = summary
        self.markdown = markdown
        self.renderedHTML = renderedHTML
        self.headings = headings
        self.sourceURL = sourceURL
        self.sourceFileURL = sourceFileURL
        self.mediaURLs = mediaURLs
        self.pageCount = pageCount
        self.hasTextLayer = hasTextLayer
        self.isLocked = isLocked
        self.currentGenerationID = currentGenerationID
        self.contentFingerprint = contentFingerprint
        self.blocks = blocks
        self.derivedRebuildPending = derivedRebuildPending
    }
}

public struct ReaderHeading: Identifiable, Equatable, Sendable {
    public let id: String
    public let level: Int
    public let title: String

    public init(id: String, level: Int, title: String) {
        self.id = id
        self.level = level
        self.title = title
    }
}

public struct MaterialImportResult: Identifiable, Equatable, Sendable {
    public let summary: StudyMaterialSummary
    public let isDuplicate: Bool
    public let duplicateOf: UUID?
    public let mediaFailures: [String]

    public var id: UUID { summary.id }

    public init(
        summary: StudyMaterialSummary,
        isDuplicate: Bool,
        duplicateOf: UUID?,
        mediaFailures: [String] = []
    ) {
        self.summary = summary
        self.isDuplicate = isDuplicate
        self.duplicateOf = duplicateOf
        self.mediaFailures = mediaFailures
    }
}

public struct MaterialImportBatch: Equatable, Sendable {
    public let results: [MaterialImportResult]

    public var importedCount: Int {
        results.count { !$0.isDuplicate }
    }

    public var duplicateCount: Int {
        results.count(where: \.isDuplicate)
    }

    public init(results: [MaterialImportResult]) {
        self.results = results
    }
}

public struct TextRevision: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let materialID: UUID
    public let createdAt: Date
    public let text: String

    public init(id: UUID, materialID: UUID, createdAt: Date, text: String) {
        self.id = id
        self.materialID = materialID
        self.createdAt = createdAt
        self.text = text
    }
}

public struct NormalizedRect: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = min(max(x, 0), 1)
        self.y = min(max(y, 0), 1)
        self.width = min(max(width, 0), 1 - self.x)
        self.height = min(max(height, 0), 1 - self.y)
    }
}

public enum AnnotationAnchorKind: String, Codable, Equatable, Sendable {
    case text
    case imageRect
    case pdfText
    case pdfPageRect
}

public enum AnnotationElementType: String, Codable, Equatable, Sendable {
    case heading
    case paragraph
    case blockquote
    case listItem
    case image
    case table
    case codeBlock
}

public struct AnnotationAnchor: Codable, Equatable, Sendable {
    public let kind: AnnotationAnchorKind
    public let excerpt: String
    public let prefix: String
    public let suffix: String
    public let offset: Int?
    public let blockPath: [Int]
    public let pageIndex: Int?
    public let rect: NormalizedRect?
    public let elementType: AnnotationElementType?
    public let contentFingerprint: String?
    public let contentSummary: String?

    public init(
        kind: AnnotationAnchorKind,
        excerpt: String = "",
        prefix: String = "",
        suffix: String = "",
        offset: Int? = nil,
        blockPath: [Int] = [],
        pageIndex: Int? = nil,
        rect: NormalizedRect? = nil,
        elementType: AnnotationElementType? = nil,
        contentFingerprint: String? = nil,
        contentSummary: String? = nil
    ) {
        self.kind = kind
        self.excerpt = excerpt
        self.prefix = prefix
        self.suffix = suffix
        self.offset = offset
        self.blockPath = blockPath
        self.pageIndex = pageIndex
        self.rect = rect
        self.elementType = elementType
        self.contentFingerprint = contentFingerprint
        self.contentSummary = contentSummary
    }
}

public enum AnnotationStatus: String, Codable, Equatable, Sendable {
    case active
    case unresolved
}

public struct MaterialAnnotation: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let materialID: UUID
    public var anchor: AnnotationAnchor
    public var quote: String
    public var note: String
    public var status: AnnotationStatus
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        materialID: UUID,
        anchor: AnnotationAnchor,
        quote: String,
        note: String,
        status: AnnotationStatus = .active,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.materialID = materialID
        self.anchor = anchor
        self.quote = quote
        self.note = note
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case materialID
        case anchor
        case quote
        case note
        case status
        case createdAt
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let wire = try CrossPlatformAnnotation(from: decoder)
        self.init(
            id: wire.id,
            materialID: wire.materialID,
            anchor: try wire.anchor.annotationAnchor(),
            quote: wire.quote,
            note: wire.note,
            status: wire.status == AnnotationStatus.active.rawValue
                ? .active
                : .unresolved,
            createdAt: wire.createdAt,
            updatedAt: wire.updatedAt
        )
    }

    public func encode(to encoder: Encoder) throws {
        let wire = CrossPlatformAnnotation(
            id: id,
            materialID: materialID,
            anchor: anchor.crossPlatformAnchor,
            quote: quote,
            note: note,
            status: status.rawValue,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        try wire.encode(to: encoder)
    }
}

public struct AIProviderProfile: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var baseURL: URL
    public var model: String
    public var keychainAccount: String

    public init(
        id: UUID = UUID(),
        name: String,
        baseURL: URL,
        model: String,
        keychainAccount: String
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.model = model
        self.keychainAccount = keychainAccount
    }
}

public enum AIMessageRole: String, Codable, Equatable, Sendable {
    case system
    case user
    case assistant
}

public struct AIMessage: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var role: AIMessageRole
    public var content: String
    public var createdAt: Date
    public var promptTokens: Int?
    public var completionTokens: Int?

    public init(
        id: UUID = UUID(),
        role: AIMessageRole,
        content: String,
        createdAt: Date = Date(),
        promptTokens: Int? = nil,
        completionTokens: Int? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
    }
}

public enum AIConversationOrigin: String, Codable, Equatable, Sendable {
    case selection
    case summary
}

public enum AIStudySessionStatus: String, Codable, Equatable, Sendable {
    case pending
    case active
    case completed
    case stopped
    case failed
}

public struct AIConversation: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let materialID: UUID
    public var title: String
    public var origin: AIConversationOrigin
    public var originAnchor: AnnotationAnchor?
    public var action: String
    public var scopeDescription: String
    public var status: AIStudySessionStatus
    public var messages: [AIMessage]
    public let createdAt: Date
    public var updatedAt: Date
    public var providerName: String
    public var model: String

    public init(
        id: UUID = UUID(),
        materialID: UUID,
        title: String,
        origin: AIConversationOrigin,
        originAnchor: AnnotationAnchor? = nil,
        action: String? = nil,
        scopeDescription: String? = nil,
        status: AIStudySessionStatus = .active,
        messages: [AIMessage] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        providerName: String,
        model: String
    ) {
        self.id = id
        self.materialID = materialID
        self.title = title
        self.origin = origin
        self.originAnchor = originAnchor
        self.action = action ?? (origin == .summary ? "总结" : "解释")
        self.scopeDescription = scopeDescription
            ?? (origin == .summary ? "整份材料" : "")
        self.status = status
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.providerName = providerName
        self.model = model
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case materialID
        case providerName
        case model
        case modelID
        case title
        case action
        case scopeDescription
        case origin
        case originAnchor
        case status
        case messages
        case createdAt
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let wire = try CrossPlatformAIStudySession(from: decoder)
        self.init(
            id: wire.id,
            materialID: wire.materialID,
            title: wire.title,
            origin: wire.origin.aiConversationOrigin,
            originAnchor: try wire.originAnchor.map { try $0.annotationAnchor() },
            action: wire.action,
            scopeDescription: wire.scopeDescription,
            status: AIStudySessionStatus(rawValue: wire.status) ?? .pending,
            messages: wire.messages.map {
                AIMessage(
                    id: $0.id,
                    role: $0.role.aiMessageRole,
                    content: $0.content,
                    createdAt: $0.createdAt,
                    promptTokens: $0.promptTokens,
                    completionTokens: $0.completionTokens
                )
            },
            createdAt: wire.createdAt,
            updatedAt: wire.updatedAt,
            providerName: wire.providerName,
            model: wire.model
        )
    }

    public func encode(to encoder: Encoder) throws {
        let wire = CrossPlatformAIStudySession(
            id: id,
            materialID: materialID,
            providerName: providerName,
            model: model,
            title: title,
            action: action,
            scopeDescription: scopeDescription,
            origin: origin.crossPlatformOrigin,
            status: status.rawValue,
            originAnchor: originAnchor?.crossPlatformAnchor,
            messages: messages.map {
                CrossPlatformAIMessage(
                    id: $0.id,
                    role: $0.role.crossPlatformRole,
                    content: $0.content,
                    createdAt: $0.createdAt,
                    promptTokens: $0.promptTokens,
                    completionTokens: $0.completionTokens
                )
            },
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        try wire.encode(to: encoder)
    }
}

public typealias AIStudySession = AIConversation

extension CrossPlatformAnnotationAnchor {
    func annotationAnchor() throws -> AnnotationAnchor {
        let mappedKind: AnnotationAnchorKind
        switch kind {
            case .text:
                mappedKind = .text
            case .imageRect:
                mappedKind = .imageRect
            case .pdfText:
                mappedKind = .pdfText
            case .pdfPageRect:
                mappedKind = .pdfPageRect
            case .wholeMaterial:
                throw CrossPlatformCodecError.unsupportedAnnotationAnchor(kind.rawValue)
        }
        return AnnotationAnchor(
            kind: mappedKind,
            excerpt: excerpt,
            prefix: prefix,
            suffix: suffix,
            offset: offset,
            blockPath: blockPath,
            pageIndex: pageIndex,
            rect: rect.map {
                NormalizedRect(
                    x: $0.x,
                    y: $0.y,
                    width: $0.width,
                    height: $0.height
                )
            },
            elementType: elementType,
            contentFingerprint: contentFingerprint,
            contentSummary: contentSummary
        )
    }
}

extension AnnotationAnchor {
    var crossPlatformAnchor: CrossPlatformAnnotationAnchor {
        let mappedKind: CrossPlatformAnnotationKind = switch kind {
            case .text:
                .text
            case .imageRect:
                .imageRect
            case .pdfText:
                .pdfText
            case .pdfPageRect:
                .pdfPageRect
        }
        return CrossPlatformAnnotationAnchor(
            kind: mappedKind,
            excerpt: excerpt,
            prefix: prefix,
            suffix: suffix,
            offset: offset,
            blockPath: blockPath,
            pageIndex: pageIndex,
            rect: rect.map {
                CrossPlatformRect(
                    x: $0.x,
                    y: $0.y,
                    width: $0.width,
                    height: $0.height
                )
            },
            elementType: elementType,
            contentFingerprint: contentFingerprint,
            contentSummary: contentSummary
        )
    }
}

extension CrossPlatformAIConversationOrigin {
    var aiConversationOrigin: AIConversationOrigin {
        switch self {
        case .selection:
            .selection
        case .summary:
            .summary
        }
    }
}

extension AIConversationOrigin {
    var crossPlatformOrigin: CrossPlatformAIConversationOrigin {
        switch self {
        case .selection:
            .selection
        case .summary:
            .summary
        }
    }
}

extension CrossPlatformAIMessageRole {
    var aiMessageRole: AIMessageRole {
        switch self {
        case .system:
            .system
        case .user:
            .user
        case .assistant:
            .assistant
        }
    }
}

extension AIMessageRole {
    var crossPlatformRole: CrossPlatformAIMessageRole {
        switch self {
        case .system:
            .system
        case .user:
            .user
        case .assistant:
            .assistant
        }
    }
}

public enum AIPromotionTarget: String, CaseIterable, Identifiable, Sendable {
    case note
    case annotation
    case material

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .note:
            "提升为笔记"
        case .annotation:
            "提升为标注"
        case .material:
            "提升为独立材料"
        }
    }
}

public struct AIPromotionResult: Equatable, Sendable {
    public let target: AIPromotionTarget
    public let material: StudyMaterialSummary
    public let annotation: MaterialAnnotation?

    public init(
        target: AIPromotionTarget,
        material: StudyMaterialSummary,
        annotation: MaterialAnnotation?
    ) {
        self.target = target
        self.material = material
        self.annotation = annotation
    }
}

public struct SearchFilter: Equatable, Sendable {
    public var knowledgeBaseID: UUID?
    public var kind: StudyMaterialKind?
    public var tag: String?
    public var updatedAfter: Date?

    public init(
        knowledgeBaseID: UUID? = nil,
        kind: StudyMaterialKind? = nil,
        tag: String? = nil,
        updatedAfter: Date? = nil
    ) {
        self.knowledgeBaseID = knowledgeBaseID
        self.kind = kind
        self.tag = tag
        self.updatedAfter = updatedAfter
    }
}

public enum SearchMatchLayer: String, Codable, Equatable, Sendable {
    case title
    case body
    case annotation
    case ai
}

public struct SearchHit: Identifiable, Equatable, Sendable {
    public let materialID: UUID
    public let title: String
    public let knowledgeBaseID: UUID?
    public let kind: StudyMaterialKind
    public let snippet: String
    public let matchedLayer: SearchMatchLayer
    public let updatedAt: Date

    public var id: String {
        "\(materialID.uuidString)-\(matchedLayer.rawValue)-\(snippet)"
    }

    public init(
        materialID: UUID,
        title: String,
        knowledgeBaseID: UUID?,
        kind: StudyMaterialKind,
        snippet: String,
        matchedLayer: SearchMatchLayer,
        updatedAt: Date
    ) {
        self.materialID = materialID
        self.title = title
        self.knowledgeBaseID = knowledgeBaseID
        self.kind = kind
        self.snippet = snippet
        self.matchedLayer = matchedLayer
        self.updatedAt = updatedAt
    }
}

public enum PublishVisibility: String, Codable, CaseIterable, Identifiable, Sendable {
    case publicArticle
    case unlisted

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .publicArticle:
            "公开"
        case .unlisted:
            "未列出"
        }
    }
}

public struct PublishMapping: Codable, Equatable, Sendable {
    public var articleID: String
    public var publicURL: URL
    public var lastPublishedVersion: String?
    public var visibility: PublishVisibility
    public var contentFingerprint: String
    public var updatedAt: Date

    public init(
        articleID: String,
        publicURL: URL,
        lastPublishedVersion: String?,
        visibility: PublishVisibility,
        contentFingerprint: String,
        updatedAt: Date
    ) {
        self.articleID = articleID
        self.publicURL = publicURL
        self.lastPublishedVersion = lastPublishedVersion
        self.visibility = visibility
        self.contentFingerprint = contentFingerprint
        self.updatedAt = updatedAt
    }
}

public enum PublishMediaState: String, Codable, Equatable, Sendable {
    case pendingCredentials
    case pendingUpload
    case uploading
    case uploaded
    case failed
}

public struct PublishMediaItem: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let fileName: String
    public let localPath: String
    public let contentHash: String
    public let mediaType: String
    public let byteCount: Int
    public var objectKey: String?
    public var state: PublishMediaState
    public var errorMessage: String?

    public init(
        id: String,
        fileName: String,
        localPath: String,
        contentHash: String,
        mediaType: String,
        byteCount: Int,
        objectKey: String? = nil,
        state: PublishMediaState,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.localPath = localPath
        self.contentHash = contentHash
        self.mediaType = mediaType
        self.byteCount = byteCount
        self.objectKey = objectKey
        self.state = state
        self.errorMessage = errorMessage
    }
}

public struct PublishedAnnotation: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let quote: String
    public let note: String
    public let anchor: AnnotationAnchor

    public init(id: UUID, quote: String, note: String, anchor: AnnotationAnchor) {
        self.id = id
        self.quote = quote
        self.note = note
        self.anchor = anchor
    }
}

public struct PublishPreview: Equatable, Sendable {
    public let materialID: UUID
    public let title: String
    public let html: String
    public let contentFingerprint: String
    public let includeAnnotations: Bool
    public let includeAI: Bool
    public let annotations: [PublishedAnnotation]
    public let aiAppendix: String?
    public let media: [PublishMediaItem]
    public let mapping: PublishMapping?

    public init(
        materialID: UUID,
        title: String,
        html: String,
        contentFingerprint: String,
        includeAnnotations: Bool,
        includeAI: Bool,
        annotations: [PublishedAnnotation],
        aiAppendix: String?,
        media: [PublishMediaItem],
        mapping: PublishMapping?
    ) {
        self.materialID = materialID
        self.title = title
        self.html = html
        self.contentFingerprint = contentFingerprint
        self.includeAnnotations = includeAnnotations
        self.includeAI = includeAI
        self.annotations = annotations
        self.aiAppendix = aiAppendix
        self.media = media
        self.mapping = mapping
    }
}
