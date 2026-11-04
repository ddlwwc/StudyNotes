import Foundation
import StudyNotesKit

public enum IOSWorkspaceLayout: String, Equatable, Sendable {
    case compact
    case regular
}

public struct IOSWorkspaceState: Equatable, Sendable {
    public var layout: IOSWorkspaceLayout
    public private(set) var knowledgeBaseID: UUID?
    public private(set) var folderPath: String
    public private(set) var materialID: UUID?
    public private(set) var isEditing: Bool
    public private(set) var selectedMaterialIDs: Set<UUID>
    public private(set) var expandedFolderPaths: Set<String>
    private var materialSelectionAnchorID: UUID?

    public init(
        layout: IOSWorkspaceLayout = .compact,
        knowledgeBaseID: UUID? = nil,
        folderPath: String = "",
        materialID: UUID? = nil,
        isEditing: Bool = false,
        selectedMaterialIDs: Set<UUID> = [],
        expandedFolderPaths: Set<String> = [""]
    ) {
        self.layout = layout
        self.knowledgeBaseID = knowledgeBaseID
        self.folderPath = folderPath
        self.materialID = materialID
        self.isEditing = isEditing
        self.selectedMaterialIDs = selectedMaterialIDs
        self.expandedFolderPaths = expandedFolderPaths
        materialSelectionAnchorID = materialID
    }

    public mutating func updateLayout(_ layout: IOSWorkspaceLayout) {
        self.layout = layout
    }

    public mutating func openKnowledgeBase(_ id: UUID) {
        knowledgeBaseID = id
        folderPath = ""
        materialID = nil
        isEditing = false
        selectedMaterialIDs = []
        materialSelectionAnchorID = nil
        expandedFolderPaths = [""]
    }

    public mutating func openFolder(_ path: String) {
        folderPath = path
        materialID = nil
        isEditing = false
        selectedMaterialIDs = []
        materialSelectionAnchorID = nil
    }

    public mutating func openMaterial(
        _ id: UUID,
        editing: Bool = false
    ) {
        materialID = id
        isEditing = editing
        selectedMaterialIDs = [id]
        materialSelectionAnchorID = id
    }

    public mutating func toggleMaterialSelection(_ id: UUID) {
        if selectedMaterialIDs.contains(id) {
            selectedMaterialIDs.remove(id)
        } else {
            selectedMaterialIDs.insert(id)
        }
        materialSelectionAnchorID = id
    }

    public mutating func extendMaterialSelection(
        to id: UUID,
        visibleMaterialIDs: [UUID]
    ) {
        guard let startID = materialSelectionAnchorID ?? materialID,
              let start = visibleMaterialIDs.firstIndex(of: startID),
              let end = visibleMaterialIDs.firstIndex(of: id) else {
            selectedMaterialIDs = [id]
            materialSelectionAnchorID = id
            return
        }
        selectedMaterialIDs = Set(
            visibleMaterialIDs[min(start, end)...max(start, end)]
        )
        materialSelectionAnchorID = startID
    }

    public mutating func selectFolderForOrganization(_ path: String) {
        folderPath = path
        selectedMaterialIDs = []
        materialSelectionAnchorID = nil
    }

    public mutating func toggleFolderExpansion(_ path: String) {
        if expandedFolderPaths.contains(path) {
            expandedFolderPaths.remove(path)
        } else {
            expandedFolderPaths.insert(path)
        }
    }

    public mutating func setExpandedFolderPaths(_ paths: Set<String>) {
        expandedFolderPaths = paths.union([""])
    }

    public mutating func expandAncestors(of path: String) {
        expandedFolderPaths.formUnion(
            DirectoryPath.expandedAncestors(of: path)
        )
    }

    public mutating func reconcileExpandedFolders(
        validPaths: Set<String>
    ) {
        expandedFolderPaths.formIntersection(validPaths)
        expandedFolderPaths.insert("")
    }

    public mutating func closeMaterial() {
        materialID = nil
        isEditing = false
        selectedMaterialIDs = []
        materialSelectionAnchorID = nil
    }

    public mutating func setEditing(_ isEditing: Bool) {
        guard materialID != nil else {
            return
        }
        self.isEditing = isEditing
    }

    public mutating func rebaseFolderPath(
        from oldPath: String,
        to newPath: String
    ) {
        if folderPath == oldPath {
            folderPath = newPath
        } else if folderPath.hasPrefix(oldPath + "/") {
            folderPath = newPath + String(folderPath.dropFirst(oldPath.count))
        }
    }

