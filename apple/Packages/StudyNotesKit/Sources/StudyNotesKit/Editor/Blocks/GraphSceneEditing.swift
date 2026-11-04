import Foundation

public struct GraphSceneEditor: Sendable {
    public private(set) var scene: GraphScene
    private var undoStack: [GraphScene] = []
    private var redoStack: [GraphScene] = []

    public init(scene: GraphScene = GraphScene(nodes: [], edges: [])) {
        self.scene = scene
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public mutating func addNode(_ node: GraphNode) throws {
        guard !scene.nodes.contains(where: { $0.id == node.id }) else {
            throw GraphSceneError.duplicateNodeID
        }
        try mutate { scene in
            scene.nodes.append(node)
        }
    }

    public mutating func updateNode(
        id: String,
        label: String? = nil,
        x: Double? = nil,
        y: Double? = nil,
        width: Double? = nil,
        height: Double? = nil,
        collapsed: Bool? = nil
    ) throws {
        guard let index = scene.nodes.firstIndex(where: { $0.id == id })
        else {
            throw GraphSceneError.danglingEdge(id)
        }
        try mutate { scene in
            if let label {
                scene.nodes[index].label = label
            }
            if let x {
                scene.nodes[index].x = x
            }
            if let y {
                scene.nodes[index].y = y
            }
            if let width {
                scene.nodes[index].width = max(40, width)
            }
            if let height {
                scene.nodes[index].height = max(24, height)
            }
            if let collapsed {
                scene.nodes[index].collapsed = collapsed
            }
        }
    }

    public mutating func setMindMapParent(
        nodeID: String,
        parentID: String?
    ) throws {
        guard let index = scene.nodes.firstIndex(where: { $0.id == nodeID })
        else {
            throw GraphSceneError.danglingEdge(nodeID)
        }
        if let parentID {
            guard scene.nodes.contains(where: { $0.id == parentID }) else {
                throw GraphSceneError.danglingEdge(parentID)
            }
            guard parentID != nodeID else {
                throw GraphSceneError.cycle
            }
            var cursor: String? = parentID
            while let current = cursor {
                if current == nodeID {
                    throw GraphSceneError.cycle
                }
                cursor = scene.nodes.first(where: { $0.id == current })?
                    .parentID
            }
        }
        try mutate { scene in
            scene.nodes[index].parentID = parentID
        }
    }

    public mutating func addEdge(_ edge: GraphEdge) throws {
        let nodeIDs = Set(scene.nodes.map(\.id))
        guard nodeIDs.contains(edge.from), nodeIDs.contains(edge.to) else {
            throw GraphSceneError.danglingEdge(edge.id)
        }
        guard !scene.edges.contains(where: { $0.id == edge.id }) else {
            throw GraphSceneError.danglingEdge(edge.id)
        }
        try mutate { scene in
            scene.edges.append(edge)
        }
    }

    public mutating func updateEdge(
        id: String,
        label: String
    ) throws {
        guard let index = scene.edges.firstIndex(where: { $0.id == id })
        else {
            throw GraphSceneError.danglingEdge(id)
        }
        try mutate { scene in
            scene.edges[index].label = label
        }
    }

    public mutating func deleteNode(id: String) throws {
        guard scene.nodes.contains(where: { $0.id == id }) else {
            throw GraphSceneError.danglingEdge(id)
        }
        let removedIDs = descendantIDs(of: id)
        try mutate { scene in
            scene.nodes.removeAll { removedIDs.contains($0.id) }
            scene.edges.removeAll {
                removedIDs.contains($0.from)
                    || removedIDs.contains($0.to)
            }
            for index in scene.nodes.indices where
                scene.nodes[index].parentID.map(removedIDs.contains) == true {
                scene.nodes[index].parentID = nil
            }
        }
    }

    public mutating func deleteEdge(id: String) throws {
        guard scene.edges.contains(where: { $0.id == id }) else {
            throw GraphSceneError.danglingEdge(id)
        }
        try mutate { scene in
            scene.edges.removeAll { $0.id == id }
        }
    }

    public mutating func setViewport(
        zoom: Double,
        offsetX: Double,
        offsetY: Double
    ) throws {
        guard zoom.isFinite, zoom > 0, zoom <= 8,
              offsetX.isFinite, offsetY.isFinite else {
            throw GraphSceneError.invalidZoom
        }
        try mutate { scene in
            scene.zoom = zoom
            scene.offsetX = offsetX
            scene.offsetY = offsetY
        }
    }

    public mutating func undo() {
        guard let previous = undoStack.popLast() else {
            return
        }
        redoStack.append(scene)
        scene = previous
    }

    public mutating func redo() {
        guard let next = redoStack.popLast() else {
            return
        }
        undoStack.append(scene)
        scene = next
    }

    private mutating func mutate(
        _ body: (inout GraphScene) throws -> Void
    ) throws {
        var next = scene
        try body(&next)
        try next.validate()
        undoStack.append(scene)
        scene = next
        redoStack.removeAll()
    }

    private func descendantIDs(of id: String) -> Set<String> {
        var result: Set<String> = [id]
        var changed = true
        while changed {
            changed = false
            for node in scene.nodes where
                node.parentID.map(result.contains) == true
                    && !result.contains(node.id) {
                result.insert(node.id)
                changed = true
            }
        }
        return result
    }
}
