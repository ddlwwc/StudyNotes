import Foundation

public enum EditorBlockKind: String, Codable, CaseIterable, Sendable {
    case paragraph
    case heading
    case callout
    case status
    case divider
    case columns
    case toggle
    case tableOfContents = "toc"
    case code
    case formula
    case mermaid
    case table
    case dataTable = "data-table"
    case whiteboard
    case mindMap = "mind-map"
    case flowchart
    case image
    case attachment
    case audio
    case video
    case link
    case documentCard = "document-card"

    public var requiresBypassData: Bool {
        switch self {
        case .callout, .status, .columns, .toggle, .code, .formula,
             .mermaid, .table, .dataTable, .whiteboard, .mindMap,
             .flowchart, .image, .attachment, .audio, .video,
             .documentCard:
            true
        case .paragraph, .heading, .divider, .tableOfContents, .link:
            false
        }
    }
}

public struct EditorBlockEnvelope: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let id: UUID
    public let type: EditorBlockKind
    public let version: Int
    public let fallback: String
    public let data: JSONValue?

    public init(
        id: UUID,
        type: EditorBlockKind,
        version: Int = Self.currentVersion,
        fallback: String,
        data: JSONValue? = nil
    ) {
        self.id = id
        self.type = type
        self.version = version
        self.fallback = fallback
        self.data = data
    }

    public func validate() throws {
        guard version == Self.currentVersion else {
            throw EditorBlockError.unsupportedVersion(
                blockID: id,
                version: version
            )
        }
        guard !fallback.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw EditorBlockError.missingFallback(blockID: id)
        }
        if type.requiresBypassData, data == nil {
            throw EditorBlockError.missingBypassData(blockID: id)
        }
    }
}

public enum EditorBlockError: Error, Equatable, Sendable, LocalizedError {
    case unsupportedVersion(blockID: UUID, version: Int)
    case missingFallback(blockID: UUID)
    case missingBypassData(blockID: UUID)
    case duplicateBlockID(UUID)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedVersion(blockID, version):
            "块 \(blockID.uuidString) 使用未知版本 \(version)。"
        case let .missingFallback(blockID):
            "块 \(blockID.uuidString) 缺少可读降级内容。"
        case let .missingBypassData(blockID):
            "块 \(blockID.uuidString) 缺少完整旁路数据。"
        case let .duplicateBlockID(blockID):
            "文档中存在重复块 ID：\(blockID.uuidString)。"
        }
    }
}

public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(
                try container.decode([String: JSONValue].self)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case let .bool(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        }
    }

    public subscript(key: String) -> JSONValue? {
        guard case let .object(value) = self else {
            return nil
        }
        return value[key]
    }

    public var stringValue: String? {
        guard case let .string(value) = self else {
            return nil
        }
        return value
    }

    public var numberValue: Double? {
        guard case let .number(value) = self else {
            return nil
        }
        return value
    }

    public var boolValue: Bool? {
        guard case let .bool(value) = self else {
            return nil
        }
        return value
    }

    public var arrayValue: [JSONValue]? {
        guard case let .array(value) = self else {
            return nil
        }
        return value
    }

    public var objectValue: [String: JSONValue]? {
        guard case let .object(value) = self else {
            return nil
        }
        return value
    }
}

public enum DataTableFieldType: String, Codable, CaseIterable, Sendable {
    case text
    case multilineText
    case number
    case singleSelect
    case multiSelect
    case checkbox
    case date
    case dateTime
    case url
    case email
    case attachment
    case formula
    case relation
    case rollup
    case autoNumber
    case createdTime
    case updatedTime
}

public struct DataTableField: Codable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var type: DataTableFieldType
    public var options: [String]
    public var formula: String?
    public var relatedTableBlockID: UUID?
    public var rollupFieldID: String?
    public var aggregation: String?

    public init(
        id: String,
        name: String,
        type: DataTableFieldType,
        options: [String] = [],
        formula: String? = nil,
        relatedTableBlockID: UUID? = nil,
        rollupFieldID: String? = nil,
        aggregation: String? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.options = options
        self.formula = formula
        self.relatedTableBlockID = relatedTableBlockID
        self.rollupFieldID = rollupFieldID
        self.aggregation = aggregation
    }
}

public struct DataTableRecord: Codable, Equatable, Sendable {
    public let id: String
    public var values: [String: JSONValue]
    public var createdAt: Date?
    public var updatedAt: Date?

