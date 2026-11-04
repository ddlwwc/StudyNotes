import Testing
@testable import StudyNotesKit

@Suite("Graph scene editing")
struct GraphSceneEditingTests {
    @Test("nodes and edges can be edited with undo and redo")
    func editingHistory() throws {
        var editor = GraphSceneEditor()
        try editor.addNode(GraphNode(id: "a", label: "Start", x: 0, y: 0))
        try editor.addNode(GraphNode(id: "b", label: "End", x: 200, y: 0))
        try editor.addEdge(GraphEdge(id: "ab", from: "a", to: "b"))
        try editor.updateEdge(id: "ab", label: "next")

        #expect(editor.scene.edges.first?.label == "next")
        editor.undo()
        #expect(editor.scene.edges.first?.label == "")
        editor.redo()
        #expect(editor.scene.edges.first?.label == "next")
    }

    @Test("mind map parent cycles are rejected")
    func mindMapCycle() throws {
        var editor = GraphSceneEditor()
        try editor.addNode(GraphNode(id: "root", label: "Root", x: 0, y: 0))
        try editor.addNode(
            GraphNode(
                id: "child",
                label: "Child",
                x: 200,
                y: 0,
                parentID: "root"
            )
        )
        try editor.addNode(
            GraphNode(
                id: "leaf",
                label: "Leaf",
                x: 400,
                y: 0,
                parentID: "child"
            )
        )

        #expect(throws: GraphSceneError.self) {
            try editor.setMindMapParent(nodeID: "root", parentID: "leaf")
        }
    }

    @Test("deleting a node removes its edges and descendant children")
    func deleteNode() throws {
        var editor = GraphSceneEditor()
        try editor.addNode(GraphNode(id: "a", label: "A", x: 0, y: 0))
        try editor.addNode(
            GraphNode(
                id: "b",
                label: "B",
                x: 200,
                y: 0,
                parentID: "a"
            )
        )
        try editor.addNode(GraphNode(id: "c", label: "C", x: 400, y: 0))
        try editor.addEdge(GraphEdge(id: "ac", from: "a", to: "c"))

        try editor.deleteNode(id: "a")

        #expect(editor.scene.nodes.map(\.id) == ["c"])
        #expect(editor.scene.edges.isEmpty)
    }
}
