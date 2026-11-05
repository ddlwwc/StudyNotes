import Foundation
import Observation
import StudyNotesKit
import SwiftUI

enum AdvancedBlockKind: String, CaseIterable, Hashable, Identifiable, Sendable {
    case dataTable = "data-table"
    case whiteboard
    case mindMap = "mind-map"
    case flowchart

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dataTable:
            "数据表"
        case .whiteboard:
            "画板"
        case .mindMap:
            "思维导图"
        case .flowchart:
            "流程图"
        }
    }

    var systemImage: String {
        switch self {
        case .dataTable:
            "tablecells"
        case .whiteboard:
            "rectangle.3.group"
        case .mindMap:
            "point.3.connected.trianglepath.dotted"
        case .flowchart:
            "flowchart"
        }
    }

    var graphKind: GraphBlockKind? {
        switch self {
        case .dataTable:
            nil
        case .whiteboard:
            .whiteboard
        case .mindMap:
            .mindMap
        case .flowchart:
            .flowchart
        }
    }
}

enum GraphBlockKind: String, CaseIterable, Hashable, Sendable {
    case whiteboard
    case mindMap = "mind-map"
    case flowchart

    var blockKind: AdvancedBlockKind {
        switch self {
        case .whiteboard:
            .whiteboard
        case .mindMap:
            .mindMap
        case .flowchart:
            .flowchart
        }
    }

    var title: String {
        blockKind.title
    }
}

enum AdvancedBlockToolsError: LocalizedError, Equatable {
    case missingBypassData
    case unsupportedBlockType(String)
    case duplicateFieldName(String)
    case saveRejected

    var errorDescription: String? {
        switch self {
        case .missingBypassData:
            "复杂块缺少旁路数据。"
        case let .unsupportedBlockType(type):
            "复杂块类型“\(type)”不能在此面板中编辑。"
        case let .duplicateFieldName(name):
            "字段名“\(name)”已存在。"
        case .saveRejected:
            "保存复杂块失败。"
        }
    }
}

enum AdvancedBlockCodec {
    static func jsonValue<T: Encodable>(_ value: T) throws -> JSONValue {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    static func decode<T: Decodable>(
        _ type: T.Type,
        from value: JSONValue?
    ) throws -> T {
        guard let value else {
            throw AdvancedBlockToolsError.missingBypassData
        }
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(type, from: data)
    }
}

struct DataTableFormulaIssue: Identifiable, Equatable {
    let fieldID: String
    let fieldName: String
    let recordID: String?
    let recordNumber: Int?
    let offset: Int
    let message: String

    var id: String {
        "\(fieldID):\(recordID ?? "document"):\(offset):\(message)"
    }

    var locationText: String {
        if let recordNumber {
            return "记录 \(recordNumber) · \(fieldName) · 位置 \(offset)"
        }
        return "字段 \(fieldName) · 公式位置 \(offset)"
    }
}

struct DataTableDraft: Equatable {
    var document: DataTableDocument
    var activeViewID: String?

    init(document: DataTableDocument) {
        var normalized = document
        if normalized.views.isEmpty {
            let viewID = "view-\(UUID().uuidString.lowercased())"
            normalized.views = [
                DataTableView(
                    id: viewID,
                    name: "表格",
                    type: .table,
                    visibleFieldIDs: normalized.schema.fields.map(\.id)
                )
            ]
        }
        for index in normalized.views.indices
        where normalized.views[index].visibleFieldIDs.isEmpty {
            normalized.views[index].visibleFieldIDs =
                normalized.schema.fields.map(\.id)
        }
        self.document = normalized
        activeViewID = normalized.views.first?.id
    }

    static var blank: DataTableDraft {
        let nameField = DataTableField(
            id: "field-\(UUID().uuidString.lowercased())",
            name: "名称",
            type: .text
        )
        let amountField = DataTableField(
            id: "field-\(UUID().uuidString.lowercased())",
            name: "数量",
            type: .number
        )
        let totalField = DataTableField(
            id: "field-\(UUID().uuidString.lowercased())",
            name: "合计",
            type: .formula,
            formula: "{数量} * 2"
        )
        let record = DataTableRecord(
            id: "record-\(UUID().uuidString.lowercased())",
            values: [
                nameField.id: .string("示例"),
                amountField.id: .number(1)
            ],
            createdAt: Date(),
            updatedAt: Date()
        )
        return DataTableDraft(
            document: DataTableDocument(
                schema: DataTableSchema(
                    fields: [nameField, amountField, totalField]
                ),
                views: [
                    DataTableView(
                        id: "view-\(UUID().uuidString.lowercased())",
                        name: "表格",
                        type: .table,
                        visibleFieldIDs: [
                            nameField.id,
                            amountField.id,
                            totalField.id
                        ]
                    )
                ],
                records: [record]
            )
        )
    }

    var activeViewIndex: Int? {
        guard let activeViewID else {
            return document.views.indices.first
        }
        return document.views.firstIndex { $0.id == activeViewID }
    }

    var visibleFields: [DataTableField] {
        guard let index = activeViewIndex else {
            return document.schema.fields
        }
        let visibleIDs = Set(document.views[index].visibleFieldIDs)
        if visibleIDs.isEmpty {
            return document.schema.fields
        }
        return document.schema.fields.filter { visibleIDs.contains($0.id) }
    }

    @discardableResult
    mutating func addField(
        name: String,
        type: DataTableFieldType,
        options: [String] = [],
        formula: String? = nil
    ) throws -> String {
        let normalizedName = name.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalizedName.isEmpty else {
            throw AdvancedBlockToolsError.duplicateFieldName("")
        }
        guard !document.schema.fields.contains(where: {
            $0.name.caseInsensitiveCompare(normalizedName) == .orderedSame
        }) else {
            throw AdvancedBlockToolsError.duplicateFieldName(normalizedName)
        }
        let field = DataTableField(
            id: "field-\(UUID().uuidString.lowercased())",
            name: normalizedName,
            type: type,
            options: options,
            formula: type == .formula ? formula : nil
        )
        document.schema.fields.append(field)
        if activeViewIndex == nil {
            let viewID = "view-\(UUID().uuidString.lowercased())"
            document.views.append(
                DataTableView(
                    id: viewID,
                    name: "表格",
                    type: .table
                )
            )
            activeViewID = viewID
        }
        if let index = activeViewIndex {
            document.views[index].visibleFieldIDs.append(field.id)
        }
        return field.id
    }

    mutating func deleteField(id: String) {
        document.schema.fields.removeAll { $0.id == id }
        for index in document.records.indices {
            document.records[index].values.removeValue(forKey: id)
        }
        for index in document.views.indices {
            document.views[index].filters.removeAll { $0.fieldID == id }
            document.views[index].sorts.removeAll { $0.fieldID == id }
            document.views[index].groupFieldIDs.removeAll { $0 == id }
            document.views[index].visibleFieldIDs.removeAll { $0 == id }
            document.views[index].columnWidths.removeValue(forKey: id)
        }
    }

    @discardableResult
    mutating func addRecord() -> String {
        let now = Date()
        let record = DataTableRecord(
            id: "record-\(UUID().uuidString.lowercased())",
            createdAt: now,
            updatedAt: now
        )
        document.records.append(record)
        return record.id
    }

    mutating func deleteRecord(id: String) {
        document.records.removeAll { $0.id == id }
    }

    func value(fieldID: String, recordID: String) -> JSONValue? {
        document.records.first(where: { $0.id == recordID })?
            .values[fieldID]
    }

    mutating func updateCell(
        recordID: String,
        fieldID: String,
        value: JSONValue?
    ) {
        guard let index = document.records.firstIndex(where: {
            $0.id == recordID
        }) else {
            return
        }
        if let value {
            document.records[index].values[fieldID] = value
        } else {
            document.records[index].values.removeValue(forKey: fieldID)
        }
        document.records[index].updatedAt = Date()
    }

