import Foundation

public enum MarkdownEditorMode: String, Codable, Equatable, Sendable {
    case edit
    case annotate
}

public struct MarkdownEditorSelection: Codable, Equatable, Sendable {
    public let quote: String
    public let prefix: String
    public let suffix: String
    public let offset: Int
    public let blockPath: [Int]
    public let elementType: AnnotationElementType?
    public let contentFingerprint: String
    public let viewportY: Double?

    public init(
        quote: String,
        prefix: String = "",
        suffix: String = "",
        offset: Int = 0,
        blockPath: [Int] = [],
        elementType: AnnotationElementType? = nil,
        contentFingerprint: String = "",
        viewportY: Double? = nil
    ) {
        self.quote = quote
        self.prefix = prefix
        self.suffix = suffix
        self.offset = offset
        self.blockPath = blockPath
        self.elementType = elementType
        self.contentFingerprint = contentFingerprint
        self.viewportY = viewportY
    }

    public var hasTarget: Bool {
        !quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !blockPath.isEmpty
    }
}

public struct MarkdownEditorAnnotationPayload:
    Codable,
    Equatable,
    Identifiable,
    Sendable
{
    public let id: UUID
    public let quote: String
    public let note: String
    public let prefix: String
    public let suffix: String
    public let offset: Int?
    public let blockPath: [Int]
    public let elementType: AnnotationElementType?
    public let unresolved: Bool

    public init(annotation: MaterialAnnotation) {
        id = annotation.id
        quote = annotation.quote
        note = annotation.note
        prefix = annotation.anchor.prefix
        suffix = annotation.anchor.suffix
        offset = annotation.anchor.offset
        blockPath = annotation.anchor.blockPath
        elementType = annotation.anchor.elementType
        unresolved = annotation.status == .unresolved
    }
}

public enum MarkdownEditorCommand: String, Codable, Equatable, Sendable {
    case save
    case undo
    case redo
    case focusTitle
    case enterSourceMode
    case exitSourceMode
}

public enum MarkdownEditorBridgeMessage: Equatable, Sendable {
    case ready
    case loadDocument(
        markdown: String,
        title: String,
        compatibilityBlocks: [MarkdownCompatibilityBlock]
    )
    case markdownChanged(String)
    case titleChanged(String)
    case sourceChanged(String)
    case sourceModeChanged(Bool)
    case command(MarkdownEditorCommand)
    case saveRequested
    case attachRequested(MarkdownEditorAttachmentKind)
    case documentRuntimeChanged(
        isLocked: Bool,
        mode: MarkdownEditorMode
    )
    case annotationsChanged([MarkdownEditorAnnotationPayload])
    case activeAnnotationChanged(UUID?)
    case selectionChanged(MarkdownEditorSelection?)
    case annotationRequested(MarkdownEditorSelection)
    case annotationClicked(UUID)
    case unresolvedAnnotationIDsChanged([UUID])
    case annotationLayoutChanged([String: Double])
    case failed(reason: String)
}

public enum MarkdownEditorAttachmentKind: String, Codable, Equatable, Sendable {
    case image
    case file
}

