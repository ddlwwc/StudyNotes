import Foundation

public struct SearchScopeSummary: Equatable, Sendable {
    public let metadataCount: Int
    public let fullTextCount: Int
    public let downloadedCount: Int
    public let offlineCount: Int

    public init(
        metadataCount: Int,
        fullTextCount: Int,
        downloadedCount: Int,
        offlineCount: Int
    ) {
        self.metadataCount = metadataCount
        self.fullTextCount = fullTextCount
        self.downloadedCount = downloadedCount
        self.offlineCount = offlineCount
    }

    public var metadataLabel: String {
        "全部 \(metadataCount) 份材料的标题与标签"
    }

    public var fullTextLabel: String {
        "正文、标注、AI 结果：\(fullTextCount) 份已下载或离线材料"
    }
}

public actor LibrarySearchService {
    private let libraryStore: IOSLibraryStore

    public init(libraryStore: IOSLibraryStore) {
        self.libraryStore = libraryStore
    }

    public func scopeSummary(snapshot: IOSLibrarySnapshot) -> SearchScopeSummary {
        SearchScopeSummary(
            metadataCount: snapshot.materials.count,
            fullTextCount: snapshot.downloadedMaterials.count,
            downloadedCount: snapshot.materials.count { $0.accessState == .downloaded },
            offlineCount: snapshot.materials.count { $0.accessState == .offline }
        )
    }

    public func search(
        query: String,
        snapshot: IOSLibrarySnapshot
    ) async -> [SearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }
        var hits: [SearchHit] = []

        for material in snapshot.materials {
            let metadata = [
                material.title,
                material.tags.joined(separator: " ")
            ].joined(separator: " ")
            if metadata.localizedCaseInsensitiveContains(trimmed) {
                hits.append(
                    SearchHit(
                        materialID: material.id,
                        title: material.title,
                        kind: .metadata,
                        snippet: metadataSnippet(for: material)
                    )
                )
            }

            guard material.isTextSearchable else {
                continue
            }
            let fullText = await libraryStore.scanTextForSearch(
                materialID: material.id,
                isICloud: snapshot.isICloud
            )
            guard fullText.localizedCaseInsensitiveContains(trimmed) else {
                continue
            }
            let annotationMatch = (try? await libraryStore.loadAnnotations(
                materialID: material.id,
                sourceText: nil
            ))?.contains {
                ($0.quote ?? "").localizedCaseInsensitiveContains(trimmed)
                    || $0.note.localizedCaseInsensitiveContains(trimmed)
            } ?? false
            let aiMatch = (try? await libraryStore.loadConversations(
                materialID: material.id
            ))?.flatMap(\.messages).contains {
                $0.content.localizedCaseInsensitiveContains(trimmed)
            } ?? false
            let hitsForMaterial = classifyFullTextHits(
                text: fullText,
                query: trimmed,
                material: material,
                annotationMatch: annotationMatch,
                aiMatch: aiMatch
            )
            hits.append(contentsOf: hitsForMaterial)
        }

        return hits.sorted {
            if $0.kind != $1.kind {
                return kindOrder($0.kind) < kindOrder($1.kind)
            }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    private func classifyFullTextHits(
        text: String,
        query: String,
        material: LibraryMaterial,
        annotationMatch: Bool,
        aiMatch: Bool
    ) -> [SearchHit] {
        let sections = text.components(separatedBy: "\n")
        let matchingLines = sections.filter {
            $0.localizedCaseInsensitiveContains(query)
        }
        guard !matchingLines.isEmpty else {
            return []
        }
        let snippet = snippet(from: matchingLines.joined(separator: " "), query: query)
        var hits: [SearchHit] = []
        hits.append(
            SearchHit(
                materialID: material.id,
                title: material.title,
                kind: .content,
                snippet: snippet
            )
        )
        if annotationMatch {
            hits.append(
                SearchHit(
                    materialID: material.id,
                    title: material.title,
                    kind: .annotation,
                    snippet: snippet
                )
            )
        }
        if aiMatch {
            hits.append(
                SearchHit(
                    materialID: material.id,
                    title: material.title,
                    kind: .ai,
                    snippet: snippet
                )
            )
        }
        return hits
    }

    private func metadataSnippet(for material: LibraryMaterial) -> String {
        var parts = [material.kind.label, material.knowledgeBaseName]
        if !material.folderPath.isEmpty {
            parts.append(material.folderPath.replacingOccurrences(of: "/", with: " / "))
        }
        if !material.tags.isEmpty {
            parts.append(material.tags.map { "#\($0)" }.joined(separator: " "))
        }
        return parts.joined(separator: " · ")
    }

    private func snippet(from text: String, query: String) -> String {
        let compact = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard compact.count > 140 else {
            return compact
        }
        guard let range = compact.range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) else {
            return String(compact.prefix(140)) + "..."
        }
        let lower = compact.index(
            range.lowerBound,
            offsetBy: -max(0, min(48, compact.distance(
                from: compact.startIndex,
                to: range.lowerBound
            )))
        )
        let upper = compact.index(
            range.upperBound,
            offsetBy: min(92, compact.distance(
                from: range.upperBound,
                to: compact.endIndex
            ))
        )
        let prefix = lower > compact.startIndex ? "..." : ""
        let suffix = upper < compact.endIndex ? "..." : ""
        return prefix + compact[lower..<upper] + suffix
    }

    private func kindOrder(_ kind: SearchHit.Kind) -> Int {
        switch kind {
        case .metadata:
            0
        case .content:
            1
        case .annotation:
            2
        case .ai:
            3
        }
    }
}

