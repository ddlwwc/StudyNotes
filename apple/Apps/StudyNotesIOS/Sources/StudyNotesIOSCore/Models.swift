import Foundation

public struct KnowledgeBaseSummary: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public let createdAt: Date

    public init(id: UUID, name: String, createdAt: Date) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

public struct IOSFolder: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let knowledgeBaseID: UUID
    public let name: String
    public let path: String
    public let parentPath: String

    public var id: String {
        "\(knowledgeBaseID.uuidString)/\(path)"
    }

    public init(
        knowledgeBaseID: UUID,
        name: String,
        path: String,
        parentPath: String
    ) {
        self.knowledgeBaseID = knowledgeBaseID
        self.name = name
        self.path = path
        self.parentPath = parentPath
    }
}

public enum IOSRootState: Equatable, Sendable {
    case available(URL, isICloud: Bool)
    case iCloudNotSignedIn
    case iCloudContainerUnavailable
    case localFallback(URL)

    public var url: URL? {
        switch self {
        case let .available(url, _), let .localFallback(url):
            url
        case .iCloudNotSignedIn, .iCloudContainerUnavailable:
            nil
        }
    }

    public var label: String {
        switch self {
        case .available(_, true):
            "iCloud 已连接"
        case .available(_, false):
            "本地目录"
        case .iCloudNotSignedIn:
            "尚未登录 iCloud"
        case .iCloudContainerUnavailable:
            "iCloud 容器不可用"
        case .localFallback:
            "本地演练目录"
        }
    }
}

public enum MaterialContentKind: String, Codable, CaseIterable, Sendable {
    case markdown
    case html
    case webArticle
    case pdf
    case image
    case note
    case unknown

    public var label: String {
        switch self {
        case .markdown:
            "Markdown"
        case .html, .webArticle:
            "网页文章"
        case .pdf:
            "PDF"
        case .image:
            "图片"
        case .note:
            "笔记"
        case .unknown:
            "学习材料"
        }
    }

    public var supportsTextAnnotation: Bool {
        switch self {
        case .markdown, .html, .webArticle, .note, .pdf:
            true
        case .image, .unknown:
            false
        }
    }
}

public struct MaterialManifestRecord: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let id: UUID
    public let knowledgeBaseID: UUID?
    public let kind: String
    public let title: String
    public let createdAt: Date
    public let updatedAt: Date
    public let folderPath: String
    public let tags: [String]
    public let deletedAt: Date?

    public init(
        schemaVersion: Int = 1,
        id: UUID,
        knowledgeBaseID: UUID?,
        kind: String,
        title: String,
        createdAt: Date,
        updatedAt: Date,
        folderPath: String = "",
        tags: [String] = [],
        deletedAt: Date? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.knowledgeBaseID = knowledgeBaseID
        self.kind = kind
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.folderPath = folderPath
        self.tags = tags
        self.deletedAt = deletedAt
    }

    public var contentKind: MaterialContentKind {
        switch kind.lowercased() {
        case "note":
            .note
        case "markdown", "md":
            .markdown
        case "html":
            .html
        case "webarticle", "web_article", "article":
            .webArticle
        case "pdf":
            .pdf
        case "image", "photo":
            .image
        default:
            .unknown
        }
    }
}

public enum MaterialAccessState: Equatable, Sendable {
    case metadataOnly
    case downloading
    case downloaded
    case offline
    case failed(String)

    public var label: String {
        switch self {
        case .metadataOnly:
            "按需下载"
        case .downloading:
            "正在下载"
        case .downloaded:
            "已下载"
        case .offline:
            "已离线"
        case .failed:
            "下载失败"
        }
    }
}

public struct LibraryMaterial: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let manifest: MaterialManifestRecord
    public let knowledgeBaseName: String
    public let packageURL: URL
    public let accessState: MaterialAccessState

    public init(
        manifest: MaterialManifestRecord,
        knowledgeBaseName: String,
        packageURL: URL,
        accessState: MaterialAccessState
    ) {
        self.id = manifest.id
        self.manifest = manifest
        self.knowledgeBaseName = knowledgeBaseName
        self.packageURL = packageURL
        self.accessState = accessState
    }

    public var title: String { manifest.title }
    public var tags: [String] { manifest.tags }
    public var folderPath: String { manifest.folderPath }
    public var kind: MaterialContentKind { manifest.contentKind }
    public var isAvailableOffline: Bool { accessState == .offline }
    public var isTextSearchable: Bool {
        accessState == .downloaded || accessState == .offline
    }
}