    mutating func addFilter(
        fieldID: String,
        operator: DataTableViewOperator,
        value: JSONValue?
    ) {
        guard let index = activeViewIndex else {
            return
        }
        document.views[index].filters.append(
            DataTableViewFilter(
                fieldID: fieldID,
                operator: `operator`,
                value: value
            )
        )
    }

    mutating func removeFilter(at index: Int) {
        guard let viewIndex = activeViewIndex,
              document.views[viewIndex].filters.indices.contains(index) else {
            return
        }
        document.views[viewIndex].filters.remove(at: index)
    }

    mutating func addSort(fieldID: String, ascending: Bool) {
        guard let index = activeViewIndex else {
            return
        }
        document.views[index].sorts.append(
            DataTableViewSort(fieldID: fieldID, ascending: ascending)
        )
    }

    mutating func removeSort(at index: Int) {
        guard let viewIndex = activeViewIndex,
              document.views[viewIndex].sorts.indices.contains(index) else {
            return
        }
        document.views[viewIndex].sorts.remove(at: index)
    }

    func visibleRecords() throws -> [DataTableRecord] {
        guard let activeViewID else {
            return document.records
        }
        return try DataTableFormulaEngine().filteredRecords(
            viewID: activeViewID,
            document: document
        )
    }

    func formulaValue(
        fieldID: String,
        recordID: String
    ) -> Result<FormulaValue, FormulaDiagnostic> {
        do {
            return .success(
                try DataTableFormulaEngine().evaluate(
                    fieldID: fieldID,
                    document: document,
                    recordID: recordID
                )
            )
        } catch let diagnostic as FormulaDiagnostic {
            return .failure(diagnostic)
        } catch {
            return .failure(
                FormulaDiagnostic(
                    fieldID: fieldID,
                    recordID: recordID,
                    offset: 0,
                    message: error.localizedDescription
                )
            )
        }
    }

    func formulaIssues() -> [DataTableFormulaIssue] {
        let formulaFields = document.schema.fields.filter {
            $0.type == .formula
        }
        let engine = DataTableFormulaEngine()
        do {
            try engine.validateDependencies(in: document)
        } catch let diagnostic as FormulaDiagnostic {
            let fieldID = diagnostic.fieldID.isEmpty
                ? formulaFields.first?.id ?? ""
                : diagnostic.fieldID
            return [
                DataTableFormulaIssue(
                    fieldID: fieldID,
                    fieldName: document.schema.fieldByID[fieldID]?.name
                        ?? fieldID,
                    recordID: nil,
                    recordNumber: nil,
                    offset: diagnostic.offset,
                    message: diagnostic.message
                )
            ]
        } catch {
            return []
        }

        let recordsToScan =
            (try? visibleRecords()) ?? document.records
        var issues: [DataTableFormulaIssue] = []
        for record in recordsToScan {
            let recordNumber =
                (document.records.firstIndex(where: {
                    $0.id == record.id
                }) ?? 0) + 1
            for field in formulaFields {
                if case let .failure(diagnostic) = formulaValue(
                    fieldID: field.id,
                    recordID: record.id
                ) {
                    let diagnosticFieldID =
                        diagnostic.fieldID.isEmpty
                            ? field.id
                            : diagnostic.fieldID
                    issues.append(
                        DataTableFormulaIssue(
                            fieldID: diagnosticFieldID,
                            fieldName: document.schema
                                .fieldByID[diagnosticFieldID]?.name
                                ?? field.name,
                            recordID: record.id,
                            recordNumber: recordNumber,
                            offset: diagnostic.offset,
                            message: diagnostic.message
                        )
                    )
                }
            }
        }
        return issues
    }

    func envelope(
        id: UUID,
        fallback: String? = nil
    ) throws -> EditorDocumentBlockEnvelope {
        let resolvedFallback = fallback?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return EditorDocumentBlockEnvelope(
            id: id,
            type: AdvancedBlockKind.dataTable.rawValue,
            fallback: resolvedFallback?.isEmpty == false
                ? resolvedFallback!
                : "数据表：\(document.schema.fields.count) 个字段，"
                    + "\(document.records.count) 条记录",
            data: try AdvancedBlockCodec.jsonValue(document)
        )
    }
}

struct GraphBlockDraft {
    var kind: GraphBlockKind
    var editor: GraphSceneEditor

    init(kind: GraphBlockKind, scene: GraphScene) {
        self.kind = kind
        editor = GraphSceneEditor(scene: scene)
    }

    static func seeded(_ kind: GraphBlockKind) -> GraphBlockDraft {
        switch kind {
        case .whiteboard:
            let firstID = UUID().uuidString
            let secondID = UUID().uuidString
            return GraphBlockDraft(
                kind: kind,
                scene: GraphScene(
                    nodes: [
                        GraphNode(
                            id: firstID,
                            label: "想法",
                            x: 100,
                            y: 90
                        ),
                        GraphNode(
                            id: secondID,
                            label: "下一步",
                            x: 360,
                            y: 220
                        )
                    ],
                    edges: [
                        GraphEdge(
                            id: UUID().uuidString,
                            from: firstID,
                            to: secondID
                        )
                    ]
                )
            )
        case .mindMap:
            let rootID = UUID().uuidString
            let secondID = UUID().uuidString
            let thirdID = UUID().uuidString
            return GraphBlockDraft(
                kind: kind,
                scene: GraphScene(
                    nodes: [
                        GraphNode(
                            id: rootID,
                            label: "中心主题",
                            x: 300,
                            y: 170
                        ),
                        GraphNode(
                            id: secondID,
                            label: "分支一",
                            x: 80,
                            y: 80,
                            parentID: rootID
                        ),
                        GraphNode(
                            id: thirdID,
                            label: "分支二",
                            x: 80,
                            y: 280,
                            parentID: rootID
                        )
                    ],
                    edges: [
                        GraphEdge(
                            id: UUID().uuidString,
                            from: rootID,
                            to: secondID
                        ),
                        GraphEdge(
                            id: UUID().uuidString,
                            from: rootID,
                            to: thirdID
                        )
                    ]
                )
            )
        case .flowchart:
            let startID = UUID().uuidString
            let decisionID = UUID().uuidString
            let endID = UUID().uuidString
            return GraphBlockDraft(
                kind: kind,
                scene: GraphScene(
                    nodes: [
                        GraphNode(
                            id: startID,
                            label: "开始",
                            x: 110,
                            y: 200,
                            width: 140,
                            height: 64
                        ),
                        GraphNode(
                            id: decisionID,
                            label: "判断",
                            x: 340,
                            y: 200,
                            width: 160,
                            height: 72
                        ),
                        GraphNode(
                            id: endID,
                            label: "结束",
                            x: 590,
                            y: 200,
                            width: 140,
                            height: 64
                        )
                    ],
                    edges: [
                        GraphEdge(
                            id: UUID().uuidString,
                            from: startID,
                            to: decisionID,
                            label: "进入"
                        ),
                        GraphEdge(
                            id: UUID().uuidString,
                            from: decisionID,
                            to: endID,
                            label: "完成"
                        )
                    ]
                )
            )
        }
    }

    func envelope(
        id: UUID,
        fallback: String? = nil
    ) throws -> EditorDocumentBlockEnvelope {
        let scene = editor.scene
        let resolvedFallback = fallback?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return EditorDocumentBlockEnvelope(
            id: id,
            type: kind.blockKind.rawValue,
            fallback: resolvedFallback?.isEmpty == false
                ? resolvedFallback!
                : "\(kind.title)：\(scene.nodes.count) 个节点，\(scene.edges.count) 条连线",
            data: try AdvancedBlockCodec.jsonValue(scene)
        )
    }