    public mutating func rebaseExpandedFolderPaths(
        from oldPath: String,
        to newPath: String
    ) {
        expandedFolderPaths = DirectoryPath.rebase(
            expandedFolderPaths,
            from: oldPath,
            to: newPath
        )
    }

    public mutating func navigateBack() {
        if materialID != nil {
            closeMaterial()
        } else if !folderPath.isEmpty {
            folderPath = Self.parentPath(of: folderPath)
        } else {
            knowledgeBaseID = nil
        }
    }

    public mutating func reconcile(
        validKnowledgeBaseIDs: Set<UUID>,
        folderPaths: Set<String>,
        materialIDs: Set<UUID>
    ) {
        guard let knowledgeBaseID else {
            folderPath = ""
            materialID = nil
            isEditing = false
            selectedMaterialIDs = []
            materialSelectionAnchorID = nil
            return
        }
        guard validKnowledgeBaseIDs.contains(knowledgeBaseID) else {
            self.knowledgeBaseID = nil
            folderPath = ""
            materialID = nil
            isEditing = false
            selectedMaterialIDs = []
            materialSelectionAnchorID = nil
            return
        }

        if !folderPath.isEmpty, !folderPaths.contains(folderPath) {
            folderPath = Self.nearestValidParent(
                of: folderPath,
                validPaths: folderPaths
            )
        }
        if let materialID, !materialIDs.contains(materialID) {
            self.materialID = nil
            isEditing = false
            selectedMaterialIDs = []
            materialSelectionAnchorID = nil
        } else {
            selectedMaterialIDs.formIntersection(materialIDs)
            if selectedMaterialIDs.isEmpty {
                materialSelectionAnchorID = nil
            }
        }
    }

    public static func isValidFolderMove(
        sourcePath: String,
        targetParentPath: String
    ) -> Bool {
        guard !sourcePath.isEmpty else {
            return false
        }
        return targetParentPath != sourcePath
            && !targetParentPath.hasPrefix(sourcePath + "/")
    }

    public static func parentPath(of path: String) -> String {
        path.split(separator: "/").dropLast().joined(separator: "/")
    }

    private static func nearestValidParent(
        of path: String,
        validPaths: Set<String>
    ) -> String {
        var candidate = parentPath(of: path)
        while !candidate.isEmpty {
            if validPaths.contains(candidate) {
                return candidate
            }
            candidate = parentPath(of: candidate)
        }
        return ""
    }
}

public enum LibraryTreeDragPayload: Equatable, Sendable {
    case folder(knowledgeBaseID: UUID, path: String)
    case materials(knowledgeBaseID: UUID?, materialIDs: [UUID])
}

public enum LibraryTreeDropTarget: Equatable, Sendable {
    case root(knowledgeBaseID: UUID)
    case folder(knowledgeBaseID: UUID, path: String)
}

public enum LibraryTreeDropRules {
    public static func allows(
        _ payload: LibraryTreeDragPayload,
        on target: LibraryTreeDropTarget,
        layout: IOSWorkspaceLayout
    ) -> Bool {
        guard layout == .regular else {
            return false
        }
        switch (payload, target) {
        case let (
            .folder(sourceKnowledgeBaseID, sourcePath),
            .folder(targetKnowledgeBaseID, targetPath)
        ):
            return sourceKnowledgeBaseID == targetKnowledgeBaseID
                && IOSWorkspaceState.isValidFolderMove(
                    sourcePath: sourcePath,
                    targetParentPath: targetPath
                )
        case let (
            .folder(sourceKnowledgeBaseID, _),
            .root(targetKnowledgeBaseID)
        ):
            return sourceKnowledgeBaseID == targetKnowledgeBaseID
        case (.materials(_, let materialIDs), .root),
             (.materials(_, let materialIDs), .folder):
            return !materialIDs.isEmpty
        }
    }

    public static func materialIDsToMove(
        draggedID: UUID,
        selectedIDs: Set<UUID>,
        visibleIDs: Set<UUID>
    ) -> Set<UUID> {
        guard selectedIDs.contains(draggedID),
              selectedIDs.count > 1 else {
            return [draggedID]
        }
        let visibleSelection = selectedIDs.intersection(visibleIDs)
        return visibleSelection.isEmpty ? [draggedID] : visibleSelection
    }
}
