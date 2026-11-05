import Foundation
import StudyNotesKit
import Testing
@testable import StudyNotesMacUI

@Suite("Advanced block tools")
struct AdvancedBlockToolsTests {
    @Test("data table fields, records, filters, sorting, and formulas round-trip")
    func dataTableWorkflow() throws {
        var draft = DataTableDraft.blank
        let amount = try #require(
            draft.document.schema.fields.first { $0.name == "数量" }
        )
        let total = try #require(
            draft.document.schema.fields.first { $0.name == "合计" }
        )

        let secondRecordID = draft.addRecord()
        let thirdRecordID = draft.addRecord()
        let firstRecordID = try #require(draft.document.records.first?.id)
        draft.updateCell(
            recordID: secondRecordID,
            fieldID: amount.id,
            value: .number(2)
        )
        draft.updateCell(
            recordID: thirdRecordID,
            fieldID: amount.id,
            value: .number(3)
        )

        draft.addFilter(
            fieldID: amount.id,
            operator: .greaterThan,
            value: .number(1)
        )
        draft.addSort(fieldID: amount.id, ascending: false)

        let visible = try draft.visibleRecords()
        #expect(visible.map(\.id) == [thirdRecordID, secondRecordID])
        #expect(!visible.map(\.id).contains(firstRecordID))

        guard case let .success(value) = draft.formulaValue(
            fieldID: total.id,
            recordID: thirdRecordID
        ) else {
            Issue.record("Expected formula to evaluate")
            return
        }
        #expect(value == .number(6))

        let envelope = try draft.envelope(id: UUID())
        let encoded = try #require(envelope.data)
        let decoded = try AdvancedBlockCodec.decode(
            DataTableDocument.self,
            from: encoded
        )
        #expect(decoded.schema.fields.map(\.name) == ["名称", "数量", "合计"])
        #expect(decoded.records.count == 3)
        #expect(decoded.views.first?.filters.count == 1)
        #expect(decoded.views.first?.sorts.count == 1)
    }

    @Test("formula dependency failures keep field and offset diagnostics")
    func formulaDiagnostics() throws {
        let missingReference = DataTableField(
            id: "formula-field",
            name: "结果",
            type: .formula,
            formula: "{不存在} + 1"
        )
        let record = DataTableRecord(id: "record-1")
        let document = DataTableDocument(
            schema: DataTableSchema(fields: [missingReference]),
            views: [
                DataTableView(
                    id: "view-1",
                    name: "表格",
                    type: .table,
                    visibleFieldIDs: [missingReference.id]
                )
            ],
            records: [record]
        )
        let draft = DataTableDraft(document: document)
        let issue = try #require(draft.formulaIssues().first)

        #expect(issue.fieldID == missingReference.id)
        #expect(issue.fieldName == "结果")
        #expect(issue.recordID == nil)
        #expect(issue.recordNumber == nil)
        #expect(issue.offset >= 0)
        #expect(issue.message.contains("不存在"))
    }

    @Test("formula issues respect empty filters and validate without records")
    func formulaIssueScope() throws {
        let amount = DataTableField(
            id: "amount",
            name: "数量",
            type: .number
        )
        let result = DataTableField(
            id: "result",
            name: "结果",
            type: .formula,
            formula: "{数量} / 0"
        )
        let view = DataTableView(
            id: "view",
            name: "表格",
            type: .table,
            filters: [
                DataTableViewFilter(
                    fieldID: amount.id,
                    operator: .greaterThan,
                    value: .number(10)
                )
            ],
            visibleFieldIDs: [amount.id, result.id]
        )
        let records = [
            DataTableRecord(
                id: "record-1",
                values: [amount.id: .number(1)]
            )
        ]
        let filtered = DataTableDraft(
            document: DataTableDocument(
                schema: DataTableSchema(fields: [amount, result]),
                views: [view],
                records: records
            )
        )
        #expect(filtered.formulaIssues().isEmpty)

        let visible = DataTableDraft(
            document: DataTableDocument(
                schema: DataTableSchema(fields: [amount, result]),
                views: [
                    DataTableView(
                        id: "visible-view",
                        name: "表格",
                        type: .table,
                        visibleFieldIDs: [amount.id, result.id]
                    )
                ],
                records: records
            )
        )
        let visibleIssue = try #require(visible.formulaIssues().first)
        #expect(visibleIssue.recordID == "record-1")
        #expect(visibleIssue.recordNumber == 1)
        #expect(visibleIssue.offset >= 0)

        let invalid = DataTableDraft(
            document: DataTableDocument(
                schema: DataTableSchema(
                    fields: [
                        DataTableField(
                            id: "invalid",
                            name: "公式",
                            type: .formula,
                            formula: "{缺失} + 1"
                        )
                    ]
                ),
                views: [
                    DataTableView(
                        id: "empty-view",
                        name: "表格",
                        type: .table
                    )
                ]
            )
        )
        let issue = try #require(invalid.formulaIssues().first)
        #expect(issue.recordID == nil)
        #expect(issue.recordNumber == nil)
        #expect(issue.message.contains("缺失"))
    }

    @Test("mind map parent changes reject cycles and graph JSON round-trips")
    func mindMapCycleAndRoundTrip() throws {
        var draft = GraphBlockDraft.seeded(.mindMap)
        let root = try #require(
            draft.editor.scene.nodes.first { $0.parentID == nil }
        )
        let child = try #require(
            draft.editor.scene.nodes.first { $0.parentID == root.id }
        )

        #expect(throws: GraphSceneError.cycle) {
            try draft.editor.setMindMapParent(
                nodeID: root.id,
                parentID: child.id
            )
        }

        let envelope = try draft.envelope(id: UUID())
        let decoded = try GraphBlockDraft.decode(block: envelope)
        #expect(decoded.kind == .mindMap)
        #expect(decoded.editor.scene.nodes == draft.editor.scene.nodes)
        #expect(decoded.editor.scene.edges == draft.editor.scene.edges)
    }

    @Test("graph undo and redo preserve one transaction per drag update")
    func graphUndoRedo() throws {
        var draft = GraphBlockDraft.seeded(.flowchart)
        let node = try #require(draft.editor.scene.nodes.first)
        let originalX = node.x

        try draft.editor.updateNode(id: node.id, x: originalX + 80)
        #expect(draft.editor.canUndo)
        #expect(
            draft.editor.scene.nodes.first(where: {
                $0.id == node.id
            })?.x == originalX + 80
        )

        draft.editor.undo()
        #expect(
            draft.editor.scene.nodes.first(where: {
                $0.id == node.id
            })?.x == originalX
        )

        draft.editor.redo()
        #expect(
            draft.editor.scene.nodes.first(where: {
                $0.id == node.id
            })?.x == originalX + 80
        )
    }

    @Test("session insert, update, and remove keep markdown block markers")
    @MainActor
    func sessionBlockLifecycle() throws {
        let session = MarkdownEditorSession(
            snapshot: MarkdownEditorSnapshot(
                materialID: UUID(),
                title: "测试",
                markdown: "# 测试",
                fingerprint: "fingerprint",
                compatibilityBlocks: []
            ),
            saveHandler: { request in
                .saved(
                    title: request.title,
                    markdown: request.markdown,
                    fingerprint: "saved"
                )
            }
        )
        let draft = DataTableDraft.blank
        let blockID = UUID()
        let inserted = try draft.envelope(id: blockID)

        session.insertBlock(inserted)
        #expect(session.blocks.map(\.id) == [blockID])
        #expect(session.markdown.contains("type=\"data-table\""))

        var changedDocument = draft.document
        changedDocument.schema.fields[0].name = "标题"
        let changed = try DataTableDraft(document: changedDocument)
            .envelope(id: blockID)
        session.updateBlock(changed)
        #expect(
            session.blocks.first?.data
                == changed.data
        )

        session.removeBlock(id: blockID)
        #expect(session.blocks.isEmpty)
        #expect(!session.markdown.contains("studynotes:block"))
    }
}
