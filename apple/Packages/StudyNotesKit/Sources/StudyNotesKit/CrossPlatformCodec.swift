import Foundation

public enum CrossPlatformCodecError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedAnnotationAnchor(String)
    case invalidAnnotation(String)
    case invalidConversation(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedAnnotationAnchor(kind):
            "无法识别的标注锚点类型：\(kind)"
        case let .invalidAnnotation(reason):
            "标注文件格式无效：\(reason)"
        case let .invalidConversation(reason):
            "AI 会话文件格式无效：\(reason)"
        }
    }
}

public enum CrossPlatformJSON {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public struct CrossPlatformRect: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public enum CrossPlatformAnnotationKind: String, Codable, Equatable, Sendable {
    case text
    case imageRect
    case pdfText
    case pdfPageRect
    case wholeMaterial
}

public struct CrossPlatformAnnotationAnchor: Codable, Equatable, Sendable {
    public let kind: CrossPlatformAnnotationKind
    public let excerpt: String
    public let prefix: String
    public let suffix: String
    public let offset: Int?
    public let blockPath: [Int]
    public let pageIndex: Int?
    public let rect: CrossPlatformRect?

    public init(
        kind: CrossPlatformAnnotationKind,
        excerpt: String = "",
        prefix: String = "",
        suffix: String = "",
        offset: Int? = nil,
        blockPath: [Int] = [],
        pageIndex: Int? = nil,
        rect: CrossPlatformRect? = nil
    ) {
        self.kind = kind
        self.excerpt = excerpt
        self.prefix = prefix
        self.suffix = suffix
        self.offset = offset
        self.blockPath = blockPath
        self.pageIndex = pageIndex
        self.rect = rect
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case type
        case text
        case excerpt
        case quote
        case prefix
        case suffix
        case offset
        case startOffset
        case blockPath
        case pageIndex
        case page
        case rect
        case rectangle
    }

    private struct LegacyTextAnchor: Codable {
        let quote: String
        let prefix: String?
        let suffix: String?
        let startOffset: Int?
        let endOffset: Int?
        let blockPath: String?
    }

    private struct LegacyAnchor: Codable {
        let type: String
        let text: LegacyTextAnchor?
        let rectangle: CrossPlatformRect?
        let page: Int?
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.type) {
            let legacy = try LegacyAnchor(from: decoder)
            switch legacy.type {
            case "text":
                let text = legacy.text
                self.init(
                    kind: .text,
                    excerpt: text?.quote ?? "",
                    prefix: text?.prefix ?? "",
                    suffix: text?.suffix ?? "",
                    offset: text?.startOffset,
                    blockPath: Self.blockPath(from: text?.blockPath)
                )
            case "imageRectangle":
                self.init(kind: .imageRect, rect: legacy.rectangle)
            case "pageRectangle":
                self.init(
                    kind: .pdfPageRect,
                    pageIndex: legacy.page,
                    rect: legacy.rectangle
                )
            case "wholeMaterial":
                self.init(kind: .wholeMaterial)
            default:
                throw CrossPlatformCodecError.unsupportedAnnotationAnchor(legacy.type)
            }
            return
        }

        let kind = try container.decode(CrossPlatformAnnotationKind.self, forKey: .kind)
        let blockPath = try container.decodeIfPresent([Int].self, forKey: .blockPath) ?? []
        self.init(
            kind: kind,
            excerpt: try container.decodeIfPresent(String.self, forKey: .excerpt) ?? "",
            prefix: try container.decodeIfPresent(String.self, forKey: .prefix) ?? "",
            suffix: try container.decodeIfPresent(String.self, forKey: .suffix) ?? "",
            offset: try container.decodeIfPresent(Int.self, forKey: .offset),
            blockPath: blockPath,
            pageIndex: try container.decodeIfPresent(Int.self, forKey: .pageIndex)
                ?? (try container.decodeIfPresent(Int.self, forKey: .page)),
            rect: try container.decodeIfPresent(CrossPlatformRect.self, forKey: .rect)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(excerpt, forKey: .excerpt)
        try container.encode(prefix, forKey: .prefix)
        try container.encode(suffix, forKey: .suffix)
        try container.encodeIfPresent(offset, forKey: .offset)
        try container.encode(blockPath, forKey: .blockPath)
        try container.encodeIfPresent(pageIndex, forKey: .pageIndex)
        try container.encodeIfPresent(rect, forKey: .rect)
    }

    private static func blockPath(from value: String?) -> [Int] {
        guard let value else {
            return []
        }
        let numbers = value
            .split(separator: "/")
            .compactMap { component -> Int? in
                let digits = component.replacingOccurrences(
                    of: #"[^0-9]"#,
                    with: "",
                    options: .regularExpression
                )
                return Int(digits)
            }
        return numbers
    }
}

public struct CrossPlatformAnnotation: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let id: UUID
    public let materialID: UUID
    public let anchor: CrossPlatformAnnotationAnchor
    public let quote: String
    public let note: String
    public let status: String
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        schemaVersion: Int = 1,
        id: UUID,
        materialID: UUID,
        anchor: CrossPlatformAnnotationAnchor,
        quote: String,
        note: String,
        status: String,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.schemaVersion = schemaVersion
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
        case schemaVersion
        case id
        case materialID
        case anchor
        case quote
        case note
        case status
        case resolution
        case createdAt
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            id = try container.decode(UUID.self, forKey: .id)
            materialID = try container.decode(UUID.self, forKey: .materialID)
            anchor = try container.decode(
                CrossPlatformAnnotationAnchor.self,
                forKey: .anchor
            )
        } catch {
            throw CrossPlatformCodecError.invalidAnnotation(error.localizedDescription)
        }
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        let fallbackQuote = anchor.excerpt
        quote = try container.decodeIfPresent(String.self, forKey: .quote)
            ?? fallbackQuote
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        if let rawStatus = try container.decodeIfPresent(String.self, forKey: .status) {
            status = rawStatus
        } else if let resolution = try container.decodeIfPresent(
            String.self,
            forKey: .resolution
        ) {
            status = resolution == "needsRecovery" ? "unresolved" : "active"
        } else {
            status = "active"
        }
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
            ?? createdAt
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(id, forKey: .id)
        try container.encode(materialID, forKey: .materialID)
        try container.encode(anchor, forKey: .anchor)
        try container.encode(quote, forKey: .quote)
        try container.encode(note, forKey: .note)
        try container.encode(status, forKey: .status)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