    static func decode(
        block: EditorDocumentBlockEnvelope
    ) throws -> GraphBlockDraft {
        guard let kind = AdvancedBlockKind(rawValue: block.type)?.graphKind
        else {
            throw AdvancedBlockToolsError.unsupportedBlockType(block.type)
        }
        let scene = try AdvancedBlockCodec.decode(
            GraphScene.self,
            from: block.data
        )
        try scene.validate()
        return GraphBlockDraft(kind: kind, scene: scene)
    }
}

private extension DataTableFieldType {
    var advancedBlockTitle: String {
        switch self {
        case .text:
            "单行文本"
        case .multilineText:
            "多行文本"
        case .number:
            "数字"
        case .singleSelect:
            "单选"
        case .multiSelect:
            "多选"
        case .checkbox:
            "复选框"
        case .date:
            "日期"
        case .dateTime:
            "日期时间"
        case .url:
            "链接"
        case .email:
            "邮箱"
        case .attachment:
            "附件"
        case .formula:
            "公式"
        case .relation:
            "关联"
        case .rollup:
            "汇总"
        case .autoNumber:
            "自动编号"
        case .createdTime:
            "创建时间"
        case .updatedTime:
            "更新时间"
        }
    }

    var usesOptions: Bool {
        self == .singleSelect || self == .multiSelect
    }
}

private extension DataTableViewOperator {
    var advancedBlockTitle: String {
        switch self {
        case .equals:
            "等于"
        case .notEquals:
            "不等于"
        case .contains:
            "包含"
        case .greaterThan:
            "大于"
        case .greaterThanOrEqual:
            "大于等于"
        case .lessThan:
            "小于"
        case .lessThanOrEqual:
            "小于等于"
        case .isEmpty:
            "为空"
        case .isNotEmpty:
            "不为空"
        }
    }

    var needsValue: Bool {
        self != .isEmpty && self != .isNotEmpty
    }
}

private extension FormulaValue {
    var advancedBlockText: String {
        switch self {
        case let .number(value):
            value.formatted(
                .number
                    .precision(.fractionLength(0...4))
                    .grouping(.never)
            )
        case let .string(value):
            value
        case let .boolean(value):
            value ? "是" : "否"
        case .empty:
            "—"
        }
    }
}

private extension JSONValue {
    var advancedBlockText: String {
        switch self {
        case .null:
            ""
        case let .bool(value):
            value ? "true" : "false"
        case let .number(value):
            value.formatted(
                .number
                    .precision(.fractionLength(0...8))
                    .grouping(.never)
            )
        case let .string(value):
            value
        case let .array(values):
            values.compactMap(\.stringValue).joined(separator: ", ")
        case let .object(value):
            value.keys.sorted().joined(separator: ", ")
        }
    }
}

private struct AdvancedBlockSelection: Equatable, Hashable {
    let id: UUID
    let kind: AdvancedBlockKind?
}

struct AdvancedBlockToolsPanel: View {
    @Bindable var session: MarkdownEditorSession
    @Environment(\.dismiss) private var dismiss
    @State private var selection: AdvancedBlockSelection?
    @State private var errorMessage: String?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 218)
                .background(SNColor.panel)

