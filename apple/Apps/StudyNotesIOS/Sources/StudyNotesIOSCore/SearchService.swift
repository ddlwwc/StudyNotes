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
        "全部 \(metadataCount) 份材料的标题、标签、目录"
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
                material.knowledgeBaseName,
                material.folderPath,
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

public enum LibraryTreeBuilder {
    public static func folders(
        for knowledgeBaseID: UUID,
        in materials: [LibraryMaterial]
    ) -> [FolderNode] {
        let scoped = materials.filter {
            $0.manifest.knowledgeBaseID == knowledgeBaseID
        }
        var paths = Set<String>()
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
}
