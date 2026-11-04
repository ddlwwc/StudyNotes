import Foundation

public struct EditorDocumentBlockEnvelope: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let type: String
    public let version: Int
    public let fallback: String
    public let data: JSONValue?

    public init(
        id: UUID,
        type: String,
        version: Int = EditorBlockEnvelope.currentVersion,
        fallback: String,
        data: JSONValue? = nil
    ) {
        self.id = id
        self.type = type
        self.version = version
        self.fallback = fallback
        self.data = data
    }

    public init(editorBlock: EditorBlockEnvelope) {
        self.init(
            id: editorBlock.id,
            type: editorBlock.type.storageName,
            version: editorBlock.version,
            fallback: editorBlock.fallback,
            data: editorBlock.data
        )
    }

    public func editorBlock() -> EditorBlockEnvelope? {
        guard let blockType = EditorBlockKind(storageName: type) else {
            return nil
        }
        return EditorBlockEnvelope(
            id: id,
            type: blockType,
            version: version,
            fallback: fallback,
            data: data
        )
    }

    func validate() throws {
        guard version == EditorBlockEnvelope.currentVersion else {
            throw StudyNotesError.editorDocumentBlockVersionUnsupported(
                blockID: id,
                version: version
            )
        }
        guard let editorBlock = editorBlock() else {
            throw StudyNotesError.editorDocumentBlockInvalid(
                blockID: id,
                reason: "未知块类型 \(type)。"
            )
        }
        do {
            try editorBlock.validate()
            _ = try CrossPlatformJSON.encoder().encode(self)
        } catch {
            throw StudyNotesError.editorDocumentBlockInvalid(
                blockID: id,
                reason: error.localizedDescription
            )
        }
    }
}

public struct EditorDocumentState: Identifiable, Codable, Equatable, Sendable {
    public let materialID: UUID
    public let title: String
    public let markdown: String
    public let blocks: [EditorDocumentBlockEnvelope]
    public let isLocked: Bool
    public let currentGenerationID: UUID?
    public let contentFingerprint: String
    public let derivedRebuildPending: Bool

    public var id: UUID { materialID }

    public init(
        materialID: UUID,
        title: String,
        markdown: String,
        blocks: [EditorDocumentBlockEnvelope],
        isLocked: Bool,
        currentGenerationID: UUID?,
        contentFingerprint: String,
        derivedRebuildPending: Bool
    ) {
        self.materialID = materialID
        self.title = title
        self.markdown = markdown
        self.blocks = blocks
        self.isLocked = isLocked
        self.currentGenerationID = currentGenerationID
        self.contentFingerprint = contentFingerprint
        self.derivedRebuildPending = derivedRebuildPending
    }
}

public struct EditorDocumentSaveRequest: Codable, Equatable, Sendable {
    public let transactionID: UUID
    public let createdAt: Date
    public let materialID: UUID
    public let title: String
    public let markdown: String
    public let blocks: [EditorDocumentBlockEnvelope]
    public let expectedContentFingerprint: String

    public init(
        transactionID: UUID = UUID(),
        createdAt: Date = Date(),
        materialID: UUID,
        title: String,
        markdown: String,
        blocks: [EditorDocumentBlockEnvelope],
        expectedContentFingerprint: String
    ) {
        self.transactionID = transactionID
        self.createdAt = createdAt
        self.materialID = materialID
        self.title = title
        self.markdown = markdown
        self.blocks = blocks
        self.expectedContentFingerprint = expectedContentFingerprint
    }
}

public struct EditorDocumentTransaction: Identifiable, Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let id: UUID
    public let materialID: UUID
    public let createdAt: Date
    public let baseContentFingerprint: String
    public let generationID: UUID
    public let contentFingerprint: String
    public let title: String
    public let markdown: String
    public let blocks: [EditorDocumentBlockEnvelope]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        id: UUID,
        materialID: UUID,
        createdAt: Date,
        baseContentFingerprint: String,
        generationID: UUID,
        contentFingerprint: String,
        title: String,
        markdown: String,
        blocks: [EditorDocumentBlockEnvelope]
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.materialID = materialID
        self.createdAt = createdAt
        self.baseContentFingerprint = baseContentFingerprint
        self.generationID = generationID
        self.contentFingerprint = contentFingerprint
        self.title = title
        self.markdown = markdown
        self.blocks = blocks
    }
}

struct EditorDocumentContent: Equatable, Sendable {
    let markdown: String
    let blocks: [EditorDocumentBlockEnvelope]
    let generationID: UUID?
    let fingerprint: String
}

enum EditorDocumentFingerprint {
    static func make(
        markdown: String,
        blocks: [EditorDocumentBlockEnvelope]
    ) throws -> String {
        guard !blocks.isEmpty else {
            return ContentFingerprint.sha256(markdown)
        }
        var data = Data("studynotes-editor-document-v1\0".utf8)
        data.append(Data(markdown.utf8))
        data.append(0)
        data.append(try CrossPlatformJSON.encoder().encode(blocks))
        return ContentFingerprint.sha256(data)
    }
}