            Divider()

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SNColor.white)
        }
        .frame(minWidth: 760, idealWidth: 1_020, minHeight: 560, idealHeight: 720)
        .alert(
            "无法保存复杂块",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("复杂块")
                    .font(.sn(14, weight: .semibold))
                    .foregroundStyle(SNColor.ink)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭复杂块面板")
                .help("关闭")
            }
            .padding(14)

            Divider()

            VStack(spacing: 6) {
                ForEach(
                    [
                        AdvancedBlockKind.dataTable,
                        .whiteboard,
                        .mindMap,
                        .flowchart
                    ]
                ) { kind in
                    Button {
                        selection = AdvancedBlockSelection(
                            id: UUID(),
                            kind: kind
                        )
                    } label: {
                        Label(kind.title, systemImage: kind.systemImage)
                            .font(.sn(12, weight: .medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                    }
                    .buttonStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: SNRadius.control)
                            .fill(SNColor.white)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: SNRadius.control)
                            .stroke(SNColor.border)
                    }
                    .accessibilityLabel("新建\(kind.title)")
                }
            }
            .padding(10)

            Divider()
                .padding(.vertical, 4)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(session.blocks) { block in
                        existingBlockButton(block)
                    }
                }
                .padding(8)
            }

            Spacer(minLength: 0)

            if let selectedBlock {
                Divider()
                Button(role: .destructive) {
                    session.removeBlock(id: selectedBlock.id)
                    selection = nil
                } label: {
                    Label("删除块", systemImage: "trash")
                        .font(.sn(11))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(SNColor.red)
                .padding(12)
                .accessibilityLabel("删除所选复杂块")
            }
        }
    }

    private var detail: some View {
        Group {
            if let selection {
                AdvancedBlockEditorHost(
                    blockID: selection.id,
                    existingBlock: session.blocks.first(where: {
                        $0.id == selection.id
                    }),
                    newKind: selection.kind,
                    onSave: save
                )
                .id(selection)
            } else {
                ContentUnavailableView(
                    "选择复杂块",
                    systemImage: "square.grid.2x2",
                    description: Text("从左侧新建或选择现有复杂块。")
                )
                .foregroundStyle(SNColor.muted)
            }
        }
    }

    private var selectedBlock: EditorDocumentBlockEnvelope? {
        guard let selection else {
            return nil
        }
        return session.blocks.first { $0.id == selection.id }
    }

    private func existingBlockButton(
        _ block: EditorDocumentBlockEnvelope
    ) -> some View {
        let kind = AdvancedBlockKind(rawValue: block.type)
        return Button {
            selection = AdvancedBlockSelection(
                id: block.id,
                kind: kind
            )
        } label: {
            HStack(spacing: 8) {
                Image(systemName: kind?.systemImage ?? "square.dashed")
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(kind?.title ?? block.type)
                        .font(.sn(11, weight: .medium))
                    Text(block.fallback)
                        .font(.sn(9))
                        .foregroundStyle(SNColor.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .foregroundStyle(
                selection?.id == block.id ? SNColor.blue : SNColor.text
            )
            .padding(.horizontal, 8)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: SNRadius.control)
                    .fill(
                        selection?.id == block.id
                            ? SNColor.blueSoft
                            : Color.clear
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(kind?.title ?? block.type)：\(block.fallback)"
        )
    }

    private func save(_ block: EditorDocumentBlockEnvelope) throws {
        if session.blocks.contains(where: { $0.id == block.id }) {
            session.updateBlock(block)
            guard session.blocks.first(where: { $0.id == block.id }) == block
            else {
                throw AdvancedBlockToolsError.saveRejected
            }
        } else {
            session.insertBlock(block)
            guard session.blocks.contains(where: { $0.id == block.id }) else {
                throw AdvancedBlockToolsError.saveRejected
            }
        }
        selection = AdvancedBlockSelection(
            id: block.id,
            kind: AdvancedBlockKind(rawValue: block.type)
        )
    }
}

private struct AdvancedBlockEditorHost: View {
    let blockID: UUID
    let existingBlock: EditorDocumentBlockEnvelope?
    let newKind: AdvancedBlockKind?
    let onSave: (EditorDocumentBlockEnvelope) throws -> Void
    @State private var dataTableDocument: DataTableDocument?
    @State private var graphDraft: GraphBlockDraft?
    @State private var loadError: String?

    init(
        blockID: UUID,
        existingBlock: EditorDocumentBlockEnvelope?,
        newKind: AdvancedBlockKind?,
        onSave: @escaping (EditorDocumentBlockEnvelope) throws -> Void
    ) {
        self.blockID = blockID
        self.existingBlock = existingBlock
        self.newKind = newKind
        self.onSave = onSave
        _dataTableDocument = State(initialValue: nil)
        _graphDraft = State(initialValue: nil)
        _loadError = State(initialValue: nil)

        let type = existingBlock?.type ?? newKind?.rawValue
        guard let type else {
            _loadError = State(initialValue: "没有可编辑的复杂块类型。")
            return
        }
        guard let kind = AdvancedBlockKind(rawValue: type) else {
            _loadError = State(
                initialValue: AdvancedBlockToolsError
                    .unsupportedBlockType(type)
                    .localizedDescription
            )
            return
        }
        do {
            switch kind {
            case .dataTable:
                if let existingBlock {
                    let document = try AdvancedBlockCodec.decode(
                        DataTableDocument.self,
                        from: existingBlock.data
                    )
                    _dataTableDocument = State(
                        initialValue: DataTableDraft(document: document).document
                    )
                } else {
                    _dataTableDocument = State(
                        initialValue: DataTableDraft.blank.document
                    )
                }
            case .whiteboard, .mindMap, .flowchart:
                if let existingBlock {
                    _graphDraft = State(
                        initialValue: try GraphBlockDraft.decode(
                            block: existingBlock
                        )
                    )
                } else if let graphKind = kind.graphKind {
                    _graphDraft = State(
                        initialValue: .seeded(graphKind)
                    )
                }
            }
        } catch {
            _loadError = State(initialValue: error.localizedDescription)
        }
    }

    var body: some View {
        Group {
            if let loadError {
                ContentUnavailableView(
                    "无法打开复杂块",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
                .foregroundStyle(SNColor.muted)
            } else if let dataTableDocument {
                DataTableBlockEditor(
                    blockID: blockID,
                    initialDocument: dataTableDocument,
                    initialFallback: existingBlock?.fallback,
                    onSave: onSave
                )
            } else if let graphDraft {
                GraphBlockEditor(
                    blockID: blockID,
                    initialDraft: graphDraft,
                    initialFallback: existingBlock?.fallback,
                    onSave: onSave
                )
            } else {
                ProgressView()
            }
        }
    }
}

private struct DataTableBlockEditor: View {
    let blockID: UUID
    let initialFallback: String?
    let onSave: (EditorDocumentBlockEnvelope) throws -> Void
    @State private var draft: DataTableDraft
    @State private var newFieldName = ""
    @State private var newFieldType: DataTableFieldType = .text
    @State private var newFieldOptions = ""
    @State private var newFieldFormula = ""
    @State private var filterFieldID = ""
    @State private var filterOperator: DataTableViewOperator = .equals
    @State private var filterValue = ""
    @State private var sortFieldID = ""
    @State private var sortAscending = true
    @State private var errorMessage: String?
    @State private var statusMessage = ""

    init(
        blockID: UUID,
        initialDocument: DataTableDocument,
        initialFallback: String?,
        onSave: @escaping (EditorDocumentBlockEnvelope) throws -> Void
    ) {
        self.blockID = blockID
        self.initialFallback = initialFallback
        self.onSave = onSave
        _draft = State(
            initialValue: DataTableDraft(document: initialDocument)
        )
    }

    private var records: [DataTableRecord] {
        (try? draft.visibleRecords()) ?? draft.document.records
    }

    private var visibleFields: [DataTableField] {
        draft.visibleFields
    }

    var body: some View {
        VStack(spacing: 0) {
            editorToolbar
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    tableSection
                    fieldsSection
                    viewsSection
                    formulaIssuesSection
                }
                .padding(16)
            }
        }
        .onAppear {
            normalizeSelections()
        }
        .onChange(of: draft.document.schema.fields.map(\.id)) {
            normalizeSelections()
        }
        .alert(
            "数据表操作失败",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var editorToolbar: some View {
        HStack(spacing: 8) {
            Label("数据表", systemImage: "tablecells")
                .font(.sn(13, weight: .semibold))
                .foregroundStyle(SNColor.ink)

            Text(
                "\(draft.document.schema.fields.count) 字段 · "
                    + "\(draft.document.records.count) 记录"
            )
            .font(.sn(10))
            .foregroundStyle(SNColor.muted)

            Spacer()

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.sn(10))
                    .foregroundStyle(SNColor.green)
            }

            Button {
                draft.addRecord()
            } label: {
                Label("新增记录", systemImage: "plus")
                    .font(.sn(11))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("新增数据表记录")

            Button {
                save()
            } label: {
                Label("保存", systemImage: "square.and.arrow.down")
                    .font(.sn(11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(SNColor.blue)
            .accessibilityLabel("保存数据表")
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(SNColor.panel)
    }

    private var tableSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("表格")
                    .font(.sn(13, weight: .semibold))
                    .foregroundStyle(SNColor.ink)

                Spacer()

                if let index = draft.activeViewIndex {
                    Picker(
                        "视图",
                        selection: Binding(
                            get: {
                                draft.activeViewID
                                    ?? draft.document.views[index].id
                            },
                            set: { draft.activeViewID = $0 }
                        )
                    ) {
                        ForEach(draft.document.views, id: \.id) { view in
                            Text(view.name).tag(view.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                    .accessibilityLabel("数据表视图")
                }
            }

            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 0) {
                    tableHeader
                    Divider()

                    if records.isEmpty {
                        Text("暂无记录")
                            .font(.sn(11))
                            .foregroundStyle(SNColor.muted)
                            .frame(maxWidth: .infinity, minHeight: 72)
                    } else {
                        ForEach(Array(records.enumerated()), id: \.element.id) {
                            index,
                            record in
                            tableRow(record, number: index + 1)
                            if record.id != records.last?.id {
                                Divider()
                            }
                        }
                    }
                }
                .background(SNColor.white)
            }
            .background(SNColor.white)
            .clipShape(
                RoundedRectangle(cornerRadius: SNRadius.panel)
            )
            .overlay {
                RoundedRectangle(cornerRadius: SNRadius.panel)
                    .stroke(SNColor.border)
            }
        }
    }

    private var tableHeader: some View {
        HStack(spacing: 0) {
            Text("#")
                .font(.sn(10, weight: .medium))
                .foregroundStyle(SNColor.muted)
                .frame(width: 42, height: 34)

            ForEach(visibleFields, id: \.id) { field in
                VStack(alignment: .leading, spacing: 1) {
                    Text(field.name)
                        .font(.sn(10, weight: .semibold))
                        .foregroundStyle(SNColor.ink)
                        .lineLimit(1)
                    Text(field.type.advancedBlockTitle)
                        .font(.sn(8))
                        .foregroundStyle(SNColor.muted)
                }
                .padding(.horizontal, 8)
                .frame(width: 156, height: 42, alignment: .leading)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(SNColor.border)
                        .frame(width: 1)
                }
            }

            Text("")
                .frame(width: 40, height: 42)
        }
        .background(SNColor.panel)
    }

    private func tableRow(
        _ record: DataTableRecord,
        number: Int
    ) -> some View {
        HStack(spacing: 0) {
            Text("\(number)")
                .font(.sn(9))
                .foregroundStyle(SNColor.muted)
                .frame(width: 42, height: 44)

            ForEach(visibleFields, id: \.id) { field in
                dataCell(record: record, field: field, number: number)
                    .frame(width: 156, height: 44)
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(SNColor.border)
                            .frame(width: 1)
                    }
            }

            Button(role: .destructive) {
                draft.deleteRecord(id: record.id)
            } label: {
                Image(systemName: "trash")
                    .font(.sn(10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(SNColor.red)
            .frame(width: 40, height: 44)
            .accessibilityLabel("删除记录 \(number)")
        }
    }

    @ViewBuilder
    private func dataCell(
        record: DataTableRecord,
        field: DataTableField,
        number: Int
    ) -> some View {
        Group {
            switch field.type {
            case .formula:
                formulaCell(record: record, field: field)
            case .checkbox:
                Toggle(
                    field.name,
                    isOn: Binding(
                        get: {
                            draft.value(
                                fieldID: field.id,
                                recordID: record.id
                            )?.boolValue ?? false
                        },
                        set: { value in
                            draft.updateCell(
                                recordID: record.id,
                                fieldID: field.id,
                                value: .bool(value)
                            )
                        }
                    )
                )
                .labelsHidden()
                .toggleStyle(.checkbox)
                .accessibilityLabel("\(field.name)，记录 \(number)")
            case .singleSelect where !field.options.isEmpty:
                Picker(
                    field.name,
                    selection: stringBinding(
                        record: record,
                        field: field
                    )
                ) {
                    Text("未选择").tag("")
                    ForEach(field.options, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .labelsHidden()
                .accessibilityLabel("\(field.name)，记录 \(number)")
            case .autoNumber:
                Text("\(number)")
                    .font(.sn(11))
                    .foregroundStyle(SNColor.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .accessibilityLabel(
                        "\(field.name)，自动编号 \(number)"
                    )
            case .createdTime, .updatedTime:
                Text(timeText(record: record, type: field.type))
                    .font(.sn(9))
                    .foregroundStyle(SNColor.muted)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .accessibilityLabel("\(field.name)，记录 \(number)")
            default:
                TextField(
                    field.placeholder,
                    text: stringBinding(record: record, field: field),
                    axis: field.type == .multilineText ? .vertical : .horizontal
                )
                .textFieldStyle(.plain)
                .font(.sn(10))
                .lineLimit(field.type == .multilineText ? 2 : 1)
                .padding(.horizontal, 8)
                .accessibilityLabel("\(field.name)，记录 \(number)")
            }
        }
    }

    private func formulaCell(
        record: DataTableRecord,
        field: DataTableField
    ) -> some View {
        Group {
            switch draft.formulaValue(
                fieldID: field.id,
                recordID: record.id
            ) {
            case let .success(value):
                Text(value.advancedBlockText)
                    .font(.sn(10, weight: .medium))
                    .foregroundStyle(SNColor.blue)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
            case let .failure(diagnostic):
                Label("错误", systemImage: "exclamationmark.triangle.fill")
                    .font(.sn(9, weight: .medium))
                    .foregroundStyle(SNColor.red)
                    .help(
                        "\(field.name) · 位置 \(diagnostic.offset)：\(diagnostic.message)"
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
            }
        }
    }

    private var fieldsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("字段")
                .font(.sn(13, weight: .semibold))
                .foregroundStyle(SNColor.ink)

            VStack(spacing: 8) {
                ForEach(
                    Array(draft.document.schema.fields.enumerated()),
                    id: \.element.id
                ) { index, field in
                    fieldEditor(index: index, field: field)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("新增字段")
                    .font(.sn(10, weight: .medium))
                    .foregroundStyle(SNColor.muted)

                TextField("字段名", text: $newFieldName)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("新字段名")

                HStack(spacing: 8) {
                    Picker("类型", selection: $newFieldType) {
                        ForEach(DataTableFieldType.allCases, id: \.self) {
                            type in
                            Text(type.advancedBlockTitle).tag(type)
                        }
                    }
                    .labelsHidden()
                    .frame(minWidth: 130, maxWidth: 180)
                    .accessibilityLabel("新字段类型")

                    Button {
                        addField()
                    } label: {
                        Label("添加字段", systemImage: "plus")
                            .font(.sn(11))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("添加数据表字段")
                }

                if newFieldType.usesOptions {
                    TextField(
                        "选项，用逗号分隔",
                        text: $newFieldOptions
                    )
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("新字段选项")
                }

                if newFieldType == .formula {
                    TextField(
                        "公式，例如 {数量} * 2",
                        text: $newFieldFormula
                    )
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("新字段公式")
                }
            }
            .padding(10)
            .background(SNColor.panel)
            .clipShape(
                RoundedRectangle(cornerRadius: SNRadius.panel)
            )
        }
    }

    private func fieldEditor(
        index: Int,
        field: DataTableField
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("字段 \(index + 1)")
                    .font(.sn(9))
                    .foregroundStyle(SNColor.muted)

                Spacer()

                Button(role: .destructive) {
                    draft.deleteField(id: field.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(SNColor.red)
                .accessibilityLabel("删除字段 \(field.name)")
            }

            TextField(
                "字段名",
                text: Binding(
                    get: { draft.document.schema.fields[index].name },
                    set: {
                        draft.document.schema.fields[index].name = $0
                    }
                )
            )
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("字段名 \(field.name)")

            Picker(
                "类型",
                selection: Binding(
                    get: { draft.document.schema.fields[index].type },
                    set: {
                        draft.document.schema.fields[index].type = $0
                    }
                )
            ) {
                ForEach(DataTableFieldType.allCases, id: \.self) { type in
                    Text(type.advancedBlockTitle).tag(type)
                }
            }
            .accessibilityLabel("字段类型 \(field.name)")

            if field.type.usesOptions {
                TextField(
                    "选项，用逗号分隔",
                    text: Binding(
                        get: {
                            draft.document.schema.fields[index].options
                                .joined(separator: ", ")
                        },
                        set: { value in
                            draft.document.schema.fields[index].options =
                                value
                                    .split(separator: ",")
                                    .map {
                                        $0.trimmingCharacters(
                                            in: .whitespacesAndNewlines
                                        )
                                    }
                                    .filter { !$0.isEmpty }
                        }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("字段选项 \(field.name)")
            }

            if field.type == .formula {
                TextField(
                    "公式",
                    text: Binding(
                        get: {
                            draft.document.schema.fields[index].formula ?? ""
                        },
                        set: { value in
                            draft.document.schema.fields[index].formula =
                                value.isEmpty ? nil : value
                        }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("字段公式 \(field.name)")
            }
        }
        .padding(10)
        .background(SNColor.panel)
        .clipShape(
            RoundedRectangle(cornerRadius: SNRadius.panel)
        )
        .overlay {
            RoundedRectangle(cornerRadius: SNRadius.panel)
                .stroke(SNColor.border)
        }
    }

    private var viewsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("视图筛选与排序")
                .font(.sn(13, weight: .semibold))
                .foregroundStyle(SNColor.ink)

            if let viewIndex = draft.activeViewIndex {
                viewEditor(viewIndex: viewIndex)
            } else {
                Text("当前没有可用视图。")
                    .font(.sn(10))
                    .foregroundStyle(SNColor.muted)
            }
        }
    }

    private func viewEditor(viewIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(
                "视图名称",
                text: Binding(
                    get: { draft.document.views[viewIndex].name },
                    set: { draft.document.views[viewIndex].name = $0 }
                )
            )
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("视图名称")

            VStack(alignment: .leading, spacing: 6) {
                Text("筛选")
                    .font(.sn(10, weight: .medium))
                    .foregroundStyle(SNColor.muted)

                Picker("筛选字段", selection: $filterFieldID) {
                    ForEach(draft.document.schema.fields, id: \.id) { field in
                        Text(field.name).tag(field.id)
                    }
                }
                .accessibilityLabel("筛选字段")

                Picker("筛选条件", selection: $filterOperator) {
                    ForEach(
                        [
                            DataTableViewOperator.equals,
                            .notEquals,
                            .contains,
                            .greaterThan,
                            .greaterThanOrEqual,
                            .lessThan,
                            .lessThanOrEqual,
                            .isEmpty,
                            .isNotEmpty
                        ],
                        id: \.self
                    ) { value in
                        Text(value.advancedBlockTitle).tag(value)
                    }
                }
                .accessibilityLabel("筛选条件")

                if filterOperator.needsValue {
                    TextField("筛选值", text: $filterValue)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("筛选值")
                }

                Button {
                    addFilter()
                } label: {
                    Label("添加筛选", systemImage: "line.3.horizontal.decrease")
                        .font(.sn(11))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("添加筛选条件")

                ForEach(
                    Array(
                        draft.document.views[viewIndex].filters.enumerated()
                    ),
                    id: \.offset
                ) { index, filter in
                    HStack {
                        Text(filterSummary(filter))
                            .font(.sn(10))
                            .lineLimit(1)
                        Spacer()
                        Button(role: .destructive) {
                            draft.removeFilter(at: index)
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("删除筛选 \(index + 1)")
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("排序")
                    .font(.sn(10, weight: .medium))
                    .foregroundStyle(SNColor.muted)

                Picker("排序字段", selection: $sortFieldID) {
                    ForEach(draft.document.schema.fields, id: \.id) { field in
                        Text(field.name).tag(field.id)
                    }
                }
                .accessibilityLabel("排序字段")

                Toggle("升序", isOn: $sortAscending)
                    .toggleStyle(.checkbox)
                    .accessibilityLabel("排序方向为升序")

                Button {
                    if !sortFieldID.isEmpty {
                        draft.addSort(
                            fieldID: sortFieldID,
                            ascending: sortAscending
                        )
                    }
                } label: {
                    Label("添加排序", systemImage: "arrow.up.arrow.down")
                        .font(.sn(11))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("添加排序条件")

                ForEach(
                    Array(draft.document.views[viewIndex].sorts.enumerated()),
                    id: \.offset
                ) { index, sort in
                    HStack {
                        Text(sortSummary(sort))
                            .font(.sn(10))
                            .lineLimit(1)
                        Spacer()
                        Button(role: .destructive) {
                            draft.removeSort(at: index)
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("删除排序 \(index + 1)")
                    }
                }
            }
        }
        .padding(10)
        .background(SNColor.panel)
        .clipShape(
            RoundedRectangle(cornerRadius: SNRadius.panel)
        )
        .overlay {
            RoundedRectangle(cornerRadius: SNRadius.panel)
                .stroke(SNColor.border)
        }
    }

    @ViewBuilder
    private var formulaIssuesSection: some View {
        let issues = draft.formulaIssues()
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    "公式错误 \(issues.count)",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.sn(12, weight: .semibold))
                .foregroundStyle(SNColor.red)

                ForEach(issues) { issue in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(issue.locationText)
                            .font(.sn(10, weight: .medium))
                        Text(issue.message)
                            .font(.sn(10))
                            .foregroundStyle(SNColor.text)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SNColor.redSoft)
                    .clipShape(
                        RoundedRectangle(cornerRadius: SNRadius.small)
                    )
                }
            }
        }
    }

    private func stringBinding(
        record: DataTableRecord,
        field: DataTableField
    ) -> Binding<String> {
        Binding(
            get: {
                draft.value(
                    fieldID: field.id,
                    recordID: record.id
                )?.advancedBlockText ?? ""
            },
            set: { value in
                draft.updateCell(
                    recordID: record.id,
                    fieldID: field.id,
                    value: jsonValue(for: field.type, text: value)
                )
            }
        )
    }

    private func jsonValue(
        for type: DataTableFieldType,
        text: String
    ) -> JSONValue? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        switch type {
        case .number:
            if let value = Double(trimmed) {
                return .number(value)
            }
            return .string(text)
        case .multiSelect:
            return .array(
                text.split(separator: ",").map {
                    .string(
                        $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }
            )
        default:
            return .string(text)
        }
    }

    private func filterJSONValue(
        fieldID: String,
        text: String
    ) -> JSONValue? {
        guard let field = draft.document.schema.fieldByID[fieldID] else {
            return nil
        }
        return jsonValue(for: field.type, text: text)
    }

    private func addField() {
        do {
            let options =
                newFieldType.usesOptions
                    ? newFieldOptions
                        .split(separator: ",")
                        .map {
                            $0.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                        }
                        .filter { !$0.isEmpty }
                    : []
            _ = try draft.addField(
                name: newFieldName,
                type: newFieldType,
                options: options,
                formula: newFieldFormula.isEmpty
                    ? nil
                    : newFieldFormula
            )
            newFieldName = ""
            newFieldOptions = ""
            newFieldFormula = ""
            statusMessage = "已新增字段"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addFilter() {
        guard !filterFieldID.isEmpty else {
            return
        }
        draft.addFilter(
            fieldID: filterFieldID,
            operator: filterOperator,
            value: filterOperator.needsValue
                ? filterJSONValue(fieldID: filterFieldID, text: filterValue)
                : nil
        )
        filterValue = ""
    }

    private func filterSummary(_ filter: DataTableViewFilter) -> String {
        let fieldName =
            draft.document.schema.fieldByID[filter.fieldID]?.name
                ?? filter.fieldID
        let value = filter.value?.advancedBlockText ?? ""
        return "\(fieldName) \(filter.operator.advancedBlockTitle) \(value)"
    }

    private func sortSummary(_ sort: DataTableViewSort) -> String {
        let fieldName =
            draft.document.schema.fieldByID[sort.fieldID]?.name
                ?? sort.fieldID
        return "\(fieldName) \(sort.ascending ? "升序" : "降序")"
    }

    private func normalizeSelections() {
        let ids = draft.document.schema.fields.map(\.id)
        if !ids.contains(filterFieldID) {
            filterFieldID = ids.first ?? ""
        }
        if !ids.contains(sortFieldID) {
            sortFieldID = ids.first ?? ""
        }
    }

    private func timeText(
        record: DataTableRecord,
        type: DataTableFieldType
    ) -> String {
        let date = type == .createdTime
            ? record.createdAt
            : record.updatedAt
        guard let date else {
            return "—"
        }
        return date.formatted(
            date: .abbreviated,
            time: .shortened
        )
    }

    private func save() {
        do {
            let block = try draft.envelope(
                id: blockID,
                fallback: initialFallback
            )
            try onSave(block)
            statusMessage = "已保存"
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension DataTableField {
    var placeholder: String {
        switch type {
        case .number:
            "0"
        case .date:
            "YYYY-MM-DD"
        case .dateTime:
            "YYYY-MM-DD HH:mm"
        case .url:
            "https://"
        case .email:
            "name@example.com"
        case .multilineText:
            "多行文本"
        default:
            name
        }
    }
}

private struct GraphBlockEditor: View {
    let blockID: UUID
    let initialFallback: String?
    let onSave: (EditorDocumentBlockEnvelope) throws -> Void
    @State private var draft: GraphBlockDraft
    @State private var selectedNodeID: String?
    @State private var selectedEdgeID: String?
    @State private var draggingNodeID: String?
    @State private var dragTranslation: CGSize = .zero
    @State private var linkFromID = ""
    @State private var linkToID = ""
    @State private var backgroundDragOrigin: CGPoint?
    @State private var backgroundTranslation: CGSize = .zero
    @State private var errorMessage: String?
    @State private var statusMessage = ""
    @FocusState private var canvasIsFocused: Bool

    init(
        blockID: UUID,
        initialDraft: GraphBlockDraft,
        initialFallback: String?,
        onSave: @escaping (EditorDocumentBlockEnvelope) throws -> Void
    ) {
        self.blockID = blockID
        self.initialFallback = initialFallback
        self.onSave = onSave
        _draft = State(initialValue: initialDraft)
    }

    private var scene: GraphScene {
        draft.editor.scene
    }

    private var selectedNode: GraphNode? {
        scene.nodes.first { $0.id == selectedNodeID }
    }

    private var selectedEdge: GraphEdge? {
        scene.edges.first { $0.id == selectedEdgeID }
    }

    var body: some View {
        VStack(spacing: 0) {
            editorToolbar
            Divider()

            GeometryReader { proxy in
                if proxy.size.width >= 720 {
                    HStack(spacing: 0) {
                        canvas
                        Divider()
                        inspector
                            .frame(width: 250)
                    }
                } else {
                    VSplitView {
                        canvas
                            .frame(minHeight: 280)
                        inspector
                            .frame(minHeight: 210)
                    }
                }
            }
        }
        .onAppear {
            normalizeLinkSelections()
        }
        .onChange(of: scene.nodes.map(\.id)) {
            normalizeLinkSelections()
        }
        .alert(
            "图形操作失败",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var editorToolbar: some View {
        HStack(spacing: 7) {
            Label(draft.kind.title, systemImage: draft.kind.blockKind.systemImage)
                .font(.sn(13, weight: .semibold))
                .foregroundStyle(SNColor.ink)

            Text(
                "\(scene.nodes.count) 节点 · \(scene.edges.count) 连线"
            )
            .font(.sn(10))
            .foregroundStyle(SNColor.muted)

            Spacer()

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.sn(10))
                    .foregroundStyle(SNColor.green)
            }

            iconButton(
                "撤销",
                systemImage: "arrow.uturn.backward",
                disabled: !draft.editor.canUndo,
                shortcut: KeyboardShortcut(
                    "z",
                    modifiers: .command
                )
            ) {
                draft.editor.undo()
                normalizeSelectionAfterHistory()
            }

            iconButton(
                "重做",
                systemImage: "arrow.uturn.forward",
                disabled: !draft.editor.canRedo,
                shortcut: KeyboardShortcut(
                    "z",
                    modifiers: [.command, .shift]
                )
            ) {
                draft.editor.redo()
                normalizeSelectionAfterHistory()
            }

            Button {
                addNode()
            } label: {
                Label("新增节点", systemImage: "plus")
                    .font(.sn(11))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("新增图形节点")

            Button {
                save()
            } label: {
                Label("保存", systemImage: "square.and.arrow.down")
                    .font(.sn(11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(SNColor.blue)
            .accessibilityLabel("保存\(draft.kind.title)")
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(SNColor.panel)
    }

    private func iconButton(
        _ label: String,
        systemImage: String,
        disabled: Bool,
        shortcut: KeyboardShortcut? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .keyboardShortcut(shortcut)
        .accessibilityLabel(label)
        .help(label)
    }

    private var canvas: some View {
        ZStack {
            Rectangle()
                .fill(SNColor.white)
                .contentShape(Rectangle())
                .gesture(backgroundDragGesture)

            Canvas { context, _ in
                drawScene(context: &context)
            }
            .allowsHitTesting(false)

            ForEach(scene.nodes, id: \.id) { node in
                nodeCard(node)
            }
        }
        .frame(minHeight: 280)
        .clipShape(Rectangle())
        .overlay {
            Rectangle()
                .stroke(SNColor.border)
        }
        .focusable()
        .focused($canvasIsFocused)
        .onTapGesture {
            canvasIsFocused = true
        }
        .onDeleteCommand {
            deleteSelection()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(draft.kind.title)画布")
        .overlay(alignment: .bottomTrailing) {
            zoomControls
                .padding(10)
        }
    }

    private var zoomControls: some View {
        HStack(spacing: 2) {
            Button {
                setZoom(scene.zoom - 0.15)
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("缩小图形画布")

            Text(scene.zoom.formatted(.percent.precision(.fractionLength(0))))
                .font(.sn(9, weight: .medium))
                .frame(width: 44)

            Button {
                setZoom(scene.zoom + 0.15)
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("放大图形画布")
        }
        .padding(.horizontal, 4)
        .background(SNColor.panel)
        .clipShape(
            RoundedRectangle(cornerRadius: SNRadius.control)
        )
        .overlay {
            RoundedRectangle(cornerRadius: SNRadius.control)
                .stroke(SNColor.border)
        }
    }

    private func nodeCard(_ node: GraphNode) -> some View {
        let isSelected = node.id == selectedNodeID
        let translation = node.id == draggingNodeID
            ? dragTranslation
            : .zero
        let width = max(80, node.width * scene.zoom)
        let height = max(44, node.height * scene.zoom)
        let x = (node.x + translation.width / scene.zoom) * scene.zoom
            + scene.offsetX + backgroundTranslation.width
        let y = (node.y + translation.height / scene.zoom) * scene.zoom
            + scene.offsetY + backgroundTranslation.height

        return Button {
            selectedNodeID = node.id
            selectedEdgeID = nil
            canvasIsFocused = true
        } label: {
            VStack(spacing: 4) {
                Text(node.label)
                    .font(.sn(11, weight: .medium))
                    .foregroundStyle(SNColor.ink)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)

                if draft.kind == .mindMap, node.parentID != nil {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.sn(8))
                        .foregroundStyle(SNColor.muted)
                }
            }
            .padding(8)
            .frame(width: width, height: height)
            .background(
                RoundedRectangle(cornerRadius: SNRadius.panel)
                    .fill(
                        isSelected
                            ? SNColor.blueSoft
                            : SNColor.panel
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: SNRadius.panel)
                    .stroke(
                        isSelected ? SNColor.blue : SNColor.border,
                        lineWidth: isSelected ? 2 : 1
                    )
            }
            .shadow(
                color: Color.black.opacity(0.04),
                radius: 2,
                y: 1
            )
        }
        .buttonStyle(.plain)
        .position(
            x: x + width / 2,
            y: y + height / 2
        )
        .simultaneousGesture(nodeDragGesture(node))
        .accessibilityLabel("节点：\(node.label)")
        .accessibilityHint(
            "拖动可移动节点，按 Delete 删除所选节点"
        )
    }

    private func nodeDragGesture(_ node: GraphNode) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if draggingNodeID != node.id {
                    draggingNodeID = node.id
                    dragTranslation = .zero
                }
                selectedNodeID = node.id
                selectedEdgeID = nil
                canvasIsFocused = true
                dragTranslation = value.translation
            }
            .onEnded { value in
                do {
                    try draft.editor.updateNode(
                        id: node.id,
                        x: node.x + value.translation.width / scene.zoom,
                        y: node.y + value.translation.height / scene.zoom
                    )
                } catch {
                    errorMessage = error.localizedDescription
                }
                draggingNodeID = nil
                dragTranslation = .zero
            }
    }

    private var backgroundDragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                canvasIsFocused = true
                if backgroundDragOrigin == nil {
                    backgroundDragOrigin = CGPoint(
                        x: scene.offsetX,
                        y: scene.offsetY
                    )
                }
                backgroundTranslation = value.translation
            }
            .onEnded { value in
                guard let origin = backgroundDragOrigin else {
                    return
                }
                do {
                    try draft.editor.setViewport(
                        zoom: scene.zoom,
                        offsetX: origin.x + value.translation.width,
                        offsetY: origin.y + value.translation.height
                    )
                } catch {
                    errorMessage = error.localizedDescription
                }
                backgroundDragOrigin = nil
                backgroundTranslation = .zero
            }
    }

    private func drawScene(context: inout GraphicsContext) {
        let nodesByID = Dictionary(
            uniqueKeysWithValues: scene.nodes.map { ($0.id, $0) }
        )

        for node in scene.nodes {
            guard let parentID = node.parentID,
                  let parent = nodesByID[parentID] else {
                continue
            }
            guard !scene.edges.contains(where: {
                $0.from == parent.id && $0.to == node.id
            }) else {
                continue
            }
            let start = displayedCenter(parent)
            let end = displayedCenter(node)
            var path = Path()
            path.move(to: start)
            path.addCurve(
                to: end,
                control1: CGPoint(
                    x: (start.x + end.x) / 2,
                    y: start.y
                ),
                control2: CGPoint(
                    x: (start.x + end.x) / 2,
                    y: end.y
                )
            )
            context.stroke(
                path,
                with: .color(SNColor.blueLine),
                style: StrokeStyle(
                    lineWidth: 1.5,
                    dash: [5, 4]
                )
            )
        }

        for edge in scene.edges {
            guard let from = nodesByID[edge.from],
                  let to = nodesByID[edge.to] else {
                continue
            }
            let start = displayedCenter(from)
            let end = displayedCenter(to)
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            context.stroke(
                path,
                with: .color(SNColor.muted),
                lineWidth: 1.5
            )

            if !edge.label.isEmpty {
                context.draw(
                    Text(edge.label)
                        .font(.sn(9))
                        .foregroundStyle(SNColor.text),
                    at: CGPoint(
                        x: (start.x + end.x) / 2,
                        y: (start.y + end.y) / 2 - 10
                    )
                )
            }
        }
    }

    private func displayedCenter(_ node: GraphNode) -> CGPoint {
        let translation = node.id == draggingNodeID
            ? dragTranslation
            : .zero
        return CGPoint(
            x: (node.x + translation.width / scene.zoom
                + node.width / 2) * scene.zoom + scene.offsetX
                + backgroundTranslation.width,
            y: (node.y + translation.height / scene.zoom
                + node.height / 2) * scene.zoom + scene.offsetY
                + backgroundTranslation.height
        )
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let selectedNode {
                    nodeInspector(selectedNode)
                } else if let selectedEdge {
                    edgeInspector(selectedEdge)
                } else {
                    Text("未选择节点")
                        .font(.sn(10))
                        .foregroundStyle(SNColor.muted)
                }

                Divider()
                connectionSection
                Divider()
                edgeList
            }
            .padding(12)
        }
        .background(SNColor.panel)
    }

    private func nodeInspector(_ node: GraphNode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("节点")
                .font(.sn(12, weight: .semibold))
                .foregroundStyle(SNColor.ink)

            TextField(
                "标签",
                text: Binding(
                    get: {
                        scene.nodes.first(where: {
                            $0.id == node.id
                        })?.label ?? ""
                    },
                    set: { value in
                        do {
                            try draft.editor.updateNode(
                                id: node.id,
                                label: value
                            )
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                )
            )
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("节点标签")

            if draft.kind == .mindMap {
                Picker(
                    "父节点",
                    selection: Binding(
                        get: {
                            scene.nodes.first(where: {
                                $0.id == node.id
                            })?.parentID ?? ""
                        },
                        set: { value in
                            do {
                                try draft.editor.setMindMapParent(
                                    nodeID: node.id,
                                    parentID: value.isEmpty ? nil : value
                                )
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    )
                ) {
                    Text("无").tag("")
                    ForEach(
                        scene.nodes.filter { $0.id != node.id },
                        id: \.id
                    ) { candidate in
                        Text(candidate.label).tag(candidate.id)
                    }
                }
                .accessibilityLabel("思维导图父节点")
            }

            Button(role: .destructive) {
                deleteSelectedNode()
            } label: {
                Label("删除节点", systemImage: "trash")
                    .font(.sn(10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(SNColor.red)
            .accessibilityLabel("删除所选节点")
        }
    }

    private func edgeInspector(_ edge: GraphEdge) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("连线")
                .font(.sn(12, weight: .semibold))
                .foregroundStyle(SNColor.ink)

            TextField(
                "标签",
                text: Binding(
                    get: {
                        scene.edges.first(where: {
                            $0.id == edge.id
                        })?.label ?? ""
                    },
                    set: { value in
                        do {
                            try draft.editor.updateEdge(
                                id: edge.id,
                                label: value
                            )
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                )
            )
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("连线标签")

            Button(role: .destructive) {
                do {
                    try draft.editor.deleteEdge(id: edge.id)
                    selectedEdgeID = nil
                } catch {
                    errorMessage = error.localizedDescription
                }
            } label: {
                Label("删除连线", systemImage: "trash")
                    .font(.sn(10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(SNColor.red)
            .accessibilityLabel("删除所选连线")
        }
    }

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("连线")
                .font(.sn(12, weight: .semibold))
                .foregroundStyle(SNColor.ink)

            Picker("起点", selection: $linkFromID) {
                ForEach(scene.nodes, id: \.id) { node in
                    Text(node.label).tag(node.id)
                }
            }
            .accessibilityLabel("连线起点")

            Picker("终点", selection: $linkToID) {
                ForEach(scene.nodes, id: \.id) { node in
                    Text(node.label).tag(node.id)
                }
            }
            .accessibilityLabel("连线终点")

            Button {
                addEdge()
            } label: {
                Label("添加连线", systemImage: "arrow.right")
                    .font(.sn(10))
            }
            .buttonStyle(.plain)
            .disabled(
                linkFromID.isEmpty
                    || linkToID.isEmpty
                    || linkFromID == linkToID
            )
            .accessibilityLabel("添加图形连线")
        }
    }

    private var edgeList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("现有连线 \(scene.edges.count)")
                .font(.sn(11, weight: .medium))
                .foregroundStyle(SNColor.muted)

            ForEach(scene.edges, id: \.id) { edge in
                Button {
                    selectedEdgeID = edge.id
                    selectedNodeID = nil
                    canvasIsFocused = true
                } label: {
                    HStack(spacing: 6) {
                        Text(edgeLabel(edge))
                            .font(.sn(10))
                            .lineLimit(1)
                        Spacer()
                    }
                    .foregroundStyle(
                        selectedEdgeID == edge.id
                            ? SNColor.blue
                            : SNColor.text
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("连线 \(edgeLabel(edge))")
            }
        }
    }

    private func edgeLabel(_ edge: GraphEdge) -> String {
        let nodeByID = Dictionary(
            uniqueKeysWithValues: scene.nodes.map {
                ($0.id, $0.label)
            }
        )
        let from = nodeByID[edge.from] ?? edge.from
        let to = nodeByID[edge.to] ?? edge.to
        return edge.label.isEmpty
            ? "\(from) → \(to)"
            : "\(from) → \(to) · \(edge.label)"
    }

    private func addNode() {
        let number = scene.nodes.count + 1
        let node = GraphNode(
            id: UUID().uuidString,
            label: "节点 \(number)",
            x: 80 + Double((number % 4) * 50),
            y: 90 + Double((number / 4) * 70)
        )
        do {
            try draft.editor.addNode(node)
            selectedNodeID = node.id
            selectedEdgeID = nil
            normalizeLinkSelections()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addEdge() {
        guard linkFromID != linkToID else {
            return
        }
        do {
            let edge = GraphEdge(
                id: UUID().uuidString,
                from: linkFromID,
                to: linkToID
            )
            try draft.editor.addEdge(edge)
            selectedEdgeID = edge.id
            selectedNodeID = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteSelection() {
        if selectedNodeID != nil {
            deleteSelectedNode()
        } else if let selectedEdgeID {
            do {
                try draft.editor.deleteEdge(id: selectedEdgeID)
                self.selectedEdgeID = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deleteSelectedNode() {
        guard let selectedNodeID else {
            return
        }
        do {
            try draft.editor.deleteNode(id: selectedNodeID)
            self.selectedNodeID = nil
            normalizeLinkSelections()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setZoom(_ value: Double) {
        do {
            try draft.editor.setViewport(
                zoom: min(2.5, max(0.4, value)),
                offsetX: scene.offsetX,
                offsetY: scene.offsetY
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func normalizeLinkSelections() {
        let ids = scene.nodes.map(\.id)
        if !ids.contains(linkFromID) {
            linkFromID = ids.first ?? ""
        }
        if !ids.contains(linkToID) || linkToID == linkFromID {
            linkToID = ids.first(where: { $0 != linkFromID }) ?? ""
        }
    }

    private func normalizeSelectionAfterHistory() {
        if let selectedNodeID,
           !scene.nodes.contains(where: { $0.id == selectedNodeID }) {
            self.selectedNodeID = nil
        }
        if let selectedEdgeID,
           !scene.edges.contains(where: { $0.id == selectedEdgeID }) {
            self.selectedEdgeID = nil
        }
        normalizeLinkSelections()
    }

    private func save() {
        do {
            let block = try draft.envelope(
                id: blockID,
                fallback: initialFallback
            )
            try onSave(block)
            statusMessage = "已保存"
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