public struct MaterialDocument: Identifiable, Equatable, Sendable {
    public let material: LibraryMaterial
    public let packageURL: URL
    public let contentURL: URL
    public let sourceText: String?

    public var id: UUID { material.id }

    public init(
        material: LibraryMaterial,
        packageURL: URL,
        contentURL: URL,
        sourceText: String?
    ) {
        self.material = material
        self.packageURL = packageURL
        self.contentURL = contentURL
        self.sourceText = sourceText
    }
}

public struct IOSLibrarySnapshot: Equatable, Sendable {
    public let knowledgeBases: [KnowledgeBaseSummary]
    public let materials: [LibraryMaterial]
    public let folders: [IOSFolder]
    public let rootURL: URL?
    public let isICloud: Bool
    public let refreshedAt: Date

    public init(
        knowledgeBases: [KnowledgeBaseSummary],
        materials: [LibraryMaterial],
        folders: [IOSFolder] = [],
        rootURL: URL?,
        isICloud: Bool,
        refreshedAt: Date = Date()
    ) {
        self.knowledgeBases = knowledgeBases
        self.materials = materials
        self.folders = folders
        self.rootURL = rootURL
        self.isICloud = isICloud
        self.refreshedAt = refreshedAt
    }

    public static let empty = IOSLibrarySnapshot(
        knowledgeBases: [],
        materials: [],
        rootURL: nil,
        isICloud: false
    )

    public var downloadedMaterials: [LibraryMaterial] {
        materials.filter(\.isTextSearchable)
    }
}

public struct FolderNode: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let path: String
    public let children: [FolderNode]
    public let materialCount: Int

    public init(
        name: String,
        path: String,
        children: [FolderNode],
        materialCount: Int
    ) {
        self.id = path
        self.name = name
        self.path = path
        self.children = children
        self.materialCount = materialCount
    }
}

public struct NormalizedRectangle: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = min(max(x, 0), 1)
        self.y = min(max(y, 0), 1)
        self.width = min(max(width, 0), 1 - self.x)
        self.height = min(max(height, 0), 1 - self.y)
    }

    public func isApproximatelyEqual(to other: NormalizedRectangle, tolerance: Double = 0.015) -> Bool {
        abs(x - other.x) < tolerance
            && abs(y - other.y) < tolerance
            && abs(width - other.width) < tolerance
            && abs(height - other.height) < tolerance
    }
}

public struct TextAnchor: Codable, Equatable, Sendable {
    public let quote: String
    public let prefix: String
    public let suffix: String
    public let startOffset: Int
    public let endOffset: Int
    public let blockPath: String

    public init(
        quote: String,
        prefix: String = "",
        suffix: String = "",
        startOffset: Int,
        endOffset: Int,
        blockPath: String
    ) {
        self.quote = quote
        self.prefix = prefix
        self.suffix = suffix
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.blockPath = blockPath
    }
}

public enum AnnotationAnchor: Codable, Equatable, Sendable {
    case text(TextAnchor)
    case imageRectangle(NormalizedRectangle)
    case pageRectangle(page: Int, rectangle: NormalizedRectangle)
    case wholeMaterial

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case rectangle
        case page
    }

    private enum AnchorType: String, Codable {
        case text
        case imageRectangle
        case pageRectangle
        case wholeMaterial
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(AnchorType.self, forKey: .type) {
        case .text:
            self = .text(try container.decode(TextAnchor.self, forKey: .text))
        case .imageRectangle:
            self = .imageRectangle(try container.decode(NormalizedRectangle.self, forKey: .rectangle))
        case .pageRectangle:
            self = .pageRectangle(
                page: try container.decode(Int.self, forKey: .page),
                rectangle: try container.decode(NormalizedRectangle.self, forKey: .rectangle)
            )
        case .wholeMaterial:
            self = .wholeMaterial
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(anchor):
            try container.encode(AnchorType.text, forKey: .type)
            try container.encode(anchor, forKey: .text)
        case let .imageRectangle(rectangle):
            try container.encode(AnchorType.imageRectangle, forKey: .type)
            try container.encode(rectangle, forKey: .rectangle)
        case let .pageRectangle(page, rectangle):
            try container.encode(AnchorType.pageRectangle, forKey: .type)
            try container.encode(page, forKey: .page)
            try container.encode(rectangle, forKey: .rectangle)
        case .wholeMaterial:
            try container.encode(AnchorType.wholeMaterial, forKey: .type)
        }
    }
}