public enum LibraryTreeRow: Identifiable, Equatable, Sendable {
    case root(
        knowledgeBase: KnowledgeBaseSummary,
        materialCount: Int,
        isExpanded: Bool
    )
    case folder(FolderNode, depth: Int, isExpanded: Bool)
    case material(LibraryMaterial, depth: Int)

    public var id: String {
        switch self {
        case let .root(knowledgeBase, _, _):
            "root:\(knowledgeBase.id.uuidString)"
        case let .folder(folder, _, _):
            "folder:\(folder.path)"
        case let .material(material, _):
            "material:\(material.id.uuidString)"
        }
    }

    public var title: String {
        switch self {
        case let .root(knowledgeBase, _, _):
            knowledgeBase.name
        case let .folder(folder, _, _):
            folder.name
        case let .material(material, _):
            material.title
        }
    }

    public var depth: Int {
        switch self {
        case .root:
            0
        case let .folder(_, depth, _), let .material(_, depth):
            depth
        }
    }

    public var materialCount: Int {
        switch self {
        case let .root(_, count, _):
            count
        case let .folder(folder, _, _):
            folder.materialCount
        case .material:
            1
        }
    }
}

public enum LibraryTreeBuilder {
    public static func folders(
        for knowledgeBaseID: UUID,
        in materials: [LibraryMaterial],
        knownFolders: [IOSFolder] = []
    ) -> [FolderNode] {
        let scoped = materials.filter {
            $0.manifest.knowledgeBaseID == knowledgeBaseID
        }
        var paths = Set(
            knownFolders
                .filter { $0.knowledgeBaseID == knowledgeBaseID }
                .map(\.path)
        )
        for material in scoped {
            let components = material.folderPath
                .split(separator: "/")
                .map(String.init)
            guard !components.isEmpty else {
                continue
            }
            for index in 1...components.count {
                paths.insert(components.prefix(index).joined(separator: "/"))
            }
        }
        return nodes(
            parentPath: "",
            paths: paths,
            materials: scoped
        )
    }

    public static func folder(
        at path: String,
        in nodes: [FolderNode]
    ) -> FolderNode? {
        for node in nodes {
            if node.path == path {
                return node
            }
            if let match = Self.folder(at: path, in: node.children) {
                return match
            }
        }
        return nil
    }

    public static func visibleRows(
        knowledgeBase: KnowledgeBaseSummary,
        materials: [LibraryMaterial],
        folders: [IOSFolder],
        expandedPaths: Set<String>
    ) -> [LibraryTreeRow] {
        let scopedMaterials = materials.filter {
            $0.manifest.knowledgeBaseID == knowledgeBase.id
        }
        var rows = [
            LibraryTreeRow.root(
                knowledgeBase: knowledgeBase,
                materialCount: scopedMaterials.count,
                isExpanded: expandedPaths.contains("")
            )
        ]
        guard expandedPaths.contains("") else {
            return rows
        }

        let tree = self.folders(
            for: knowledgeBase.id,
            in: scopedMaterials,
            knownFolders: folders
        )
        for folder in tree {
            append(
                folder,
                depth: 1,
                materials: scopedMaterials,
                expandedPaths: expandedPaths,
                to: &rows
            )
        }
        rows.append(
            contentsOf: Self.materials(
                in: "",
                from: scopedMaterials,
                depth: 1
            )
        )
        return rows
    }

    private static func nodes(
        parentPath: String,
        paths: Set<String>,
        materials: [LibraryMaterial]
    ) -> [FolderNode] {
        let prefix = parentPath.isEmpty ? "" : "\(parentPath)/"
        let directNames = Set(paths.compactMap { path -> String? in
            guard path.hasPrefix(prefix) else {
                return nil
            }
            let remainder = String(path.dropFirst(prefix.count))
            guard !remainder.isEmpty, !remainder.contains("/") else {
                return nil
            }
            return remainder
        })
        return directNames.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }.map { name in
            let path = prefix + name
            let count = materials.count {
                $0.folderPath == path || $0.folderPath.hasPrefix(path + "/")
            }
            return FolderNode(
                name: name,
                path: path,
                children: nodes(
                    parentPath: path,
                    paths: paths,
                    materials: materials
                ),
                materialCount: count
            )
        }
    }

    private static func append(
        _ folder: FolderNode,
        depth: Int,
        materials: [LibraryMaterial],
        expandedPaths: Set<String>,
        to rows: inout [LibraryTreeRow]
    ) {
        let isExpanded = expandedPaths.contains(folder.path)
        rows.append(
            .folder(folder, depth: depth, isExpanded: isExpanded)
        )
        guard isExpanded else {
            return
        }
        for child in folder.children {
            append(
                child,
                depth: depth + 1,
                materials: materials,
                expandedPaths: expandedPaths,
                to: &rows
            )
        }
        rows.append(
            contentsOf: self.materials(
                in: folder.path,
                from: materials,
                depth: depth + 1
            )
        )
    }

    private static func materials(
        in folderPath: String,
        from materials: [LibraryMaterial],
        depth: Int
    ) -> [LibraryTreeRow] {
        materials
            .filter { $0.folderPath == folderPath }
            .sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            .map { .material($0, depth: depth) }
    }
}