extension MarkdownEditorBridgeMessage: Codable {
    private enum Kind: String, Codable {
        case ready
        case loadDocument
        case markdownChanged
        case titleChanged
        case sourceChanged
        case sourceModeChanged
        case command
        case saveRequested
        case attachRequested
        case documentRuntimeChanged
        case annotationsChanged
        case activeAnnotationChanged
        case selectionChanged
        case annotationRequested
        case annotationClicked
        case unresolvedAnnotationIDsChanged
        case annotationLayoutChanged
        case failed
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case markdown
        case title
        case compatibilityBlocks
        case sourceMode
        case command
        case attachmentKind
        case isLocked
        case mode
        case annotations
        case activeAnnotationID
        case selection
        case annotationID
        case unresolvedAnnotationIDs
        case annotationLayout
        case reason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .type)
        switch kind {
        case .ready:
            self = .ready
        case .loadDocument:
            self = .loadDocument(
                markdown: try container.decode(String.self, forKey: .markdown),
                title: try container.decode(String.self, forKey: .title),
                compatibilityBlocks: try container.decodeIfPresent(
                    [MarkdownCompatibilityBlock].self,
                    forKey: .compatibilityBlocks
                ) ?? []
            )
        case .markdownChanged:
            self = .markdownChanged(
                try container.decode(String.self, forKey: .markdown)
            )
        case .titleChanged:
            self = .titleChanged(
                try container.decode(String.self, forKey: .title)
            )
        case .sourceChanged:
            self = .sourceChanged(
                try container.decode(String.self, forKey: .markdown)
            )
        case .sourceModeChanged:
            self = .sourceModeChanged(
                try container.decode(Bool.self, forKey: .sourceMode)
            )
        case .command:
            self = .command(
                try container.decode(
                    MarkdownEditorCommand.self,
                    forKey: .command
                )
            )
        case .saveRequested:
            self = .saveRequested
        case .attachRequested:
            self = .attachRequested(
                try container.decode(
                    MarkdownEditorAttachmentKind.self,
                    forKey: .attachmentKind
                )
            )
        case .documentRuntimeChanged:
            self = .documentRuntimeChanged(
                isLocked: try container.decode(
                    Bool.self,
                    forKey: .isLocked
                ),
                mode: try container.decode(
                    MarkdownEditorMode.self,
                    forKey: .mode
                )
            )
        case .annotationsChanged:
            self = .annotationsChanged(
                try container.decode(
                    [MarkdownEditorAnnotationPayload].self,
                    forKey: .annotations
                )
            )
        case .activeAnnotationChanged:
            self = .activeAnnotationChanged(
                try container.decodeIfPresent(
                    UUID.self,
                    forKey: .activeAnnotationID
                )
            )
        case .selectionChanged:
            self = .selectionChanged(
                try container.decodeIfPresent(
                    MarkdownEditorSelection.self,
                    forKey: .selection
                )
            )
        case .annotationRequested:
            self = .annotationRequested(
                try container.decode(
                    MarkdownEditorSelection.self,
                    forKey: .selection
                )
            )
        case .annotationClicked:
            self = .annotationClicked(
                try container.decode(UUID.self, forKey: .annotationID)
            )
        case .unresolvedAnnotationIDsChanged:
            self = .unresolvedAnnotationIDsChanged(
                try container.decode(
                    [UUID].self,
                    forKey: .unresolvedAnnotationIDs
                )
            )
        case .annotationLayoutChanged:
            self = .annotationLayoutChanged(
                try container.decode(
                    [String: Double].self,
                    forKey: .annotationLayout
                )
            )
        case .failed:
            self = .failed(
                reason: try container.decode(String.self, forKey: .reason)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .ready:
            try container.encode(Kind.ready, forKey: .type)
        case .loadDocument(let markdown, let title, let compatibilityBlocks):
            try container.encode(Kind.loadDocument, forKey: .type)
            try container.encode(markdown, forKey: .markdown)
            try container.encode(title, forKey: .title)
            try container.encode(
                compatibilityBlocks,
                forKey: .compatibilityBlocks
            )
        case .markdownChanged(let markdown):
            try container.encode(Kind.markdownChanged, forKey: .type)
            try container.encode(markdown, forKey: .markdown)
        case .titleChanged(let title):
            try container.encode(Kind.titleChanged, forKey: .type)
            try container.encode(title, forKey: .title)
        case .sourceChanged(let markdown):
            try container.encode(Kind.sourceChanged, forKey: .type)
            try container.encode(markdown, forKey: .markdown)
        case .sourceModeChanged(let enabled):
            try container.encode(Kind.sourceModeChanged, forKey: .type)
            try container.encode(enabled, forKey: .sourceMode)
        case .command(let command):
            try container.encode(Kind.command, forKey: .type)
            try container.encode(command, forKey: .command)
        case .saveRequested:
            try container.encode(Kind.saveRequested, forKey: .type)
        case .attachRequested(let kind):
            try container.encode(Kind.attachRequested, forKey: .type)
            try container.encode(kind, forKey: .attachmentKind)
        case let .documentRuntimeChanged(isLocked, mode):
            try container.encode(
                Kind.documentRuntimeChanged,
                forKey: .type
            )
            try container.encode(isLocked, forKey: .isLocked)
            try container.encode(mode, forKey: .mode)
        case .annotationsChanged(let annotations):
            try container.encode(Kind.annotationsChanged, forKey: .type)
            try container.encode(annotations, forKey: .annotations)
        case .activeAnnotationChanged(let annotationID):
            try container.encode(
                Kind.activeAnnotationChanged,
                forKey: .type
            )
            try container.encodeIfPresent(
                annotationID,
                forKey: .activeAnnotationID
            )
        case .selectionChanged(let selection):
            try container.encode(Kind.selectionChanged, forKey: .type)
            try container.encodeIfPresent(selection, forKey: .selection)
        case .annotationRequested(let selection):
            try container.encode(
                Kind.annotationRequested,
                forKey: .type
            )
            try container.encode(selection, forKey: .selection)
        case .annotationClicked(let annotationID):
            try container.encode(Kind.annotationClicked, forKey: .type)
            try container.encode(annotationID, forKey: .annotationID)
        case .unresolvedAnnotationIDsChanged(let annotationIDs):
            try container.encode(
                Kind.unresolvedAnnotationIDsChanged,
                forKey: .type
            )
            try container.encode(
                annotationIDs,
                forKey: .unresolvedAnnotationIDs
            )
        case .annotationLayoutChanged(let positions):
            try container.encode(
                Kind.annotationLayoutChanged,
                forKey: .type
            )
            try container.encode(positions, forKey: .annotationLayout)
        case .failed(let reason):
            try container.encode(Kind.failed, forKey: .type)
            try container.encode(reason, forKey: .reason)
        }
    }
}

public struct MarkdownEditorWebResource: Codable, Equatable, Sendable {
    public let htmlURL: URL
    public let baseURL: URL
    public let messageHandlerName: String

    public init(
        htmlURL: URL,
        baseURL: URL,
        messageHandlerName: String
    ) {
        self.htmlURL = htmlURL
        self.baseURL = baseURL
        self.messageHandlerName = messageHandlerName
    }
}

@MainActor
public protocol MarkdownEditorHosting: AnyObject {
    func loadMarkdownEditor(_ resource: MarkdownEditorWebResource) throws
    func send(_ message: MarkdownEditorBridgeMessage) async throws
}