public enum AnnotationResolution: String, Codable, Equatable, Sendable {
    case resolved
    case needsRecovery

    public var label: String {
        switch self {
        case .resolved:
            "位置已恢复"
        case .needsRecovery:
            "位置待恢复"
        }
    }
}

public struct StudyAnnotation: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let materialID: UUID
    public var anchor: AnnotationAnchor
    public var note: String
    public let createdAt: Date
    public var updatedAt: Date
    public var resolution: AnnotationResolution

    public init(
        id: UUID = UUID(),
        materialID: UUID,
        anchor: AnnotationAnchor,
        note: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        resolution: AnnotationResolution = .resolved
    ) {
        self.id = id
        self.materialID = materialID
        self.anchor = anchor
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.resolution = resolution
    }

    public var quote: String? {
        guard case let .text(textAnchor) = anchor else {
            return nil
        }
        return textAnchor.quote
    }
}

public enum InboxItemKind: String, Codable, CaseIterable, Sendable {
    case url
    case image
    case text

    public var label: String {
        switch self {
        case .url:
            "网页链接"
        case .image:
            "图片"
        case .text:
            "文本片段"
        }
    }
}

public struct InboxManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let id: UUID
    public let kind: InboxItemKind
    public let title: String
    public let createdAt: Date
    public let payloadFile: String
    public let source: String

    public init(
        schemaVersion: Int = 1,
        id: UUID = UUID(),
        kind: InboxItemKind,
        title: String,
        createdAt: Date = Date(),
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

public struct InboxItem: Identifiable, Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case pending
        case collected
        case failed(String)
    }

    public let id: UUID
    public let kind: InboxItemKind
    public let title: String
    public let createdAt: Date
    public let status: Status
    public let localPayloadURL: URL?

    public init(
        id: UUID,
        kind: InboxItemKind,
        title: String,
        createdAt: Date,
        status: Status,
        localPayloadURL: URL? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.createdAt = createdAt
        self.status = status
        self.localPayloadURL = localPayloadURL
    }
}

public struct InboxDraft: Equatable, Sendable {
    public let id: UUID
    public let kind: InboxItemKind
    public let title: String
    public let payloadFileExtension: String
    public let payloadData: Data
    public let source: String
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        kind: InboxItemKind,
        title: String,
        payloadFileExtension: String,
        payloadData: Data,
        source: String = "iOS",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.payloadFileExtension = payloadFileExtension
        self.payloadData = payloadData
        self.source = source
        self.createdAt = createdAt
    }
}

public struct SearchHit: Identifiable, Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case metadata
        case content
        case annotation
        case ai

        public var label: String {
            switch self {
            case .metadata:
                "标题、标签、目录"
            case .content:
                "正文"
            case .annotation:
                "标注"
            case .ai:
                "AI 研读结果"
            }
        }
    }

    public let id: String
    public let materialID: UUID
    public let title: String
    public let kind: Kind
    public let snippet: String

    public init(
        materialID: UUID,
        title: String,
        kind: Kind,
        snippet: String
    ) {
        self.id = "\(materialID.uuidString)-\(kind.rawValue)-\(snippet.hashValue)"
        self.materialID = materialID
        self.title = title
        self.kind = kind
        self.snippet = snippet
    }
}

