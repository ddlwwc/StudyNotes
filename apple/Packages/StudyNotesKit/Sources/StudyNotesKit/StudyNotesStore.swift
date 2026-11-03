import Foundation

public enum StudyNotesError: Error, Equatable, Sendable, LocalizedError {
    case knowledgeBaseNotFound
    case folderNotFound
    case folderAlreadyExists
    case invalidFolderName
    case invalidFolderPath
    case invalidFolderMove
    case malformedMaterialPackage
    case materialNotFound
    case materialAlreadyExists
    case unsupportedSchemaVersion(Int)
    case fileCoordinationFailed

    public var errorDescription: String? {
        switch self {
        case .knowledgeBaseNotFound:
            "没有找到对应的知识库。"
        case .folderNotFound:
            "没有找到对应的文件夹。"
        case .folderAlreadyExists:
            "目标位置已存在同名文件夹。"
        case .invalidFolderName:
            "文件夹名称不能为空，也不能包含路径分隔符。"
        case .invalidFolderPath:
            "文件夹路径无效。"
        case .invalidFolderMove:
            "不能把文件夹移动到自身或其子文件夹中。"
        case .malformedMaterialPackage:
            "学习材料包已损坏或缺少必要文件。"
        case .materialNotFound:
            "没有找到对应的学习材料。"
        case .materialAlreadyExists:
            "目标位置已存在同一学习材料。"
        case .unsupportedSchemaVersion(let version):
            "学习材料包使用了不受支持的格式版本：\(version)。"
        case .fileCoordinationFailed:
            "无法协调文件访问，请稍后重试。"
        }
    }
}

