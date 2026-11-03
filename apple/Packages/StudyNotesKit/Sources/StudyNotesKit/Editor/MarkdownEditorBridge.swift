import Foundation

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
