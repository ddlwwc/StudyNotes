import Foundation
import Testing
@testable import StudyNotesKit

@Suite("Mac editor structured blocks")
struct EditorStructuredBlockTests {
    @Test("block envelopes round-trip and reject broken bypass data")
    func blockEnvelopeValidation() throws {
        let block = EditorBlockEnvelope(
            id: UUID(),
            type: .dataTable,
            fallback: "| Name | Score |\n| --- | --- |",
            data: .object([
                "schema": .object([
                    "fields": .array([
                        .object([
                            "id": .string("name"),
                            "type": .string("text")
                        ])
                    ])
                ])
            ])
        )
        let encoded = try JSONEncoder().encode(block)
        let decoded = try JSONDecoder().decode(
            EditorBlockEnvelope.self,
            from: encoded
        )

        #expect(decoded == block)
        try decoded.validate()

        let invalid = EditorBlockEnvelope(
            id: block.id,
            type: .flowchart,
            version: 99,
            fallback: "flowchart"
        )
        #expect(throws: EditorBlockError.self) {
            try invalid.validate()
        }
    }

    @Test("formula evaluation is deterministic and does not execute scripts")
    func formulaEvaluation() throws {
        let document = makeFormulaDocument(
            formula: "({Price} * {Quantity}) + 5"
        )

        let value = try DataTableFormulaEngine().evaluate(
            fieldID: "total",
            document: document,
            recordID: "row-1"
        )

        #expect(value == .number(35))
    }

    @Test("formula dependencies detect cycles and division by zero is located")
    func formulaDiagnostics() {
        var cyclic = makeFormulaDocument(formula: "{Total} * 2")
        cyclic.schema.fields = [
            DataTableField(
                id: "total",
                name: "Total",
                type: .formula,
                formula: "{Other} + 1"
            ),
            DataTableField(
                id: "other",
                name: "Other",
                type: .formula,
                formula: "{Total} + 1"
            )
        ]

        #expect(throws: FormulaDiagnostic.self) {
            try DataTableFormulaEngine().evaluate(
                fieldID: "total",
                document: cyclic,
                recordID: "row-1"
            )
        }

        let division = makeFormulaDocument(formula: "{Price} / 0")
        #expect(throws: FormulaDiagnostic.self) {
            try DataTableFormulaEngine().evaluate(
                fieldID: "total",
                document: division,
                recordID: "row-1"
            )
        }
    }

    @Test("view filters and sorts use schema values without JavaScript")
    func viewRules() throws {
        let document = DataTableDocument(
            schema: DataTableSchema(fields: [
                DataTableField(id: "name", name: "Name", type: .text),
                DataTableField(id: "score", name: "Score", type: .number)
            ]),
            views: [
                DataTableView(
                    id: "view",
                    name: "Passing",
                    type: .table,
                    filters: [
                        DataTableViewFilter(
                            fieldID: "score",
                            operator: .greaterThanOrEqual,
                            value: .number(60)
                        )
                    ],
                    sorts: [
                        DataTableViewSort(fieldID: "score", ascending: false)
                    ]
                )
            ],
            records: [
                DataTableRecord(
                    id: "a",
                    values: [
                        "name": .string("Ada"),
                        "score": .number(90)
                    ]
                ),
                DataTableRecord(
                    id: "b",
                    values: [
                        "name": .string("Lin"),
                        "score": .number(50)
                    ]
                ),
                DataTableRecord(
                    id: "c",
                    values: [
                        "name": .string("Ming"),
                        "score": .number(70)
                    ]
                )
            ]
        )

        let rows = try DataTableFormulaEngine().filteredRecords(
            viewID: "view",
            document: document
        )

        #expect(rows.map(\.id) == ["a", "c"])
    }

    @Test("graph scenes round-trip and reject dangling edges")
    func graphValidation() throws {
        let scene = GraphScene(
            nodes: [
                GraphNode(id: "a", label: "A", x: 10, y: 10),
                GraphNode(id: "b", label: "B", x: 200, y: 10)
            ],
            edges: [GraphEdge(id: "ab", from: "a", to: "b")]
        )
        try scene.validate()
        let data = try JSONEncoder().encode(scene)
        let decoded = try JSONDecoder().decode(GraphScene.self, from: data)
        #expect(decoded == scene)

        let invalid = GraphScene(
            nodes: scene.nodes,
            edges: [GraphEdge(id: "bad", from: "a", to: "missing")]
        )
        #expect(throws: GraphSceneError.self) {
            try invalid.validate()
        }
    }

    private func makeFormulaDocument(formula: String) -> DataTableDocument {
        DataTableDocument(
            schema: DataTableSchema(fields: [
                DataTableField(id: "price", name: "Price", type: .number),
                DataTableField(id: "quantity", name: "Quantity", type: .number),
                DataTableField(
                    id: "total",
                    name: "Total",
                    type: .formula,
                    formula: formula
                )
            ]),
            views: [],
            records: [
                DataTableRecord(
                    id: "row-1",
                    values: [
                        "price": .number(10),
                        "quantity": .number(3)
                    ]
                )
            ]
        )
    }
}