    public init(
        id: String,
        values: [String: JSONValue] = [:],
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.values = values
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum DataTableViewType: String, Codable, CaseIterable, Sendable {
    case table
    case board
    case calendar
    case gallery
}

public enum DataTableViewOperator: String, Codable, Sendable {
    case equals
    case notEquals
    case contains
    case greaterThan
    case greaterThanOrEqual
    case lessThan
    case lessThanOrEqual
    case isEmpty
    case isNotEmpty
}

public struct DataTableViewFilter: Codable, Equatable, Sendable {
    public let fieldID: String
    public let `operator`: DataTableViewOperator
    public let value: JSONValue?

    public init(
        fieldID: String,
        operator: DataTableViewOperator,
        value: JSONValue? = nil
    ) {
        self.fieldID = fieldID
        self.operator = `operator`
        self.value = value
    }
}

public struct DataTableViewSort: Codable, Equatable, Sendable {
    public let fieldID: String
    public let ascending: Bool

    public init(fieldID: String, ascending: Bool) {
        self.fieldID = fieldID
        self.ascending = ascending
    }
}

public struct DataTableView: Codable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var type: DataTableViewType
    public var filters: [DataTableViewFilter]
    public var sorts: [DataTableViewSort]
    public var groupFieldIDs: [String]
    public var visibleFieldIDs: [String]
    public var columnWidths: [String: Double]

    public init(
        id: String,
        name: String,
        type: DataTableViewType,
        filters: [DataTableViewFilter] = [],
        sorts: [DataTableViewSort] = [],
        groupFieldIDs: [String] = [],
        visibleFieldIDs: [String] = [],
        columnWidths: [String: Double] = [:]
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.filters = filters
        self.sorts = sorts
        self.groupFieldIDs = groupFieldIDs
        self.visibleFieldIDs = visibleFieldIDs
        self.columnWidths = columnWidths
    }
}

public struct DataTableSchema: Codable, Equatable, Sendable {
    public var fields: [DataTableField]

    public init(fields: [DataTableField]) {
        self.fields = fields
    }

    public var fieldByName: [String: DataTableField] {
        Dictionary(uniqueKeysWithValues: fields.map { ($0.name, $0) })
    }

    public var fieldByID: [String: DataTableField] {
        Dictionary(uniqueKeysWithValues: fields.map { ($0.id, $0) })
    }
}

public struct DataTableDocument: Codable, Equatable, Sendable {
    public var schema: DataTableSchema
    public var views: [DataTableView]
    public var records: [DataTableRecord]

    public init(
        schema: DataTableSchema,
        views: [DataTableView] = [],
        records: [DataTableRecord] = []
    ) {
        self.schema = schema
        self.views = views
        self.records = records
    }
}

public struct GraphNode: Codable, Equatable, Sendable {
    public let id: String
    public var label: String
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var parentID: String?
    public var collapsed: Bool
    public var style: [String: JSONValue]

    public init(
        id: String,
        label: String,
        x: Double,
        y: Double,
        width: Double = 160,
        height: Double = 80,
        parentID: String? = nil,
        collapsed: Bool = false,
        style: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.label = label
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.parentID = parentID
        self.collapsed = collapsed
        self.style = style
    }
}

public struct GraphEdge: Codable, Equatable, Sendable {
    public let id: String
    public var from: String
    public var to: String
    public var label: String

    public init(id: String, from: String, to: String, label: String = "") {
        self.id = id
        self.from = from
        self.to = to
        self.label = label
    }
}

public struct GraphScene: Codable, Equatable, Sendable {
    public var nodes: [GraphNode]
    public var edges: [GraphEdge]
    public var zoom: Double
    public var offsetX: Double
    public var offsetY: Double

    public init(
        nodes: [GraphNode],
        edges: [GraphEdge],
        zoom: Double = 1,
        offsetX: Double = 0,
        offsetY: Double = 0
    ) {
        self.nodes = nodes
        self.edges = edges
        self.zoom = zoom
        self.offsetX = offsetX
        self.offsetY = offsetY
    }

    public func validate() throws {
        let nodeIDs = Set(nodes.map(\.id))
        guard nodeIDs.count == nodes.count else {
            throw GraphSceneError.duplicateNodeID
        }
        for edge in edges where
            !nodeIDs.contains(edge.from) || !nodeIDs.contains(edge.to) {
            throw GraphSceneError.danglingEdge(edge.id)
        }
        guard zoom.isFinite, zoom > 0 else {
            throw GraphSceneError.invalidZoom
        }
    }
}

public enum GraphSceneError: Error, Equatable, Sendable, LocalizedError {
    case duplicateNodeID
    case danglingEdge(String)
    case invalidZoom
    case cycle

    public var errorDescription: String? {
        switch self {
        case .duplicateNodeID:
            "图形块包含重复节点 ID。"
        case let .danglingEdge(id):
            "连线 \(id) 引用了不存在的节点。"
        case .invalidZoom:
            "图形缩放比例无效。"
        case .cycle:
            "思维导图父子关系存在循环。"
        }
    }
}

public struct DocumentCardReference: Codable, Equatable, Sendable {
    public let materialID: UUID
    public var title: String

    public init(materialID: UUID, title: String) {
        self.materialID = materialID
        self.title = title
    }
}

public struct MediaBlockReference: Codable, Equatable, Sendable {
    public let objectKey: String
    public var label: String
    public var contentType: String
    public var byteCount: Int
    public var width: Double?
    public var height: Double?
    public var alignment: String
    public var alternativeText: String

    public init(
        objectKey: String,
        label: String,
        contentType: String,
        byteCount: Int,
        width: Double? = nil,
        height: Double? = nil,
        alignment: String = "center",
        alternativeText: String = ""
    ) {
        self.objectKey = objectKey
        self.label = label
        self.contentType = contentType
        self.byteCount = byteCount
        self.width = width
        self.height = height
        self.alignment = alignment
        self.alternativeText = alternativeText
    }
}