public enum CrossPlatformAIMessageRole: String, Codable, Equatable, Sendable {
    case system
    case user
    case assistant
}

public struct CrossPlatformAIMessage: Codable, Equatable, Sendable {
    public let id: UUID
    public let role: CrossPlatformAIMessageRole
    public let content: String
    public let createdAt: Date
    public let promptTokens: Int?
    public let completionTokens: Int?

    public init(
        id: UUID,
        role: CrossPlatformAIMessageRole,
        content: String,
        createdAt: Date,
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

public enum CrossPlatformAIConversationOrigin: String, Codable, Equatable, Sendable {
    case selection
    case summary
}

public struct CrossPlatformAIStudySession: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let id: UUID
    public let materialID: UUID
    public let providerName: String
    public let model: String
    public let title: String
    public let action: String
    public let scopeDescription: String
    public let origin: CrossPlatformAIConversationOrigin
    public let status: String
    public let originAnchor: CrossPlatformAnnotationAnchor?
    public let messages: [CrossPlatformAIMessage]
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        schemaVersion: Int = 1,
        id: UUID,
        materialID: UUID,
        providerName: String,
        model: String,
        title: String,
        action: String,
        scopeDescription: String,
        origin: CrossPlatformAIConversationOrigin,
        status: String,
        originAnchor: CrossPlatformAnnotationAnchor? = nil,
        messages: [CrossPlatformAIMessage],
        createdAt: Date,
        updatedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.materialID = materialID
        self.providerName = providerName
        self.model = model
        self.title = title
        self.action = action
        self.scopeDescription = scopeDescription
        self.origin = origin
        self.status = status
        self.originAnchor = originAnchor
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case materialID
        case providerName
        case model
        case modelID
        case title
        case action
        case scopeDescription
        case origin
        case status
        case originAnchor
        case messages
        case createdAt
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            id = try container.decode(UUID.self, forKey: .id)
            materialID = try container.decode(UUID.self, forKey: .materialID)
            messages = try container.decodeIfPresent(
                [CrossPlatformAIMessage].self,
                forKey: .messages
            ) ?? []
        } catch {
            throw CrossPlatformCodecError.invalidConversation(error.localizedDescription)
        }
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        providerName = try container.decodeIfPresent(String.self, forKey: .providerName) ?? ""
        model = try container.decodeIfPresent(String.self, forKey: .model)
            ?? (try container.decodeIfPresent(String.self, forKey: .modelID))
            ?? ""
        let decodedOrigin = try container.decodeIfPresent(
            CrossPlatformAIConversationOrigin.self,
            forKey: .origin
        )
        action = try container.decodeIfPresent(String.self, forKey: .action)
            ?? (decodedOrigin == .summary ? "总结" : "解释")
        origin = decodedOrigin ?? (action == "总结" ? .summary : .selection)
        scopeDescription = try container.decodeIfPresent(
            String.self,
            forKey: .scopeDescription
        ) ?? (origin == .summary ? "整份材料" : "")
        title = try container.decodeIfPresent(String.self, forKey: .title)
            ?? (origin == .summary ? "整篇总结" : action)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "active"
        originAnchor = try container.decodeIfPresent(
            CrossPlatformAnnotationAnchor.self,
            forKey: .originAnchor
        )
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
            ?? createdAt
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(id, forKey: .id)
        try container.encode(materialID, forKey: .materialID)
        try container.encode(providerName, forKey: .providerName)
        try container.encode(model, forKey: .model)
        try container.encode(model, forKey: .modelID)
        try container.encode(title, forKey: .title)
        try container.encode(action, forKey: .action)
        try container.encode(scopeDescription, forKey: .scopeDescription)
        try container.encode(origin, forKey: .origin)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(originAnchor, forKey: .originAnchor)
        try container.encode(messages, forKey: .messages)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

public enum CrossPlatformInboxItemKind: String, Codable, Equatable, Sendable {
    case url
    case image
    case text
}

public struct CrossPlatformInboxManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let id: UUID
    public let kind: CrossPlatformInboxItemKind
    public let title: String
    public let createdAt: Date
    public let payloadFile: String
    public let source: String

    public init(
        schemaVersion: Int = 1,
        id: UUID,
        kind: CrossPlatformInboxItemKind,
        title: String,
        createdAt: Date,
        payloadFile: String,
        source: String
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.kind = kind
        self.title = title
        self.createdAt = createdAt
        self.payloadFile = payloadFile
        self.source = source
    }
}