public actor StudyNotesStore {
    private static let recycleRetentionInterval: TimeInterval = 30 * 24 * 60 * 60

    private let rootProvider: any StudyNotesRootProviding
    private let fileManager: FileManager
    private let fileCoordinator = NSFileCoordinator(filePresenter: nil)

    public init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootProvider = FixedStudyNotesRootProvider(status: .available(.local(rootURL)))
        self.fileManager = fileManager
    }

    public init(
        rootProvider: any StudyNotesRootProviding,
        fileManager: FileManager = .default
    ) {
        self.rootProvider = rootProvider
        self.fileManager = fileManager
    }

    public func rootStatus() -> StudyNotesRootStatus {
        rootProvider.resolveRootStatus()
    }

    public func createKnowledgeBase(named name: String) throws -> KnowledgeBase {
        let rootURL = try availableRootURL()
        try prepareRootDirectories(at: rootURL)
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        return try coordinatedWrite(at: rootURL) {
            let knowledgeBase = KnowledgeBase(
                id: UUID(),
                name: normalizedName,
                createdAt: Date()
            )
            let temporaryURL = librariesURL(at: rootURL).appending(
                path: ".tmp-\(knowledgeBase.id.uuidString)",
                directoryHint: .isDirectory
            )
            let destinationURL = knowledgeBaseURL(id: knowledgeBase.id, rootURL: rootURL)

            try fileManager.createDirectory(at: temporaryURL, withIntermediateDirectories: false)
            do {
                try encode(knowledgeBase).write(
                    to: temporaryURL.appending(path: "knowledge-base.json"),
                    options: .atomic
                )
                try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            } catch {
                try? fileManager.removeItem(at: temporaryURL)
                throw error
            }

            return knowledgeBase
        }
    }

    public func renameKnowledgeBase(id: UUID, to name: String) throws -> KnowledgeBase {
        let rootURL = try availableRootURL()
        try prepareRootDirectories(at: rootURL)
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        return try coordinatedWrite(at: rootURL) {
            let knowledgeBases = try loadKnowledgeBases(rootURL: rootURL)
            guard let index = knowledgeBases.firstIndex(where: { $0.id == id }) else {
                throw StudyNotesError.knowledgeBaseNotFound
            }

            var knowledgeBase = knowledgeBases[index]
            knowledgeBase.name = normalizedName
            let metadataURL = knowledgeBaseURL(id: id, rootURL: rootURL)
                .appending(path: "knowledge-base.json")
            try encode(knowledgeBase).write(to: metadataURL, options: .atomic)
            return knowledgeBase
        }
    }

    @discardableResult
    public func deleteKnowledgeBase(id: UUID) throws -> [UUID] {
        let rootURL = try availableRootURL()
        try prepareRootDirectories(at: rootURL)

        return try coordinatedWrite(at: rootURL) {
            let knowledgeBases = try loadKnowledgeBases(rootURL: rootURL)
            guard knowledgeBases.contains(where: { $0.id == id }) else {
                throw StudyNotesError.knowledgeBaseNotFound
            }

            let scan = try scanMaterialPackages(
                in: knowledgeBaseURL(id: id, rootURL: rootURL),
                knowledgeBaseID: id
            )
            let recycledIDs = try movePackagesToRecycle(
                scan.packages,
                rootURL: rootURL,
                now: Date()
            )
            try fileManager.removeItem(at: knowledgeBaseURL(id: id, rootURL: rootURL))
            return recycledIDs
        }
    }

    public func createFolder(
        named name: String,
        in knowledgeBaseID: UUID,
        parentPath: String = ""
    ) throws -> KnowledgeFolder {
        let rootURL = try availableRootURL()
        try prepareRootDirectories(at: rootURL)
        let normalizedParentPath = try normalizedFolderPath(parentPath)
        let normalizedName = try normalizedFolderName(name)

        return try coordinatedWrite(at: rootURL) {
            try requireKnowledgeBase(id: knowledgeBaseID, rootURL: rootURL)
            try requireFolder(
                path: normalizedParentPath,
                knowledgeBaseID: knowledgeBaseID,
                rootURL: rootURL
            )

            let path = joinFolderPath(normalizedParentPath, normalizedName)
            let destinationURL = folderURL(
                path: path,
                knowledgeBaseID: knowledgeBaseID,
                rootURL: rootURL
            )
            guard !fileManager.fileExists(atPath: destinationURL.path) else {
                throw StudyNotesError.folderAlreadyExists
            }

            try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: false)
            return KnowledgeFolder(
                knowledgeBaseID: knowledgeBaseID,
                name: normalizedName,
                path: path,
                parentPath: normalizedParentPath,
                depth: path.split(separator: "/").count
            )
        }
    }

    public func renameFolder(
        at path: String,
        in knowledgeBaseID: UUID,
        to name: String
    ) throws -> KnowledgeFolder {
        let rootURL = try availableRootURL()
        try prepareRootDirectories(at: rootURL)
        let normalizedPath = try normalizedFolderPath(path)
        let normalizedName = try normalizedFolderName(name)
        guard !normalizedPath.isEmpty else {
            throw StudyNotesError.folderNotFound
        }

        return try coordinatedWrite(at: rootURL) {
            try requireKnowledgeBase(id: knowledgeBaseID, rootURL: rootURL)
            try requireFolder(
                path: normalizedPath,
                knowledgeBaseID: knowledgeBaseID,
                rootURL: rootURL
            )

            let parentPath = parentFolderPath(of: normalizedPath)
            let destinationPath = joinFolderPath(parentPath, normalizedName)
            let sourceURL = folderURL(
                path: normalizedPath,
                knowledgeBaseID: knowledgeBaseID,
                rootURL: rootURL
            )
            let destinationURL = folderURL(
                path: destinationPath,
                knowledgeBaseID: knowledgeBaseID,
                rootURL: rootURL
            )

            if destinationPath == normalizedPath {
                return KnowledgeFolder(
                    knowledgeBaseID: knowledgeBaseID,
                    name: normalizedName,
                    path: normalizedPath,
                    parentPath: parentPath,
                    depth: normalizedPath.split(separator: "/").count
                )
            }
            guard !fileManager.fileExists(atPath: destinationURL.path) else {
                throw StudyNotesError.folderAlreadyExists
            }

            try moveFolderAtomically(
                from: sourceURL,
                to: destinationURL,
                knowledgeBaseID: knowledgeBaseID,
                destinationFolderPath: destinationPath
            )
            return KnowledgeFolder(
                knowledgeBaseID: knowledgeBaseID,
                name: normalizedName,
                path: destinationPath,
                parentPath: parentPath,
                depth: destinationPath.split(separator: "/").count
            )
        }
    }

    public func moveFolder(
        at path: String,
        in knowledgeBaseID: UUID,
        toParentPath parentPath: String
    ) throws -> KnowledgeFolder {
        let rootURL = try availableRootURL()
        try prepareRootDirectories(at: rootURL)
        let normalizedPath = try normalizedFolderPath(path)
        let normalizedParentPath = try normalizedFolderPath(parentPath)
        guard !normalizedPath.isEmpty else {
            throw StudyNotesError.folderNotFound
        }
        guard !isSameOrDescendantPath(normalizedParentPath, of: normalizedPath) else {
            throw StudyNotesError.invalidFolderMove
        }

        return try coordinatedWrite(at: rootURL) {
            try requireKnowledgeBase(id: knowledgeBaseID, rootURL: rootURL)
            try requireFolder(
                path: normalizedPath,
                knowledgeBaseID: knowledgeBaseID,
                rootURL: rootURL
            )
            try requireFolder(
                path: normalizedParentPath,
                knowledgeBaseID: knowledgeBaseID,
                rootURL: rootURL
            )

            let folderName = normalizedPath.split(separator: "/").last.map(String.init) ?? ""
            let destinationPath = joinFolderPath(normalizedParentPath, folderName)
            let sourceURL = folderURL(
                path: normalizedPath,
                knowledgeBaseID: knowledgeBaseID,
                rootURL: rootURL
            )
            let destinationURL = folderURL(
                path: destinationPath,
                knowledgeBaseID: knowledgeBaseID,
                rootURL: rootURL
            )

            if destinationPath == normalizedPath {
                return KnowledgeFolder(
                    knowledgeBaseID: knowledgeBaseID,
                    name: folderName,
                    path: normalizedPath,
                    parentPath: normalizedParentPath,
                    depth: normalizedPath.split(separator: "/").count
                )
            }
            guard !fileManager.fileExists(atPath: destinationURL.path) else {
                throw StudyNotesError.folderAlreadyExists
            }

            try moveFolderAtomically(
                from: sourceURL,
                to: destinationURL,
                knowledgeBaseID: knowledgeBaseID,
                destinationFolderPath: destinationPath
            )
            return KnowledgeFolder(
                knowledgeBaseID: knowledgeBaseID,
                name: folderName,
                path: destinationPath,
                parentPath: normalizedParentPath,
                depth: destinationPath.split(separator: "/").count
            )
        }
    }

    @discardableResult
    public func deleteFolder(
        at path: String,
        in knowledgeBaseID: UUID
    ) throws -> [UUID] {
        let rootURL = try availableRootURL()
        try prepareRootDirectories(at: rootURL)
        let normalizedPath = try normalizedFolderPath(path)
        guard !normalizedPath.isEmpty else {
            throw StudyNotesError.folderNotFound
        }

        return try coordinatedWrite(at: rootURL) {
            try requireKnowledgeBase(id: knowledgeBaseID, rootURL: rootURL)
            try requireFolder(
                path: normalizedPath,
                knowledgeBaseID: knowledgeBaseID,
                rootURL: rootURL
            )

            let scan = try scanMaterialPackages(
                in: knowledgeBaseURL(id: knowledgeBaseID, rootURL: rootURL),
                knowledgeBaseID: knowledgeBaseID
            )
            let packages = scan.packages.filter {
                isSameOrDescendantPath($0.folderPath, of: normalizedPath)
            }
            let recycledIDs = try movePackagesToRecycle(
                packages,
                rootURL: rootURL,
                now: Date()
            )
            let folderURL = folderURL(
                path: normalizedPath,
                knowledgeBaseID: knowledgeBaseID,
                rootURL: rootURL
            )
            try fileManager.removeItem(at: folderURL)
            return recycledIDs
        }
    }

    public func createMarkdownNote(
        title: String,
        in knowledgeBaseID: UUID,
        markdown: String,
        folderPath: String = "",
        tags: [String] = []
    ) throws -> MarkdownNote {
        let rootURL = try availableRootURL()
        try prepareRootDirectories(at: rootURL)
        let normalizedFolderPath = try normalizedFolderPath(folderPath)

        return try coordinatedWrite(at: rootURL) {
            try requireKnowledgeBase(id: knowledgeBaseID, rootURL: rootURL)
            try requireFolder(
                path: normalizedFolderPath,
                knowledgeBaseID: knowledgeBaseID,
                rootURL: rootURL
            )
            return try createMarkdownPackage(
                title: title,
                markdown: markdown,
                knowledgeBaseID: knowledgeBaseID,
                folderPath: normalizedFolderPath,
                tags: tags,
                rootURL: rootURL
            )
        }
    }

    public func createInboxMarkdownNote(
        title: String,
        markdown: String,
        tags: [String] = []
    ) throws -> MarkdownNote {
        let rootURL = try availableRootURL()
        try prepareRootDirectories(at: rootURL)

        return try coordinatedWrite(at: rootURL) {
            try createMarkdownPackage(
                title: title,
                markdown: markdown,
                knowledgeBaseID: nil,
                folderPath: "",
                tags: tags,
                rootURL: rootURL
            )
        }
    }

    public func loadIndex() throws -> LibraryIndex {
        let rootURL = try availableRootURL()
        try prepareRootDirectories(at: rootURL)

        return try coordinatedRead(at: rootURL) {
            let knowledgeBases = try loadKnowledgeBases(rootURL: rootURL)
            var materials: [StudyMaterialSummary] = []
            var folders: [KnowledgeFolder] = []

            for knowledgeBase in knowledgeBases {
                let scan = try scanMaterialPackages(
                    in: knowledgeBaseURL(id: knowledgeBase.id, rootURL: rootURL),
                    knowledgeBaseID: knowledgeBase.id
                )
                folders.append(contentsOf: scan.folders)
                materials.append(
                    contentsOf: try summaries(
                        from: scan.packages,
                        placement: .knowledgeBase(knowledgeBase.id)
                    )
                )
            }

            let inboxScan = try scanMaterialPackages(
                in: inboxURL(at: rootURL),
                knowledgeBaseID: nil
            )
            let inboxMaterials = try summaries(
                from: inboxScan.packages,
                placement: .inbox
            )

            let recycleBinScan = try scanMaterialPackages(
                in: recycleBinURL(at: rootURL),
                knowledgeBaseID: nil
            )
            let recycledMaterials = try summaries(
                from: recycleBinScan.packages,
                placement: .recycleBin
            )

            let tags = sortedUniqueTags(
                (materials + inboxMaterials).flatMap(\.tags)
            )

            return LibraryIndex(
                knowledgeBases: knowledgeBases,
                materials: sortedMaterials(materials),
                folders: folders.sorted(by: folderSort),
                inboxMaterials: sortedMaterials(inboxMaterials),
                recycledMaterials: sortedRecycledMaterials(recycledMaterials),
                tags: tags
            )
        }
    }

    public func loadMarkdownNote(id: UUID) throws -> MarkdownNote {
        let rootURL = try availableRootURL()
        try prepareRootDirectories(at: rootURL)

        return try coordinatedRead(at: rootURL) {
            guard let locatedMaterial = try locateMaterial(
                id: id,
                rootURL: rootURL,
                includeRecycled: true
            ) else {
                throw StudyNotesError.materialNotFound
            }
            let markdownURL = locatedMaterial.packageURL
                .appending(path: "content", directoryHint: .isDirectory)
                .appending(path: "note.md")
            let markdown = try String(contentsOf: markdownURL, encoding: .utf8)

            return MarkdownNote(
                summary: try summary(for: locatedMaterial),
                markdown: markdown
            )
        }
    }

    @discardableResult
    public func moveMaterials(
        ids: [UUID],
        toKnowledgeBaseID knowledgeBaseID: UUID?,
        folderPath: String = ""
    ) throws -> [UUID] {
        let rootURL = try availableRootURL()
        try prepareRootDirectories(at: rootURL)
        let normalizedFolderPath = try normalizedFolderPath(folderPath)

        return try coordinatedWrite(at: rootURL) {
            if let knowledgeBaseID {
                try requireKnowledgeBase(id: knowledgeBaseID, rootURL: rootURL)
                try requireFolder(
                    path: normalizedFolderPath,
                    knowledgeBaseID: knowledgeBaseID,
                    rootURL: rootURL
                )
            } else {
                guard normalizedFolderPath.isEmpty else {
                    throw StudyNotesError.invalidFolderPath
                }
            }

            let uniqueIDs = unique(ids)
            var plans: [(
                located: LocatedMaterial,
                destinationURL: URL,
                manifest: MaterialManifest,
                conflicts: [(sourceURL: URL, destinationURL: URL)]
            )] = []

            for id in uniqueIDs {
                guard let located = try locateMaterial(
                    id: id,
                    rootURL: rootURL,
                    includeRecycled: false
                ) else {
                    throw StudyNotesError.materialNotFound
                }

                let destinationDirectory = try destinationDirectory(
                    knowledgeBaseID: knowledgeBaseID,
                    folderPath: normalizedFolderPath,
                    rootURL: rootURL
                )
                let destinationURL = destinationDirectory.appending(
                    path: located.packageURL.lastPathComponent,
                    directoryHint: .isDirectory
                )
                guard located.packageURL.standardizedFileURL != destinationURL.standardizedFileURL else {
                    continue
                }
                guard !fileManager.fileExists(atPath: destinationURL.path) else {
                    throw StudyNotesError.materialAlreadyExists
                }

                var manifest = located.manifest
                manifest.knowledgeBaseID = knowledgeBaseID
                manifest.folderPath = normalizedFolderPath
                manifest.updatedAt = Date()
                manifest.deletedAt = nil
                manifest.originalLocation = nil

                let conflicts = try siblingConflictURLs(
                    for: located.packageURL,
                    materialID: id
                ).map { conflictURL in
                    let conflictDestinationURL = destinationDirectory.appending(
                        path: conflictURL.lastPathComponent,
                        directoryHint: .isDirectory
                    )
                    guard !fileManager.fileExists(atPath: conflictDestinationURL.path) else {
                        throw StudyNotesError.materialAlreadyExists
                    }
                    return (conflictURL, conflictDestinationURL)
                }
                plans.append((located, destinationURL, manifest, conflicts))
            }

            var completedMoves: [CompletedPackageMove] = []
            do {
                for plan in plans {
                    try writeManifest(plan.manifest, to: plan.located.packageURL)
                    do {
                        try fileManager.moveItem(
                            at: plan.located.packageURL,
                            to: plan.destinationURL
                        )
                        completedMoves.append(
                            CompletedPackageMove(
                                sourceURL: plan.located.packageURL,
                                destinationURL: plan.destinationURL,
                                originalManifest: plan.located.manifest
                            )
                        )
                        for conflict in plan.conflicts {
                            try fileManager.moveItem(
                                at: conflict.sourceURL,
                                to: conflict.destinationURL
                            )
                            completedMoves.append(
                                CompletedPackageMove(
                                    sourceURL: conflict.sourceURL,
                                    destinationURL: conflict.destinationURL,
                                    originalManifest: nil
                                )
                            )
                        }
                    } catch {
                        try? writeManifest(
                            plan.located.manifest,
                            to: plan.located.packageURL
                        )
                        throw error
                    }
                }
            } catch {
                rollbackMoves(completedMoves)
                throw error
            }

            return uniqueIDs
        }
    }

    public func setTags(
        _ tags: [String],
        onMaterialIDs ids: [UUID]
    ) throws -> [StudyMaterialSummary] {
        try updateTags(ids: ids) { _ in normalizedTags(tags) }
    }

    public func addTags(
        _ tags: [String],
        toMaterialIDs ids: [UUID]
    ) throws -> [StudyMaterialSummary] {
        try updateTags(ids: ids) { manifest in
            normalizedTags(manifest.tags + tags)
        }
    }

    public func removeTags(
        _ tags: [String],
        fromMaterialIDs ids: [UUID]
    ) throws -> [StudyMaterialSummary] {
        let removedTags = Set(normalizedTags(tags))
        return try updateTags(ids: ids) { manifest in
            manifest.tags.filter { !removedTags.contains($0) }
        }
    }

    @discardableResult
    public func moveMaterialsToRecycleBin(
        ids: [UUID],
        now: Date = Date()
    ) throws -> [UUID] {
        let rootURL = try availableRootURL()
        try prepareRootDirectories(at: rootURL)

        return try coordinatedWrite(at: rootURL) {
            let uniqueIDs = unique(ids)
            var packages: [ScannedPackage] = []
            var seenPaths = Set<String>()

            for id in uniqueIDs {
                guard let located = try locateMaterial(
                    id: id,
                    rootURL: rootURL,
                    includeRecycled: false
                ) else {
                    throw StudyNotesError.materialNotFound
                }
                if seenPaths.insert(located.packageURL.standardizedFileURL.path).inserted {
                    packages.append(located.package)
                }
                for conflictURL in try siblingConflictURLs(
                    for: located.packageURL,
                    materialID: id
                ) where seenPaths.insert(conflictURL.standardizedFileURL.path).inserted {
                    packages.append(
                        ScannedPackage(
                            packageURL: conflictURL,
                            folderPath: located.package.folderPath,
                            manifest: nil
                        )
                    )
                }
            }

            return try movePackagesToRecycle(
                packages,
                rootURL: rootURL,
                now: now
            )
        }
    }

    @discardableResult
    public func restoreMaterials(ids: [UUID]) throws -> [UUID] {
        let rootURL = try availableRootURL()
        try prepareRootDirectories(at: rootURL)

        return try coordinatedWrite(at: rootURL) {
            let uniqueIDs = unique(ids)
            var plans: [(
                located: LocatedMaterial,
                destinationURL: URL,
                manifest: MaterialManifest,
                conflicts: [(sourceURL: URL, destinationURL: URL)]
            )] = []

            for id in uniqueIDs {
                guard let located = try locateMaterial(
                    id: id,
                    rootURL: rootURL,
                    includeRecycled: true
                ), located.placement.isRecycleBin else {
                    throw StudyNotesError.materialNotFound
                }

                let originalLocation = located.manifest.originalLocation
                let destinationKnowledgeBaseID = originalLocation?.knowledgeBaseID
                let destinationFolderPath = originalLocation?.folderPath ?? ""
                let destinationDirectory: URL
                var resolvedKnowledgeBaseID = destinationKnowledgeBaseID
                var resolvedFolderPath = destinationFolderPath

                if let destinationKnowledgeBaseID,
                   fileManager.fileExists(
                       atPath: knowledgeBaseURL(
                           id: destinationKnowledgeBaseID,
                           rootURL: rootURL
                       ).path
                   ) {
                    if !destinationFolderPath.isEmpty,
                       try folderExists(
                           path: destinationFolderPath,
                           knowledgeBaseID: destinationKnowledgeBaseID,
                           rootURL: rootURL
                       ) {
                        destinationDirectory = folderURL(
                            path: destinationFolderPath,
                            knowledgeBaseID: destinationKnowledgeBaseID,
                            rootURL: rootURL
                        )
                    } else {
                        resolvedFolderPath = ""
                        destinationDirectory = knowledgeBaseURL(
                            id: destinationKnowledgeBaseID,
                            rootURL: rootURL
                        )
                    }
                } else {
                    resolvedKnowledgeBaseID = nil
                    resolvedFolderPath = ""
                    destinationDirectory = inboxURL(at: rootURL)
                }

                let destinationURL = destinationDirectory.appending(
                    path: located.packageURL.lastPathComponent,
                    directoryHint: .isDirectory
                )
                guard !fileManager.fileExists(atPath: destinationURL.path) else {
                    throw StudyNotesError.materialAlreadyExists
                }

                var manifest = located.manifest
                manifest.knowledgeBaseID = resolvedKnowledgeBaseID
                manifest.folderPath = resolvedFolderPath
                manifest.updatedAt = Date()
                manifest.deletedAt = nil
                manifest.originalLocation = nil

                let conflicts = try siblingConflictURLs(
                    for: located.packageURL,
                    materialID: id
                ).map { conflictURL in
                    let conflictDestinationURL = destinationDirectory.appending(
                        path: conflictURL.lastPathComponent,
                        directoryHint: .isDirectory
                    )
                    guard !fileManager.fileExists(atPath: conflictDestinationURL.path) else {
                        throw StudyNotesError.materialAlreadyExists
                    }
                    return (conflictURL, conflictDestinationURL)
                }
                plans.append((located, destinationURL, manifest, conflicts))
            }

            var completedMoves: [CompletedPackageMove] = []
            do {
                for plan in plans {
                    try writeManifest(plan.manifest, to: plan.located.packageURL)
                    do {
                        try fileManager.moveItem(
                            at: plan.located.packageURL,
                            to: plan.destinationURL
                        )
                        completedMoves.append(
                            CompletedPackageMove(
                                sourceURL: plan.located.packageURL,
                                destinationURL: plan.destinationURL,
                                originalManifest: plan.located.manifest
                            )
                        )
                        for conflict in plan.conflicts {
                            try fileManager.moveItem(
                                at: conflict.sourceURL,
                                to: conflict.destinationURL
                            )
                            completedMoves.append(
                                CompletedPackageMove(
                                    sourceURL: conflict.sourceURL,
                                    destinationURL: conflict.destinationURL,
                                    originalManifest: nil
                                )
                            )
                        }
                    } catch {
                        try? writeManifest(
                            plan.located.manifest,
                            to: plan.located.packageURL
                        )
                        throw error
                    }
                }
            } catch {
                rollbackMoves(completedMoves)
                throw error
            }

            return uniqueIDs
        }
    }

    @discardableResult
    public func purgeExpiredRecycleBin(now: Date = Date()) throws -> [UUID] {
        let rootURL = try availableRootURL()
        try prepareRootDirectories(at: rootURL)

        return try coordinatedWrite(at: rootURL) {
            let scan = try scanMaterialPackages(
                in: recycleBinURL(at: rootURL),
                knowledgeBaseID: nil
            )
            let regularPackages = scan.packages.filter { $0.manifest != nil }
            let expiredPackages = regularPackages.filter { package in
                guard let deletedAt = package.manifest?.deletedAt else {
                    return false
                }
                return now.timeIntervalSince(deletedAt) > Self.recycleRetentionInterval
            }

            var purgedIDs: [UUID] = []
            for package in expiredPackages {
                guard let manifest = package.manifest else {
                    continue
                }
                let conflicts = try siblingConflictURLs(
                    for: package.packageURL,
                    materialID: manifest.id
                )
                for conflictURL in conflicts {
                    try fileManager.removeItem(at: conflictURL)
                }
                try fileManager.removeItem(at: package.packageURL)
                purgedIDs.append(manifest.id)
            }
            return purgedIDs
        }
    }

    private func updateTags(
        ids: [UUID],
        transform: (MaterialManifest) -> [String]
    ) throws -> [StudyMaterialSummary] {
        let rootURL = try availableRootURL()
        try prepareRootDirectories(at: rootURL)

        return try coordinatedWrite(at: rootURL) {
            var summaries: [StudyMaterialSummary] = []
            var completedUpdates: [(LocatedMaterial, MaterialManifest)] = []
            do {
                for id in unique(ids) {
                    guard let located = try locateMaterial(
                        id: id,
                        rootURL: rootURL,
                        includeRecycled: true
                    ) else {
                        throw StudyNotesError.materialNotFound
                    }
                    var manifest = located.manifest
                    manifest.tags = transform(manifest)
                    manifest.updatedAt = Date()
                    try writeManifest(manifest, to: located.packageURL)
                    completedUpdates.append((located, located.manifest))

                    var updatedLocation = located
                    updatedLocation.manifest = manifest
                    summaries.append(try summary(for: updatedLocation))
                }
            } catch {
                for (located, originalManifest) in completedUpdates.reversed() {
                    try? writeManifest(originalManifest, to: located.packageURL)
                }
                throw error
            }
            return summaries
        }
    }

    private func createMarkdownPackage(
        title: String,
        markdown: String,
        knowledgeBaseID: UUID?,
        folderPath: String,
        tags: [String],
        rootURL: URL
    ) throws -> MarkdownNote {
        let now = Date()
        let materialID = UUID()
        let manifest = MaterialManifest(
            schemaVersion: StudyNotesKit.schemaVersion,
            id: materialID,
            knowledgeBaseID: knowledgeBaseID,
            kind: .note,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: now,
            updatedAt: now,
            folderPath: folderPath,
            tags: normalizedTags(tags),
            deletedAt: nil,
            originalLocation: nil
        )
        let destinationDirectory = try destinationDirectory(
            knowledgeBaseID: knowledgeBaseID,
            folderPath: folderPath,
            rootURL: rootURL
        )
        let packageName = "\(materialID.uuidString).studyitem"
        let temporaryURL = destinationDirectory.appending(
            path: ".tmp-\(materialID.uuidString)",
            directoryHint: .isDirectory
        )
        let destinationURL = destinationDirectory.appending(
            path: packageName,
            directoryHint: .isDirectory
        )
        let contentURL = temporaryURL
            .appending(path: "content", directoryHint: .isDirectory)
            .appending(path: "note.md")

        try fileManager.createDirectory(
            at: contentURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        do {
            try encode(manifest).write(
                to: temporaryURL.appending(path: "manifest.json"),
                options: .atomic
            )
            try Data(markdown.utf8).write(to: contentURL, options: .atomic)
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }

        return MarkdownNote(
            summary: manifest.summary(
                knowledgeBaseID: knowledgeBaseID,
                folderPath: folderPath,
                conflictCopies: []
            ),
            markdown: markdown
        )
    }

    private func availableRootURL() throws -> URL {
        let status = rootProvider.resolveRootStatus()
        switch status {
        case .available(let location):
            return location.url
        case .iCloudNotSignedIn:
            throw StudyNotesStorageUnavailableError(reason: .iCloudNotSignedIn)
        case .iCloudContainerUnavailable:
            throw StudyNotesStorageUnavailableError(reason: .iCloudContainerUnavailable)
        }
    }

    private func coordinatedRead<T>(
        at url: URL,
        _ body: () throws -> T
    ) throws -> T {
        guard shouldCoordinateFileAccess else {
            return try body()
        }

        var coordinationError: NSError?
        var result: Result<T, Error>?

        fileCoordinator.coordinate(
            readingItemAt: url,
            options: [],
            error: &coordinationError
        ) { _ in
            result = Result { try body() }
        }

        if let coordinationError {
            throw coordinationError
        }
        guard let result else {
            throw StudyNotesError.fileCoordinationFailed
        }
        return try result.get()
    }

    private func coordinatedWrite<T>(
        at url: URL,
        options: NSFileCoordinator.WritingOptions = [],
        _ body: () throws -> T
    ) throws -> T {
        guard shouldCoordinateFileAccess else {
            return try body()
        }

        var coordinationError: NSError?
        var result: Result<T, Error>?

        fileCoordinator.coordinate(
            writingItemAt: url,
            options: options,
            error: &coordinationError
        ) { _ in
            result = Result { try body() }
        }

        if let coordinationError {
            throw coordinationError
        }
        guard let result else {
            throw StudyNotesError.fileCoordinationFailed
        }
        return try result.get()
    }

    private var shouldCoordinateFileAccess: Bool {
        guard case .available(.iCloud) = rootProvider.resolveRootStatus() else {
            return false
        }
        return true
    }

    private func librariesURL(at rootURL: URL) -> URL {
        rootURL.appending(path: "Libraries", directoryHint: .isDirectory)
    }

    private func inboxURL(at rootURL: URL) -> URL {
        rootURL.appending(path: "Inbox", directoryHint: .isDirectory)
    }

    private func recycleBinURL(at rootURL: URL) -> URL {
        rootURL.appending(path: "RecycleBin", directoryHint: .isDirectory)
    }

    private func knowledgeBaseURL(id: UUID, rootURL: URL) -> URL {
        librariesURL(at: rootURL).appending(path: id.uuidString, directoryHint: .isDirectory)
    }

    private func prepareRootDirectories(at rootURL: URL) throws {
        try coordinatedWrite(at: rootURL) {
            for directoryURL in [
                rootURL,
                librariesURL(at: rootURL),
                inboxURL(at: rootURL),
                recycleBinURL(at: rootURL)
            ] {
                try fileManager.createDirectory(
                    at: directoryURL,
                    withIntermediateDirectories: true
                )
            }
            for containerURL in [
                librariesURL(at: rootURL),
                inboxURL(at: rootURL),
                recycleBinURL(at: rootURL)
            ] {
                guard isRegularDirectory(containerURL),
                      !containsSymbolicLink(from: rootURL, to: containerURL) else {
                    throw StudyNotesError.invalidFolderPath
                }
            }
        }
    }

    private func loadKnowledgeBases(rootURL: URL) throws -> [KnowledgeBase] {
        let directoryURLs = try fileManager.contentsOfDirectory(
            at: librariesURL(at: rootURL),
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )

        return try directoryURLs
            .filter { directoryURL in
                let metadataURL = directoryURL.appending(path: "knowledge-base.json")
                return fileManager.fileExists(atPath: metadataURL.path)
                    && isRegularDirectory(directoryURL)
            }
            .map { directoryURL in
                let metadataURL = directoryURL.appending(path: "knowledge-base.json")
                let data = try Data(contentsOf: metadataURL)
                return try decoder.decode(KnowledgeBase.self, from: data)
            }
            .sorted {
                if $0.createdAt == $1.createdAt {
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                return $0.createdAt < $1.createdAt
            }
    }

    private func requireKnowledgeBase(id: UUID, rootURL: URL) throws {
        let knowledgeBaseURL = knowledgeBaseURL(id: id, rootURL: rootURL)
        let metadataURL = knowledgeBaseURL
            .appending(path: "knowledge-base.json")
        guard fileManager.fileExists(atPath: metadataURL.path),
              isRegularDirectory(knowledgeBaseURL),
              !containsSymbolicLink(
                  from: librariesURL(at: rootURL),
                  to: knowledgeBaseURL
              )
        else {
            throw StudyNotesError.knowledgeBaseNotFound
        }
    }

    private func destinationDirectory(
        knowledgeBaseID: UUID?,
        folderPath: String,
        rootURL: URL
    ) throws -> URL {
        if let knowledgeBaseID {
            try requireKnowledgeBase(id: knowledgeBaseID, rootURL: rootURL)
            try requireFolder(
                path: folderPath,
                knowledgeBaseID: knowledgeBaseID,
                rootURL: rootURL
            )
            return folderPath.isEmpty
                ? knowledgeBaseURL(id: knowledgeBaseID, rootURL: rootURL)
                : folderURL(
                    path: folderPath,
                    knowledgeBaseID: knowledgeBaseID,
                    rootURL: rootURL
                )
        }

        guard folderPath.isEmpty else {
            throw StudyNotesError.invalidFolderPath
        }
        return inboxURL(at: rootURL)
    }

    private func requireFolder(
        path: String,
        knowledgeBaseID: UUID,
        rootURL: URL
    ) throws {
        guard !path.isEmpty else {
            return
        }
        guard try folderExists(
            path: path,
            knowledgeBaseID: knowledgeBaseID,
            rootURL: rootURL
        ) else {
            throw StudyNotesError.folderNotFound
        }
    }

    private func folderExists(
        path: String,
        knowledgeBaseID: UUID,
        rootURL: URL
    ) throws -> Bool {
        let normalizedPath = try normalizedFolderPath(path)
        guard !normalizedPath.isEmpty else {
            return true
        }
        let folderURL = folderURL(
            path: normalizedPath,
            knowledgeBaseID: knowledgeBaseID,
            rootURL: rootURL
        )
        guard !containsSymbolicLink(
            from: knowledgeBaseURL(id: knowledgeBaseID, rootURL: rootURL),
            to: folderURL
        ) else {
            throw StudyNotesError.invalidFolderPath
        }
        return fileManager.fileExists(atPath: folderURL.path)
            && isRegularDirectory(folderURL)
    }

    private func folderURL(
        path: String,
        knowledgeBaseID: UUID,
        rootURL: URL
    ) -> URL {
        knowledgeBaseURL(id: knowledgeBaseID, rootURL: rootURL)
            .appending(path: path, directoryHint: .isDirectory)
    }

    private func isRegularDirectory(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        ) else {
            return false
        }
        return values.isDirectory == true && values.isSymbolicLink != true
    }

    private func containsSymbolicLink(from baseURL: URL, to targetURL: URL) -> Bool {
        let baseComponents = baseURL.standardizedFileURL.pathComponents
        let targetComponents = targetURL.standardizedFileURL.pathComponents
        guard targetComponents.starts(with: baseComponents) else {
            return true
        }

        var currentURL = baseURL.standardizedFileURL
        for component in targetComponents.dropFirst(baseComponents.count) {
            currentURL.append(path: component)
            if (try? currentURL.resourceValues(
                forKeys: [.isSymbolicLinkKey]
            ).isSymbolicLink) == true {
                return true
            }
        }
        return false
    }

    private func scanMaterialPackages(
        in containerURL: URL,
        knowledgeBaseID: UUID?
    ) throws -> ContainerScan {
        guard fileManager.fileExists(atPath: containerURL.path) else {
            return ContainerScan(packages: [], folders: [])
        }

        var packages: [ScannedPackage] = []
        var folders: [KnowledgeFolder] = []

        func walk(_ directoryURL: URL, relativePath: String) throws {
            let children = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )

            for childURL in children {
                guard isRegularDirectory(childURL) else {
                    continue
                }

                let childPath = joinFolderPath(relativePath, childURL.lastPathComponent)
                if childURL.pathExtension == "studyitem" {
                    if isConflictCopy(childURL) {
                        packages.append(
                            ScannedPackage(
                                packageURL: childURL,
                                folderPath: relativePath,
                                manifest: nil
                            )
                        )
                    } else {
                        packages.append(
                            ScannedPackage(
                                packageURL: childURL,
                                folderPath: relativePath,
                                manifest: try loadManifest(from: childURL)
                            )
                        )
                    }
                    continue
                }

                if let knowledgeBaseID, !relativePath.isEmpty || !childURL.pathExtension.isEmpty {
                    folders.append(
                        KnowledgeFolder(
                            knowledgeBaseID: knowledgeBaseID,
                            name: childURL.lastPathComponent,
                            path: childPath,
                            parentPath: relativePath,
                            depth: childPath.split(separator: "/").count
                        )
                    )
                } else if let knowledgeBaseID {
                    folders.append(
                        KnowledgeFolder(
                            knowledgeBaseID: knowledgeBaseID,
                            name: childURL.lastPathComponent,
                            path: childPath,
                            parentPath: "",
                            depth: 1
                        )
                    )
                }

                try walk(childURL, relativePath: childPath)
            }
        }

        try walk(containerURL, relativePath: "")
        return ContainerScan(packages: packages, folders: folders)
    }

    private func summaries(
        from packages: [ScannedPackage],
        placement: MaterialPlacement
    ) throws -> [StudyMaterialSummary] {
        var summaries: [StudyMaterialSummary] = []
        for package in packages {
            guard let manifest = package.manifest else {
                continue
            }
            let located = LocatedMaterial(
                package: package,
                manifest: manifest,
                placement: placement
            )
            summaries.append(try summary(for: located))
        }
        return summaries
    }

    private func summary(for located: LocatedMaterial) throws -> StudyMaterialSummary {
        let conflictCopies = try conflictCopies(
            in: located.package.packageURL.deletingLastPathComponent(),
            materialID: located.manifest.id
        ) + nestedConflictCopies(in: located.package.packageURL)

        switch located.placement {
        case .knowledgeBase(let knowledgeBaseID):
            return located.manifest.summary(
                knowledgeBaseID: knowledgeBaseID,
                folderPath: located.package.folderPath,
                conflictCopies: conflictCopies
            )
        case .inbox:
            return located.manifest.summary(
                knowledgeBaseID: nil,
                folderPath: located.package.folderPath,
                conflictCopies: conflictCopies
            )
        case .recycleBin:
            let originalLocation = located.manifest.originalLocation
            return located.manifest.summary(
                knowledgeBaseID: originalLocation?.knowledgeBaseID,
                folderPath: originalLocation?.folderPath ?? "",
                conflictCopies: conflictCopies
            )
        }
    }

    private func locateMaterial(
        id: UUID,
        rootURL: URL,
        includeRecycled: Bool
    ) throws -> LocatedMaterial? {
        for knowledgeBase in try loadKnowledgeBases(rootURL: rootURL) {
            let scan = try scanMaterialPackages(
                in: knowledgeBaseURL(id: knowledgeBase.id, rootURL: rootURL),
                knowledgeBaseID: knowledgeBase.id
            )
            if let package = scan.packages.first(where: {
                !isConflictCopy($0.packageURL) && $0.manifest?.id == id
            }), let manifest = package.manifest {
                return LocatedMaterial(
                    package: package,
                    manifest: manifest,
                    placement: .knowledgeBase(knowledgeBase.id)
                )
            }
        }

        let inboxScan = try scanMaterialPackages(
            in: inboxURL(at: rootURL),
            knowledgeBaseID: nil
        )
        if let package = inboxScan.packages.first(where: {
            !isConflictCopy($0.packageURL) && $0.manifest?.id == id
        }), let manifest = package.manifest {
            return LocatedMaterial(
                package: package,
                manifest: manifest,
                placement: .inbox
            )
        }

        guard includeRecycled else {
            return nil
        }
        let recycleBinScan = try scanMaterialPackages(
            in: recycleBinURL(at: rootURL),
            knowledgeBaseID: nil
        )
        if let package = recycleBinScan.packages.first(where: {
            !isConflictCopy($0.packageURL) && $0.manifest?.id == id
        }), let manifest = package.manifest {
            return LocatedMaterial(
                package: package,
                manifest: manifest,
                placement: .recycleBin
            )
        }

        return nil
    }

    private func movePackagesToRecycle(
        _ packages: [ScannedPackage],
        rootURL: URL,
        now: Date
    ) throws -> [UUID] {
        let recycleBinURL = recycleBinURL(at: rootURL)
        var destinationURLs = Set<String>()
        var plans: [(ScannedPackage, URL, MaterialManifest?)] = []
        var recycledIDs: [UUID] = []

        for package in packages {
            let destinationURL = recycleBinURL.appending(
                path: package.packageURL.lastPathComponent,
                directoryHint: .isDirectory
            )
            let standardizedPath = destinationURL.standardizedFileURL.path
            guard !fileManager.fileExists(atPath: destinationURL.path),
                  destinationURLs.insert(standardizedPath).inserted
            else {
                throw StudyNotesError.materialAlreadyExists
            }

            if let manifest = package.manifest {
                var recycledManifest = manifest
                recycledManifest.deletedAt = now
                recycledManifest.updatedAt = now
                recycledManifest.originalLocation = MaterialOriginalLocation(
                    knowledgeBaseID: manifest.knowledgeBaseID,
                    folderPath: package.folderPath
                )
                plans.append((package, destinationURL, recycledManifest))
                recycledIDs.append(manifest.id)
            } else {
                plans.append((package, destinationURL, nil))
            }
        }

        var completedMoves: [CompletedPackageMove] = []
        do {
            for (package, destinationURL, recycledManifest) in plans {
                if let recycledManifest {
                    try writeManifest(recycledManifest, to: package.packageURL)
                }
                do {
                    try fileManager.moveItem(
                        at: package.packageURL,
                        to: destinationURL
                    )
                    completedMoves.append(
                        CompletedPackageMove(
                            sourceURL: package.packageURL,
                            destinationURL: destinationURL,
                            originalManifest: package.manifest
                        )
                    )
                } catch {
                    if let manifest = package.manifest {
                        try? writeManifest(manifest, to: package.packageURL)
                    }
                    throw error
                }
            }
        } catch {
            rollbackMoves(completedMoves)
            throw error
        }

        return recycledIDs
    }

    private func moveFolderAtomically(
        from sourceURL: URL,
        to destinationURL: URL,
        knowledgeBaseID: UUID,
        destinationFolderPath: String
    ) throws {
        let scan = try scanMaterialPackages(
            in: sourceURL,
            knowledgeBaseID: knowledgeBaseID
        )

        let updates: [(
            packageURL: URL,
            originalManifest: MaterialManifest,
            updatedManifest: MaterialManifest
        )] = scan.packages.compactMap { package in
            guard var manifest = package.manifest else {
                return nil
            }
            let originalManifest = manifest
            manifest.knowledgeBaseID = knowledgeBaseID
            manifest.folderPath = joinFolderPath(
                destinationFolderPath,
                package.folderPath
            )
            manifest.updatedAt = Date()
            return (package.packageURL, originalManifest, manifest)
        }

        var writtenUpdates: [(
            packageURL: URL,
            originalManifest: MaterialManifest
        )] = []
        do {
            for update in updates {
                try writeManifest(
                    update.updatedManifest,
                    to: update.packageURL
                )
                writtenUpdates.append((update.packageURL, update.originalManifest))
            }
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
        } catch {
            if fileManager.fileExists(atPath: destinationURL.path),
               !fileManager.fileExists(atPath: sourceURL.path) {
                try? fileManager.moveItem(at: destinationURL, to: sourceURL)
            }
            for update in writtenUpdates.reversed() {
                try? writeManifest(update.originalManifest, to: update.packageURL)
            }
            throw error
        }
    }

    private func writeManifest(
        _ manifest: MaterialManifest,
        to packageURL: URL
    ) throws {
        try encode(manifest).write(
            to: packageURL.appending(path: "manifest.json"),
            options: .atomic
        )
    }

    private func loadManifest(from packageURL: URL) throws -> MaterialManifest {
        do {
            let data = try Data(contentsOf: packageURL.appending(path: "manifest.json"))
            let manifest = try decoder.decode(MaterialManifest.self, from: data)
            guard manifest.schemaVersion == StudyNotesKit.schemaVersion else {
                throw StudyNotesError.unsupportedSchemaVersion(manifest.schemaVersion)
            }
            return manifest
        } catch let error as StudyNotesError {
            throw error
        } catch {
            throw StudyNotesError.malformedMaterialPackage
        }
    }

    private func conflictCopies(
        in directoryURL: URL,
        materialID: UUID
    ) throws -> [ConflictCopy] {
        let packageURLs = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        return packageURLs
            .filter {
                $0.pathExtension == "studyitem"
                    && isConflictCopy($0)
                    && self.materialID(forConflictCopyAt: $0) == materialID
            }
            .map { packageURL in
                let relativePath = packageURL.lastPathComponent
                return ConflictCopy(
                    id: relativePath,
                    displayName: packageURL.deletingPathExtension().lastPathComponent,
                    relativePath: relativePath
                )
            }
            .sorted {
                $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
            }
    }

    private func materialID(forConflictCopyAt packageURL: URL) -> UUID? {
        if let manifest = try? loadManifest(from: packageURL) {
            return manifest.id
        }

        let stem = packageURL.deletingPathExtension().lastPathComponent
        guard let identifier = stem.split(separator: " ").first else {
            return nil
        }
        return UUID(uuidString: String(identifier))
    }

    private func nestedConflictCopies(in packageURL: URL) -> [ConflictCopy] {
        guard let enumerator = fileManager.enumerator(
            at: packageURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let packagePath = packageURL.standardizedFileURL.path
        var conflicts: [ConflictCopy] = []

        for case let candidateURL as URL in enumerator {
            guard isConflictCopy(candidateURL) else {
                continue
            }

            let relativePath = candidateURL.standardizedFileURL.path
                .replacingOccurrences(of: "\(packagePath)/", with: "")
            conflicts.append(
                ConflictCopy(
                    id: relativePath,
                    displayName: candidateURL.deletingPathExtension().lastPathComponent,
                    relativePath: relativePath
                )
            )
            if (try? candidateURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                enumerator.skipDescendants()
            }
        }

        return conflicts.sorted {
            $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
        }
    }

    private func siblingConflictURLs(
        for packageURL: URL,
        materialID: UUID
    ) throws -> [URL] {
        let siblings = try fileManager.contentsOfDirectory(
            at: packageURL.deletingLastPathComponent(),
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return siblings
            .filter {
                $0.pathExtension == "studyitem"
                    && isConflictCopy($0)
                    && self.materialID(forConflictCopyAt: $0) == materialID
            }
            .sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent)
                    == .orderedAscending
            }
    }

    private func rollbackMoves(_ moves: [CompletedPackageMove]) {
        for move in moves.reversed() {
            guard fileManager.fileExists(atPath: move.destinationURL.path),
                  !fileManager.fileExists(atPath: move.sourceURL.path) else {
                continue
            }
            try? fileManager.moveItem(
                at: move.destinationURL,
                to: move.sourceURL
            )
            if let originalManifest = move.originalManifest {
                try? writeManifest(originalManifest, to: move.sourceURL)
            }
        }
    }

    private func isConflictCopy(_ packageURL: URL) -> Bool {
        let name = packageURL.lastPathComponent.lowercased()
        return name.contains("conflicted copy") || name.contains("conflict")
    }

    private func normalizedFolderName(_ name: String) throws -> String {
        guard !name.isEmpty,
              name == name.trimmingCharacters(in: .whitespacesAndNewlines),
              name != ".",
              name != "..",
              !name.contains("/"),
              !name.contains("\\"),
              !name.hasSuffix(".studyitem")
        else {
            throw StudyNotesError.invalidFolderName
        }
        return name
    }

    private func normalizedFolderPath(_ path: String) throws -> String {
        guard path == path.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.contains("\\"),
              !path.hasPrefix("/")
        else {
            throw StudyNotesError.invalidFolderPath
        }
        guard !path.isEmpty else {
            return ""
        }

        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({
            !$0.isEmpty
                && $0 != "."
                && $0 != ".."
                && !$0.hasSuffix(".studyitem")
        }) else {
            throw StudyNotesError.invalidFolderPath
        }
        return components.joined(separator: "/")
    }

    private func normalizedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.compactMap { tag in
            let trimmedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTag.isEmpty, seen.insert(trimmedTag).inserted else {
                return nil
            }
            return trimmedTag
        }
    }

    private func sortedUniqueTags(_ tags: [String]) -> [String] {
        Array(Set(normalizedTags(tags))).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    private func joinFolderPath(_ parentPath: String, _ name: String) -> String {
        parentPath.isEmpty ? name : "\(parentPath)/\(name)"
    }

    private func parentFolderPath(of path: String) -> String {
        path.split(separator: "/").dropLast().joined(separator: "/")
    }

    private func isSameOrDescendantPath(_ candidate: String, of parent: String) -> Bool {
        candidate == parent || candidate.hasPrefix("\(parent)/")
    }

    private func unique(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return ids.filter { seen.insert($0).inserted }
    }

    private func sortedMaterials(
        _ materials: [StudyMaterialSummary]
    ) -> [StudyMaterialSummary] {
        materials.sorted {
            if $0.updatedAt == $1.updatedAt {
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            return $0.updatedAt > $1.updatedAt
        }
    }

    private func sortedRecycledMaterials(
        _ materials: [StudyMaterialSummary]
    ) -> [StudyMaterialSummary] {
        materials.sorted {
            let leftDeletedAt = $0.deletedAt ?? .distantPast
            let rightDeletedAt = $1.deletedAt ?? .distantPast
            if leftDeletedAt == rightDeletedAt {
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            return leftDeletedAt > rightDeletedAt
        }
    }

    private func folderSort(_ left: KnowledgeFolder, _ right: KnowledgeFolder) -> Bool {
        if left.knowledgeBaseID != right.knowledgeBaseID {
            return left.knowledgeBaseID.uuidString < right.knowledgeBaseID.uuidString
        }
        return left.path.localizedStandardCompare(right.path) == .orderedAscending
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private struct MaterialManifest: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let id: UUID
    var knowledgeBaseID: UUID?
    let kind: StudyMaterialKind
    let title: String
    let createdAt: Date
    var updatedAt: Date
    var folderPath: String
    var tags: [String]
    var deletedAt: Date?
    var originalLocation: MaterialOriginalLocation?

    init(
        schemaVersion: Int,
        id: UUID,
        knowledgeBaseID: UUID?,
        kind: StudyMaterialKind,
        title: String,
        createdAt: Date,
        updatedAt: Date,
        folderPath: String,
        tags: [String],
        deletedAt: Date?,
        originalLocation: MaterialOriginalLocation?
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.knowledgeBaseID = knowledgeBaseID
        self.kind = kind
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.folderPath = folderPath
        self.tags = tags
        self.deletedAt = deletedAt
        self.originalLocation = originalLocation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        id = try container.decode(UUID.self, forKey: .id)
        knowledgeBaseID = try container.decodeIfPresent(UUID.self, forKey: .knowledgeBaseID)
        kind = try container.decode(StudyMaterialKind.self, forKey: .kind)
        title = try container.decode(String.self, forKey: .title)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        folderPath = try container.decodeIfPresent(String.self, forKey: .folderPath) ?? ""
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        originalLocation = try container.decodeIfPresent(
            MaterialOriginalLocation.self,
            forKey: .originalLocation
        )
    }

    func summary(
        knowledgeBaseID: UUID?,
        folderPath: String,
        conflictCopies: [ConflictCopy]
    ) -> StudyMaterialSummary {
        StudyMaterialSummary(
            id: id,
            knowledgeBaseID: knowledgeBaseID,
            kind: kind,
            title: title,
            updatedAt: updatedAt,
            conflictCopies: conflictCopies,
            folderPath: folderPath,
            tags: tags,
            deletedAt: deletedAt
        )
    }
}

private struct MaterialOriginalLocation: Codable, Equatable, Sendable {
    let knowledgeBaseID: UUID?
    let folderPath: String
}

private struct ScannedPackage {
    let packageURL: URL
    let folderPath: String
    let manifest: MaterialManifest?
}

private struct CompletedPackageMove {
    let sourceURL: URL
    let destinationURL: URL
    let originalManifest: MaterialManifest?
}

private struct ContainerScan {
    let packages: [ScannedPackage]
    let folders: [KnowledgeFolder]
}

private enum MaterialPlacement {
    case knowledgeBase(UUID)
    case inbox
    case recycleBin

    var isRecycleBin: Bool {
        if case .recycleBin = self {
            return true
        }
        return false
    }
}

private struct LocatedMaterial {
    let package: ScannedPackage
    var manifest: MaterialManifest
    let placement: MaterialPlacement

    var packageURL: URL {
        package.packageURL
    }
}
