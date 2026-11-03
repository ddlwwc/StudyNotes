import Foundation

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

    public init(
        layout: IOSWorkspaceLayout = .compact,
        knowledgeBaseID: UUID? = nil,
        folderPath: String = "",
        materialID: UUID? = nil,
        isEditing: Bool = false
    ) {
        self.layout = layout
        self.knowledgeBaseID = knowledgeBaseID
        self.folderPath = folderPath
        self.materialID = materialID
        self.isEditing = isEditing
    }

    public mutating func updateLayout(_ layout: IOSWorkspaceLayout) {
        self.layout = layout
    }

    public mutating func openKnowledgeBase(_ id: UUID) {
        knowledgeBaseID = id
        folderPath = ""
        materialID = nil
        isEditing = false
    }

    public mutating func openFolder(_ path: String) {
        folderPath = path
        materialID = nil
        isEditing = false
    }

    public mutating func openMaterial(
        _ id: UUID,
        editing: Bool = false
    ) {
        materialID = id
        isEditing = editing
    }

    public mutating func closeMaterial() {
        materialID = nil
        isEditing = false
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
            return
        }
        guard validKnowledgeBaseIDs.contains(knowledgeBaseID) else {
            self.knowledgeBaseID = nil
            folderPath = ""
            materialID = nil
            isEditing = false
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