public struct AIConversation: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let materialID: UUID
    public let providerName: String
    public var modelID: String
    public let action: String
    public let scopeDescription: String
    public var title: String
    public var origin: AIConversationOrigin
    public var originAnchor: AnnotationAnchor?
    public var status: AIStudySessionStatus
    public let createdAt: Date
    public var updatedAt: Date
    public var messages: [AIMessage]

    public init(
        id: UUID = UUID(),
        materialID: UUID,
        providerName: String,
        modelID: String,
        action: String,
        scopeDescription: String,
        title: String? = nil,
        origin: AIConversationOrigin? = nil,
        originAnchor: AnnotationAnchor? = nil,
        status: AIStudySessionStatus = .active,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        messages: [AIMessage] = []
    ) {
        self.id = id
        self.materialID = materialID
        self.providerName = providerName
        self.modelID = modelID
        self.action = action
        self.scopeDescription = scopeDescription
        self.title = title ?? (action == "总结" ? "整篇总结" : action)
        self.origin = origin ?? (action == "总结" ? .summary : .selection)
        self.originAnchor = originAnchor
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
    }

    public var model: String {
        get { modelID }
        set { modelID = newValue }
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

public struct AIMessage: Identifiable, Codable, Equatable, Sendable {
    public enum Role: String, Codable, Sendable {
        case system
        case user
        case assistant
    }

    public let id: UUID
    public let role: Role
    public var content: String
    public let createdAt: Date
    public var promptTokens: Int?
    public var completionTokens: Int?

    public init(
        id: UUID = UUID(),
        role: Role,
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

public struct AIProvider: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var baseURL: String
    public var modelID: String
    public var syncKeychain: Bool { false }

    public init(
        id: UUID = UUID(),
        name: String,
        baseURL: String,
        modelID: String,
        syncKeychain: Bool = false
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.modelID = modelID
    }

    public var isConfigured: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && URL(string: baseURL)?.scheme != nil
            && !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case baseURL
        case modelID
        case syncKeychain
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        baseURL = try container.decode(String.self, forKey: .baseURL)
        modelID = try container.decode(String.self, forKey: .modelID)
        _ = try container.decodeIfPresent(Bool.self, forKey: .syncKeychain)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(baseURL, forKey: .baseURL)
        try container.encode(modelID, forKey: .modelID)
        try container.encode(false, forKey: .syncKeychain)
    }
}

public struct AIContext: Equatable, Sendable {
    public let action: String
    public let text: String
    public let scopeDescription: String

    public init(action: String, text: String, scopeDescription: String) {
        self.action = action
        self.text = text
        self.scopeDescription = scopeDescription
    }

    public var approximateLength: Int {
        text.count
    }

    public var requiresWholeMaterialConfirmation: Bool {
        action == "总结" || scopeDescription.contains("整份材料")
    }
}

public enum AIStreamEvent: Equatable, Sendable {
    case delta(String)
    case usage(promptTokens: Int?, completionTokens: Int?)
    case completed
}

public enum StudyNotesIOSError: Error, Equatable, LocalizedError, Sendable {
    case noWorkspace
    case materialNotFound
    case materialNotDownloaded
    case unreadableContent
    case malformedManifest(String)
    case inboxWriteFailed(String)
    case keychain(Int32)
    case invalidProvider
    case missingAPIKey
    case malformedStream
    case unsupportedMaterial

    public var errorDescription: String? {
        switch self {
        case .noWorkspace:
            "尚未连接 StudyNotes 学习目录。"
        case .materialNotFound:
            "没有找到学习材料。"
        case .materialNotDownloaded:
            "学习材料正文尚未下载。"
        case .unreadableContent:
            "无法读取学习材料正文。"
        case let .malformedManifest(reason):
            "学习材料包格式无效：\(reason)"
        case let .inboxWriteFailed(reason):
            "收件箱写入失败：\(reason)"
        case .keychain(let status):
            "钥匙串操作失败（\(status)）。"
        case .invalidProvider:
            "AI 供应商配置无效。"
        case .missingAPIKey:
            "尚未保存该供应商的 API Key。"
        case .malformedStream:
            "AI 流式响应格式无效。"
        case .unsupportedMaterial:
            "当前学习材料类型暂不支持此操作。"
        }
    }
}