struct EditorDocumentBlockMarker: Equatable, Sendable {
    let id: UUID
    let type: String
    let version: Int
}

enum EditorDocumentBlockMarkerParser {
    private static let openingPattern = #"<!--\s*studynotes:block\b([^>]*)-->"#
    private static let closingPattern = #"<!--\s*/studynotes:block\s*-->"#
    private static let attributePattern = #"([A-Za-z][A-Za-z0-9_-]*)\s*=\s*"([^"]*)""#

    static func parse(_ markdown: String) throws -> [EditorDocumentBlockMarker] {
        let range = NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
        let openingExpression = try NSRegularExpression(pattern: openingPattern)
        let closingExpression = try NSRegularExpression(pattern: closingPattern)
        let openings = openingExpression.matches(in: markdown, range: range)
        let closings = closingExpression.matches(in: markdown, range: range)

        guard openings.count == closings.count else {
            throw StudyNotesError.editorDocumentMarkersInvalid(
                reason: "旁路块开始标记与结束标记数量不一致。"
            )
        }

        return try openings.map { match in
            let attributeRange = match.range(at: 1)
            guard let swiftRange = Range(attributeRange, in: markdown) else {
                throw StudyNotesError.editorDocumentMarkersInvalid(
                    reason: "无法读取旁路块标记属性。"
                )
            }
            let attributes = try parseAttributes(String(markdown[swiftRange]))
            guard let rawID = attributes["id"],
                  let id = UUID(uuidString: rawID) else {
                throw StudyNotesError.editorDocumentMarkersInvalid(
                    reason: "旁路块标记缺少有效 id。"
                )
            }
            guard let type = attributes["type"],
                  !type.isEmpty else {
                throw StudyNotesError.editorDocumentMarkersInvalid(
                    reason: "旁路块 \(id.uuidString) 的 type 无效。"
                )
            }
            guard let rawVersion = attributes["version"],
                  let version = Int(rawVersion) else {
                throw StudyNotesError.editorDocumentMarkersInvalid(
                    reason: "旁路块 \(id.uuidString) 的 version 无效。"
                )
            }
            return EditorDocumentBlockMarker(
                id: id,
                type: type,
                version: version
            )
        }
    }

    private static func parseAttributes(_ source: String) throws -> [String: String] {
        let expression = try NSRegularExpression(pattern: attributePattern)
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        var attributes: [String: String] = [:]
        for match in expression.matches(in: source, range: range) {
            guard let nameRange = Range(match.range(at: 1), in: source),
                  let valueRange = Range(match.range(at: 2), in: source) else {
                continue
            }
            attributes[String(source[nameRange])] = String(source[valueRange])
        }
        guard !attributes.isEmpty else {
            throw StudyNotesError.editorDocumentMarkersInvalid(
                reason: "旁路块标记没有属性。"
            )
        }
        return attributes
    }
}

func validateEditorDocumentBlocks(
    _ blocks: [EditorDocumentBlockEnvelope],
    markdown: String
) throws -> [EditorDocumentBlockMarker] {
    let markers = try EditorDocumentBlockMarkerParser.parse(markdown)
    var blocksByID: [UUID: EditorDocumentBlockEnvelope] = [:]

    for block in blocks {
        guard blocksByID.updateValue(block, forKey: block.id) == nil else {
            throw StudyNotesError.editorDocumentBlockInvalid(
                blockID: block.id,
                reason: "文档中存在重复块 ID。"
            )
        }
        try block.validate()
    }

    var markerIDs = Set<UUID>()
    for marker in markers {
        guard markerIDs.insert(marker.id).inserted else {
            throw StudyNotesError.editorDocumentBlockInvalid(
                blockID: marker.id,
                reason: "Markdown 中存在重复块标记。"
            )
        }
        guard let block = blocksByID.removeValue(forKey: marker.id) else {
            throw StudyNotesError.editorDocumentBlockMissing(blockID: marker.id)
        }
        guard marker.version == EditorBlockEnvelope.currentVersion else {
            throw StudyNotesError.editorDocumentBlockVersionUnsupported(
                blockID: marker.id,
                version: marker.version
            )
        }
        guard marker.type == block.type,
              marker.version == block.version else {
            throw StudyNotesError.editorDocumentBlockInvalid(
                blockID: marker.id,
                reason: "Markdown 标记与 block.json 的类型或版本不一致。"
            )
        }
    }

    if let orphan = blocksByID.keys.first {
        throw StudyNotesError.editorDocumentBlockMarkerMissing(blockID: orphan)
    }
    return markers
}

private extension EditorBlockKind {
    init?(storageName: String) {
        switch storageName {
        case "data-table": self = .dataTable
        case "table-of-contents": self = .tableOfContents
        case "mind-map": self = .mindMap
        case "document-card": self = .documentCard
        default:
            self.init(rawValue: storageName)
        }
    }

    var storageName: String {
        switch self {
        case .dataTable: "data-table"
        case .tableOfContents: "table-of-contents"
        case .mindMap: "mind-map"
        case .documentCard: "document-card"
        default: rawValue
        }
    }
}
