import Foundation
import ImageIO
import PDFKit

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
    case materialNotPublishable
    case annotationNotFound
    case conversationNotFound
    case revisionNotFound
    case invalidLinkedMaterial
    case editorDocumentLocked
    case editorDocumentConflict(expected: String, current: String)
    case editorDocumentTransactionInvalid(String)
    case editorDocumentBlockInvalid(blockID: UUID, reason: String)
    case editorDocumentBlockMissing(blockID: UUID)
    case editorDocumentBlockVersionUnsupported(blockID: UUID, version: Int)
    case editorDocumentBlockMarkerMissing(blockID: UUID)
    case editorDocumentMarkersInvalid(reason: String)
    case editorDocumentHasPendingTransaction

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
        case .materialNotPublishable:
            "只有 Markdown、HTML 或网页文章可以进入发布预览。"
        case .annotationNotFound:
            "没有找到对应的标注。"
        case .conversationNotFound:
            "没有找到对应的 AI 研读会话。"
        case .revisionNotFound:
            "没有找到对应的文字版本。"
        case .invalidLinkedMaterial:
            "关联材料不存在，或不能关联自身。"
        case .editorDocumentLocked:
            "文档已完成编辑并锁定，不能修改正文。"
        case let .editorDocumentConflict(expected, current):
            "文档已在其他位置被修改。编辑基线 \(expected)，当前指纹 \(current)。"
        case let .editorDocumentTransactionInvalid(reason):
            "文档恢复事务无效：\(reason)"
        case let .editorDocumentBlockInvalid(blockID, reason):
            "旁路块 \(blockID.uuidString) 无效：\(reason)"
        case let .editorDocumentBlockMissing(blockID):
            "旁路块 \(blockID.uuidString) 缺失。"
        case let .editorDocumentBlockVersionUnsupported(blockID, version):
            "旁路块 \(blockID.uuidString) 使用了不支持的版本 \(version)。"
        case let .editorDocumentBlockMarkerMissing(blockID):
            "旁路块 \(blockID.uuidString) 没有对应的 Markdown 标记。"
        case let .editorDocumentMarkersInvalid(reason):
            "Markdown 旁路块标记无效：\(reason)"
        case .editorDocumentHasPendingTransaction:
            "文档仍有未提交事务，不能锁定。"
        }
    }
}

public actor StudyNotesStore {
    private static let recycleRetentionInterval: TimeInterval = 30 * 24 * 60 * 60

    private let rootProvider: any StudyNotesRootProviding
    private let fileManager: FileManager
    private let explicitDerivedDataURL: URL?
    private let fileCoordinator = NSFileCoordinator(filePresenter: nil)
    private var searchIndex: StudyNotesSearchIndex?

    public init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootProvider = FixedStudyNotesRootProvider(status: .available(.local(rootURL)))
        self.fileManager = fileManager
        self.explicitDerivedDataURL = nil
    }

    public init(
        rootProvider: any StudyNotesRootProviding,
        fileManager: FileManager = .default,
        derivedDataURL: URL? = nil
    ) {
        self.rootProvider = rootProvider
        self.fileManager = fileManager
        self.explicitDerivedDataURL = derivedDataURL
    }

    public init(
        rootURL: URL,
        derivedDataURL: URL,
        fileManager: FileManager = .default
    ) {
        self.rootProvider = FixedStudyNotesRootProvider(status: .available(.local(rootURL)))
        self.fileManager = fileManager
        self.explicitDerivedDataURL = derivedDataURL
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
            let inboxDraftMaterials = try scanInboxDrafts(
                in: inboxURL(at: rootURL)
            ).map(inboxDraftSummary)

            let recycleBinScan = try scanMaterialPackages(
                in: recycleBinURL(at: rootURL),
                knowledgeBaseID: nil
            )
            let recycledMaterials = try summaries(
                from: recycleBinScan.packages,
                placement: .recycleBin
            )

            let tags = sortedUniqueTags(
                (materials + inboxMaterials + inboxDraftMaterials).flatMap(\.tags)
            )

            return LibraryIndex(
                knowledgeBases: knowledgeBases,
                materials: sortedMaterials(materials),
                folders: folders.sorted(by: folderSort),
                inboxMaterials: sortedMaterials(inboxMaterials + inboxDraftMaterials),
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
            let content = try loadEditorDocumentContent(for: locatedMaterial)

            return MarkdownNote(
                summary: try summary(for: locatedMaterial),
                markdown: content.markdown
            )
        }
    }

    public func loadMaterialDocument(id: UUID) throws -> MaterialDocument {
        let rootURL = try availableRootURL()
        try prepareRootDirectories(at: rootURL)

        return try coordinatedRead(at: rootURL) {
            if let draft = try locateInboxDraft(id: id, rootURL: rootURL) {
                return try loadInboxDraftDocument(draft)
            }
            guard let located = try locateMaterial(
                id: id,
                rootURL: rootURL,
                includeRecycled: true
            ) else {
                throw StudyNotesError.materialNotFound
            }
            let packageURL = located.packageURL
            let manifest = located.manifest
            let editorContent: EditorDocumentContent?
            if manifest.kind.isTextDocument {
                editorContent = try loadEditorDocumentContent(for: located)
            } else {
                editorContent = nil
            }
            let markdown = editorContent?.markdown ?? ""
            let mediaURLs = mediaFileURLs(in: packageURL)
            let content = ReaderContentBuilder.build(
                markdown: markdown,
                title: manifest.title,
                mediaURLs: mediaURLs
            )
            let sourceFileURL = manifest.sourceFileName.map {
                packageURL
                    .appending(path: "source", directoryHint: .isDirectory)
                    .appending(path: $0)
            }
            let pdfDocument: PDFDocument?
            if manifest.kind == .pdf,
               let sourceFileURL,
               let data = try? Data(contentsOf: sourceFileURL) {
                pdfDocument = PDFDocument(data: data)
            } else {
                pdfDocument = nil
            }
            if manifest.kind == .pdf, pdfDocument == nil {
                throw StudyNotesContentError.invalidPDF
            }
            let hasTextLayer = pdfDocument.map { document in
                (0..<document.pageCount).contains {
                    !(document.page(at: $0)?.string ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty
                }
            }
            return MaterialDocument(
                summary: try summary(for: located),
                markdown: markdown,
                renderedHTML: content.html,
                headings: content.headings,
                sourceURL: packageURL,
                sourceFileURL: sourceFileURL,
                mediaURLs: mediaURLs,
                pageCount: pdfDocument?.pageCount,
                hasTextLayer: hasTextLayer,
                isLocked: manifest.isLocked,
                currentGenerationID: editorContent?.generationID,
                contentFingerprint: editorContent?.fingerprint,
                blocks: editorContent?.blocks ?? [],
                derivedRebuildPending: manifest.derivedRebuildPending
            )
        }
    }

    public func loadEditorDocument(id: UUID) throws -> EditorDocumentState {
        let rootURL = try availableRootURL()
        try prepareRootDirectories(at: rootURL)

        return try coordinatedRead(at: rootURL) {
            guard let located = try locateMaterial(
                id: id,
                rootURL: rootURL,
                includeRecycled: true
            ), located.manifest.kind.isTextDocument else {
                throw StudyNotesError.materialNotFound
            }
            return try editorDocumentState(for: located)
        }
    }

    public func saveEditorDocument(
        _ request: EditorDocumentSaveRequest
    ) throws -> EditorDocumentState {
        let rootURL = try availableRootURL()
        try prepareRootDirectories(at: rootURL)

        return try coordinatedWrite(at: rootURL) {
            guard let located = try locateMaterial(
                id: request.materialID,
                rootURL: rootURL,
                includeRecycled: false
            ), located.manifest.kind.isTextDocument else {
                throw StudyNotesError.materialNotFound
            }
            return try commitEditorDocument(
                located,
                request: request,
                createUserVisibleRevision: false,
                ensureRevisionExists: false
            ).state
        }
    }

    public func loadPendingEditorDocumentTransaction(
        id: UUID
    ) throws -> EditorDocumentTransaction? {
        let rootURL = try availableRootURL()
        try prepareRootDirectories(at: rootURL)

        return try coordinatedRead(at: rootURL) {
            guard let located = try locateMaterial(
                id: id,
                rootURL: rootURL,
                includeRecycled: true
            ) else {
                throw StudyNotesError.materialNotFound
            }
            return try pendingEditorDocumentTransaction(
                packageURL: located.packageURL,
                materialID: id,
                committedGenerationID: located.manifest.currentGenerationID
            )
        }
    }

    public func setEditorDocumentLocked(
        id: UUID,
        isLocked: Bool
    ) throws -> EditorDocumentState {
        let rootURL = try availableRootURL()
        try prepareRootDirectories(at: rootURL)

        return try coordinatedWrite(at: rootURL) {
            guard var located = try locateMaterial(
                id: id,
                rootURL: rootURL,
                includeRecycled: false
            ), located.manifest.kind.isTextDocument else {
                throw StudyNotesError.materialNotFound
            }
            if isLocked {
                if try pendingEditorDocumentTransaction(
                    packageURL: located.packageURL,
                    materialID: id,
                    committedGenerationID: located.manifest.currentGenerationID
                ) != nil {
                    throw StudyNotesError.editorDocumentHasPendingTransaction
                }
                _ = try editorDocumentState(for: located)
            }
            located.manifest.isLocked = isLocked
            located.manifest.updatedAt = Date()
            try writeManifest(located.manifest, to: located.packageURL)
            return try editorDocumentState(for: located)
        }
    }

    public func retryEditorDocumentDerivedRebuild(
        id: UUID
    ) throws -> EditorDocumentState {
        let rootURL = try availableRootURL()
        try prepareRootDirectories(at: rootURL)

        return try coordinatedWrite(at: rootURL) {
            guard var located = try locateMaterial(
                id: id,
                rootURL: rootURL,
                includeRecycled: false
            ), located.manifest.kind.isTextDocument else {
                throw StudyNotesError.materialNotFound
            }
            let content = try loadEditorDocumentContent(for: located)
            do {
                try refreshAnnotationStatuses(
                    packageURL: located.packageURL,
                    materialID: id,
                    text: content.markdown,
                    kind: located.manifest.kind
                )
            } catch {
                located.manifest.derivedRebuildPending = true
                located.manifest.updatedAt = Date()
                try? writeManifest(located.manifest, to: located.packageURL)
                throw error
            }
            located.manifest.derivedRebuildPending = false
            try writeManifest(located.manifest, to: located.packageURL)
            return try editorDocumentState(for: located)
        }
    }

    @discardableResult
    public func exportEditorDocumentMarkdown(
        id: UUID,
        to destinationURL: URL
    ) throws -> URL {
        let rootURL = try availableRootURL()
        try prepareRootDirectories(at: rootURL)

        return try coordinatedRead(at: rootURL) {
            guard let located = try locateMaterial(
                id: id,
                rootURL: rootURL,
                includeRecycled: false
            ), located.manifest.kind.isTextDocument else {
                throw StudyNotesError.materialNotFound
            }
            let content = try loadEditorDocumentContent(for: located)
            let blocks = content.blocks.compactMap { $0.editorBlock() }
            return try EditorExportService().writeReadableMarkdown(
                markdown: content.markdown,
                blocks: blocks,
                destinationURL: destinationURL
            )
        }
    }

    @discardableResult
    public func exportEditorDocumentPackage(
        id: UUID,
        to destinationURL: URL
    ) throws -> URL {
        let rootURL = try availableRootURL()
        try prepareRootDirectories(at: rootURL)

        return try coordinatedRead(at: rootURL) {
            guard let located = try locateMaterial(
                id: id,
                rootURL: rootURL,
                includeRecycled: false
            ), located.manifest.kind.isTextDocument else {
                throw StudyNotesError.materialNotFound
            }
            let content = try loadEditorDocumentContent(for: located)
            let blocks = content.blocks.compactMap { $0.editorBlock() }
            let parent = destinationURL.deletingLastPathComponent()
            let temporary = parent.appending(
                path: ".package-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
            try fileManager.createDirectory(
                at: parent,
                withIntermediateDirectories: true
            )
            do {
                try fileManager.copyItem(
                    at: located.packageURL,
                    to: temporary
                )
                let transactionDirectory = temporary
                    .appending(path: "content", directoryHint: .isDirectory)
                    .appending(
                        path: "transactions",
                        directoryHint: .isDirectory
                    )
                try? fileManager.removeItem(at: transactionDirectory)
                let readable = try EditorMarkdownFallback()
                    .readableMarkdown(
                        content.markdown,
                        blocks: blocks
                    )
                try Data(readable.utf8).write(
                    to: temporary.appending(path: "readable.md"),
                    options: .atomic
                )
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                try fileManager.moveItem(at: temporary, to: destinationURL)
                return destinationURL
            } catch {
                try? fileManager.removeItem(at: temporary)
                throw error
            }
        }
    }

    public func importFiles(
        at fileURLs: [URL],
        knowledgeBaseID: UUID?,
        folderPath: String = "",
        tags: [String] = []
    ) throws -> MaterialImportBatch {
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

            var results: [MaterialImportResult] = []
            for fileURL in fileURLs {
                let data = try Data(contentsOf: fileURL)
                let fileExtension = fileURL.pathExtension.lowercased()
                let request = try importRequest(
                    data: data,
                    fileExtension: fileExtension,
                    fallbackTitle: fileURL.deletingPathExtension().lastPathComponent
                )
                let fingerprint = ContentFingerprint.sha256(data)
                if let duplicate = try findDuplicate(
                    fingerprint: fingerprint,
                    rootURL: rootURL
                ) {
                    results.append(
                        MaterialImportResult(
                            summary: duplicate,
                            isDuplicate: true,
                            duplicateOf: duplicate.id
                        )
                    )
                    continue
                }

                let imported = try createImportedPackage(
                    request: request,
                    sourceData: data,
                    sourceFileName: "original.\(fileExtension)",
                    fingerprint: fingerprint,
                    knowledgeBaseID: knowledgeBaseID,
                    folderPath: normalizedFolderPath,
                    tags: tags,
                    rootURL: rootURL
                )
                results.append(
                    MaterialImportResult(
                        summary: imported,
                        isDuplicate: false,
                        duplicateOf: nil
                    )
                )
            }
            return MaterialImportBatch(results: results)
        }
    }

    public func importWebArticle(
        _ draft: WebArticleDraft,
        title: String,
        markdown: String,
        knowledgeBaseID: UUID?,
        folderPath: String = "",
        tags: [String] = []
    ) throws -> MaterialImportResult {
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

            let sourceData = Data(draft.rawHTML.utf8)
            let fingerprint = ContentFingerprint.sha256(sourceData)
            if let duplicate = try findDuplicate(
                fingerprint: fingerprint,
                rootURL: rootURL
            ) {
                return MaterialImportResult(
                    summary: duplicate,
                    isDuplicate: true,
                    duplicateOf: duplicate.id
                )
            }
            let normalizedMarkdown = localizeWebMediaReferences(
                markdown,
                media: draft.media
            )
            let request = ImportRequest(
                kind: .webArticle,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? draft.title
                    : title,
                markdown: normalizedMarkdown,
                originalSourceURL: draft.sourceURL,
                media: draft.media,
                mediaFailures: draft.mediaFailures
            )
            let summary = try createImportedPackage(
                request: request,
                sourceData: sourceData,
                sourceFileName: "article.html",
                fingerprint: fingerprint,
                knowledgeBaseID: knowledgeBaseID,
                folderPath: normalizedFolderPath,
                tags: tags,
                rootURL: rootURL
            )
            return MaterialImportResult(
                summary: summary,
                isDuplicate: false,
                duplicateOf: nil,
                mediaFailures: draft.mediaFailures.map(\.sourceURL.absoluteString)
            )
        }
    }

    @discardableResult
    public func saveReaderCopy(id: UUID, text: String) throws -> TextRevision {
        try saveReaderCopy(
            id: id,
            text: text,
            title: nil,
            createRecoveryVersion: true
        )
    }

    @discardableResult
    public func saveReaderCopy(
        id: UUID,
        text: String,
        title: String?,
        createRecoveryVersion: Bool
    ) throws -> TextRevision {
        let rootURL = try availableRootURL()
        try prepareRootDirectories(at: rootURL)

        return try coordinatedWrite(at: rootURL) {
            guard let located = try locateMaterial(
                id: id,
                rootURL: rootURL,
                includeRecycled: false
            ), located.manifest.kind.isTextDocument else {
                throw StudyNotesError.materialNotFound
            }
            let content = try loadEditorDocumentContent(for: located)
            let normalizedTitle = title?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedTitle: String
            if let normalizedTitle, !normalizedTitle.isEmpty {
                resolvedTitle = normalizedTitle
            } else {
                resolvedTitle = located.manifest.title
            }
            let request = EditorDocumentSaveRequest(
                materialID: id,
                title: resolvedTitle,
                markdown: text,
                blocks: content.blocks,
                expectedContentFingerprint: content.fingerprint
            )
            let result = try commitEditorDocument(
                located,
                request: request,
                createUserVisibleRevision: createRecoveryVersion,
                ensureRevisionExists: true
            )
            guard let revision = result.revision else {
                throw StudyNotesError.revisionNotFound
            }
            return revision
        }
    }

    public func loadTextRevisions(id: UUID) throws -> [TextRevision] {
        let rootURL = try availableRootURL()
        try prepareRootDirectories(at: rootURL)

        return try coordinatedRead(at: rootURL) {
            guard let located = try locateMaterial(
                id: id,
                rootURL: rootURL,
                includeRecycled: true
            ) else {
                throw StudyNotesError.materialNotFound
            }
            return try revisions(
                packageURL: located.packageURL,
                materialID: id
            )
        }
    }

    @discardableResult
    public func restoreRevision(id: UUID, revisionID: UUID) throws -> TextRevision {
        let rootURL = try availableRootURL()
        try prepareRootDirectories(at: rootURL)

        return try coordinatedWrite(at: rootURL) {
            guard let located = try locateMaterial(
                id: id,
                rootURL: rootURL,
                includeRecycled: false
            ) else {
                throw StudyNotesError.materialNotFound
            }
            guard let revision = try revisions(
                packageURL: located.packageURL,
                materialID: id
            ).first(where: { $0.id == revisionID }),
            let contentURL = contentFileURL(
                kind: located.manifest.kind,
                packageURL: located.packageURL
            ) else {
                throw StudyNotesError.revisionNotFound
            }
            try Data(revision.text.utf8).write(to: contentURL, options: .atomic)
            let restoredRevision = try appendRevision(
                text: revision.text,
                packageURL: located.packageURL,
                materialID: id
            )
            var manifest = located.manifest
            manifest.contentVersionID = restoredRevision.id
            let oldGenerationID = manifest.currentGenerationID
            manifest.currentGenerationID = nil
            manifest.updatedAt = restoredRevision.createdAt
            manifest.contentFingerprint = ContentFingerprint.sha256(revision.text)
            try writeManifest(manifest, to: located.packageURL)
            if let oldGenerationID {
                try? fileManager.removeItem(
                    at: editorGenerationURL(
                        generationID: oldGenerationID,
                        packageURL: located.packageURL
                    )
                )
            }
            try refreshAnnotationStatuses(
                packageURL: located.packageURL,
                materialID: id,
                text: revision.text,
                kind: manifest.kind
            )
            return restoredRevision
        }
    }

    @discardableResult
    public func setLinkedMaterials(
        for materialID: UUID,
        linkedMaterialIDs: [UUID]
    ) throws -> StudyMaterialSummary {
        let rootURL = try availableRootURL()
        try prepareRootDirectories(at: rootURL)

        return try coordinatedWrite(at: rootURL) {
            guard let located = try locateMaterial(
                id: materialID,
                rootURL: rootURL,
                includeRecycled: false
            ) else {
                throw StudyNotesError.materialNotFound
            }
            let uniqueIDs = unique(linkedMaterialIDs).filter { $0 != materialID }
            for linkedID in uniqueIDs {
                guard try locateMaterial(
                    id: linkedID,
                    rootURL: rootURL,
                    includeRecycled: false
                ) != nil else {
                    throw StudyNotesError.invalidLinkedMaterial
                }
            }
            var manifest = located.manifest
            manifest.linkedMaterialIDs = uniqueIDs
            manifest.updatedAt = Date()
            try writeManifest(manifest, to: located.packageURL)
            var updated = located
            updated.manifest = manifest
            return try summary(for: updated)
        }
    }

    public func loadAnnotations(materialID: UUID) throws -> [MaterialAnnotation] {
        let rootURL = try availableRootURL()
        try prepareRootDirectories(at: rootURL)

        return try coordinatedRead(at: rootURL) {
            if try locateInboxDraft(id: materialID, rootURL: rootURL) != nil {
                return []
            }
            guard let located = try locateMaterial(
                id: materialID,
                rootURL: rootURL,
                includeRecycled: true
            ) else {
                throw StudyNotesError.materialNotFound
            }
            let annotations = try loadAnnotationFiles(
                packageURL: located.packageURL,
                materialID: materialID
            )
            let text = try readerText(
                packageURL: located.packageURL,
                manifest: located.manifest
            )
            return annotations.map { annotation in
                var resolved = annotation
                resolved.status = resolvedAnnotationStatus(
                    annotation,
                    text: text,
                    packageURL: located.packageURL,
                    kind: located.manifest.kind
                )
                return resolved
            }
        }
    }

    public func upsertAnnotation(
        _ annotation: MaterialAnnotation
    ) throws -> MaterialAnnotation {
        let rootURL = try availableRootURL()
        try prepareRootDirectories(at: rootURL)

        return try coordinatedWrite(at: rootURL) {
            guard let located = try locateMaterial(
                id: annotation.materialID,
                rootURL: rootURL,
                includeRecycled: false
            ) else {
                throw StudyNotesError.materialNotFound
            }
            var annotations = try loadAnnotationFiles(
                packageURL: located.packageURL,
                materialID: annotation.materialID
            )
            var value = annotation
            if let existingIndex = annotations.firstIndex(where: {
                sameAnchorLocation($0.anchor, annotation.anchor)
            }) {
                let existing = annotations[existingIndex]
                value = MaterialAnnotation(
                    id: existing.id,
                    materialID: existing.materialID,
                    anchor: annotation.anchor,
                    quote: annotation.quote,
                    note: annotation.note,
                    status: .active,
                    createdAt: existing.createdAt,
                    updatedAt: Date()
                )
                annotations[existingIndex] = value
            } else {
                annotations.append(value)
            }
            try writeAnnotation(value, packageURL: located.packageURL)
            return value
        }
    }

    public func rebindAnnotation(
        id annotationID: UUID,
        materialID: UUID,
        anchor: AnnotationAnchor
    ) throws -> MaterialAnnotation {
        let rootURL = try availableRootURL()
        try prepareRootDirectories(at: rootURL)
        return try coordinatedWrite(at: rootURL) {
            guard let located = try locateMaterial(
                id: materialID,
                rootURL: rootURL,
                includeRecycled: false
            ) else {
                throw StudyNotesError.materialNotFound
            }
            var annotations = try loadAnnotationFiles(
                packageURL: located.packageURL,
                materialID: materialID
            )
            guard let index = annotations.firstIndex(where: { $0.id == annotationID }) else {
                throw StudyNotesError.annotationNotFound
            }
            annotations[index].anchor = anchor
            annotations[index].status = .active
            annotations[index].updatedAt = Date()
            try writeAnnotation(annotations[index], packageURL: located.packageURL)
            return annotations[index]
        }
    }

    public func deleteAnnotation(id: UUID, materialID: UUID) throws {
        let rootURL = try availableRootURL()
        try prepareRootDirectories(at: rootURL)
        try coordinatedWrite(at: rootURL) {
            guard let located = try locateMaterial(
                id: materialID,
                rootURL: rootURL,
                includeRecycled: false
            ) else {
                throw StudyNotesError.materialNotFound
            }
            let fileURL = located.packageURL
                .appending(path: "annotations", directoryHint: .isDirectory)
                .appending(path: "\(id.uuidString).json")
            guard fileManager.fileExists(atPath: fileURL.path) else {
                throw StudyNotesError.annotationNotFound
            }
            try fileManager.removeItem(at: fileURL)
        }
    }

    public func loadConversations(materialID: UUID) throws -> [AIConversation] {
        let rootURL = try availableRootURL()
        try prepareRootDirectories(at: rootURL)
        return try coordinatedRead(at: rootURL) {
            if try locateInboxDraft(id: materialID, rootURL: rootURL) != nil {
                return []
            }
            guard let located = try locateMaterial(
                id: materialID,
                rootURL: rootURL,
                includeRecycled: true
            ) else {
                throw StudyNotesError.materialNotFound
            }
            return try conversationFiles(packageURL: located.packageURL)
        }
    }

    @discardableResult
    public func saveConversation(_ conversation: AIConversation) throws -> AIConversation {
        let rootURL = try availableRootURL()
        try prepareRootDirectories(at: rootURL)
        return try coordinatedWrite(at: rootURL) {
            guard let located = try locateMaterial(
                id: conversation.materialID,
                rootURL: rootURL,
                includeRecycled: false
            ) else {
                throw StudyNotesError.materialNotFound
            }
            let directory = located.packageURL
                .appending(path: "ai", directoryHint: .isDirectory)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            var value = conversation
            value.updatedAt = Date()
            try encode(value).write(
                to: directory.appending(path: "\(value.id.uuidString).json"),
                options: .atomic
            )
            return value
        }
    }

    public func deleteConversation(id: UUID, materialID: UUID) throws {
        let rootURL = try availableRootURL()
        try prepareRootDirectories(at: rootURL)
        try coordinatedWrite(at: rootURL) {
            guard let located = try locateMaterial(
                id: materialID,
                rootURL: rootURL,
                includeRecycled: false
            ) else {
                throw StudyNotesError.materialNotFound
            }
            let fileURL = located.packageURL
                .appending(path: "ai", directoryHint: .isDirectory)
                .appending(path: "\(id.uuidString).json")
            guard fileManager.fileExists(atPath: fileURL.path) else {
                throw StudyNotesError.conversationNotFound
            }
            try fileManager.removeItem(at: fileURL)
        }
    }

    public func promoteAIResult(
        conversationID: UUID,
        messageID: UUID,
        materialID: UUID,
        target: AIPromotionTarget,
        knowledgeBaseID: UUID?,
        folderPath: String = ""
    ) throws -> AIPromotionResult {
        let rootURL = try availableRootURL()
        try prepareRootDirectories(at: rootURL)
        return try coordinatedWrite(at: rootURL) {
            guard let located = try locateMaterial(
                id: materialID,
                rootURL: rootURL,
                includeRecycled: false
            ) else {
                throw StudyNotesError.materialNotFound
            }
            guard let conversation = try conversationFiles(
                packageURL: located.packageURL
            ).first(where: { $0.id == conversationID }) else {
                throw StudyNotesError.conversationNotFound
            }
            guard let message = conversation.messages.first(where: { $0.id == messageID }) else {
                throw StudyNotesError.conversationNotFound
            }
            let title = conversation.title.isEmpty
                ? "AI 研读结果"
                : conversation.title
            switch target {
            case .note, .material:
                let note = try createMarkdownPackage(
                    title: title,
                    markdown: message.content,
                    knowledgeBaseID: knowledgeBaseID,
                    folderPath: folderPath,
                    tags: ["AI 研读"],
                    rootURL: rootURL
                )
                return AIPromotionResult(
                    target: target,
                    material: note.summary,
                    annotation: nil
                )
            case .annotation:
                guard let anchor = conversation.originAnchor else {
                    throw StudyNotesError.annotationNotFound
                }
                var annotations = try loadAnnotationFiles(
                    packageURL: located.packageURL,
                    materialID: materialID
                )
                let annotation: MaterialAnnotation
                if let existingIndex = annotations.firstIndex(where: {
                    sameAnchorLocation($0.anchor, anchor)
                }) {
                    let existing = annotations[existingIndex]
                    annotation = MaterialAnnotation(
                        id: existing.id,
                        materialID: materialID,
                        anchor: anchor,
                        quote: anchor.excerpt,
                        note: message.content,
                        status: .active,
                        createdAt: existing.createdAt,
                        updatedAt: Date()
                    )
                    annotations[existingIndex] = annotation
                } else {
                    annotation = MaterialAnnotation(
                        materialID: materialID,
                        anchor: anchor,
                        quote: anchor.excerpt,
                        note: message.content
                    )
                }
                try writeAnnotation(annotation, packageURL: located.packageURL)
                return AIPromotionResult(
                    target: target,
                    material: located.manifest.summary(
                        knowledgeBaseID: located.manifest.knowledgeBaseID,
                        folderPath: located.package.folderPath,
                        conflictCopies: []
                    ),
                    annotation: annotation
                )
            }
        }
    }

    public func search(
        _ query: String,
        filter: SearchFilter = SearchFilter()
    ) async throws -> [SearchHit] {
        let rootURL = try availableRootURL()
        try prepareRootDirectories(at: rootURL)
        let documents = try searchableDocuments(rootURL: rootURL)
        let index = try ensureSearchIndex(rootURL: rootURL)
        return try await index.search(
            query: query,
            filter: filter,
            documents: documents
        )
    }

    public func publishPreview(
        materialID: UUID,
        includeAnnotations: Bool = false,
        includeAI: Bool = false
    ) throws -> PublishPreview {
        let document = try loadMaterialDocument(id: materialID)
        guard document.summary.kind.canPublish else {
            throw StudyNotesError.materialNotPublishable
        }
        let annotations = includeAnnotations
            ? try loadAnnotations(materialID: materialID)
                .filter { $0.status == .active }
                .map {
                    PublishedAnnotation(
                        id: $0.id,
                        quote: $0.quote,
                        note: $0.note,
                        anchor: $0.anchor
                    )
                }
            : []
        let conversations = try loadConversations(materialID: materialID)
        let appendix = includeAI
            ? conversations.flatMap { conversation in
                conversation.messages.compactMap { message in
                    message.role == .assistant
                        ? "### \(conversation.title)\n\n\(message.content)"
                        : nil
                }
            }.joined(separator: "\n\n")
            : ""
        let html = ReaderContentBuilder.publicationHTML(
            title: document.summary.title,
            markdown: document.markdown,
            annotations: annotations,
            aiAppendix: appendix.isEmpty ? nil : appendix
        )
        let fingerprint = ContentFingerprint.sha256(
            [
                html,
                includeAnnotations ? "annotations" : "",
                includeAI ? "ai" : ""
            ].joined(separator: "\n")
        )
        let media = try publishMediaItems(packageURL: document.sourceURL)
        return PublishPreview(
            materialID: materialID,
            title: document.summary.title,
            html: html,
            contentFingerprint: fingerprint,
            includeAnnotations: includeAnnotations,
            includeAI: includeAI,
            annotations: annotations,
            aiAppendix: appendix.isEmpty ? nil : appendix,
            media: media,
            mapping: document.summary.publishMapping
        )
    }

    public func savePublishMapping(
        materialID: UUID,
        mapping: PublishMapping
    ) throws -> StudyMaterialSummary {
        let rootURL = try availableRootURL()
        try prepareRootDirectories(at: rootURL)
        return try coordinatedWrite(at: rootURL) {
            guard let located = try locateMaterial(
                id: materialID,
                rootURL: rootURL,
                includeRecycled: false
            ) else {
                throw StudyNotesError.materialNotFound
            }
            guard located.manifest.kind.canPublish else {
                throw StudyNotesError.materialNotPublishable
            }
            var manifest = located.manifest
            manifest.publishMapping = mapping
            manifest.updatedAt = Date()
            try writeManifest(manifest, to: located.packageURL)
            var updated = located
            updated.manifest = manifest
            return try summary(for: updated)
        }
    }

    @discardableResult
    public func clearPublishMapping(
        materialID: UUID
    ) throws -> StudyMaterialSummary {
        let rootURL = try availableRootURL()
        try prepareRootDirectories(at: rootURL)
        return try coordinatedWrite(at: rootURL) {
            guard let located = try locateMaterial(
                id: materialID,
                rootURL: rootURL,
                includeRecycled: false
            ) else {
                throw StudyNotesError.materialNotFound
            }
            var manifest = located.manifest
            manifest.publishMapping = nil
            manifest.updatedAt = Date()
            try writeManifest(manifest, to: located.packageURL)
            var updated = located
            updated.manifest = manifest
            return try summary(for: updated)
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
            var draftPlans: [(
                draft: InboxDraftPackage,
                destinationURL: URL,
                manifest: MaterialManifest
            )] = []
            let destinationDirectory = try destinationDirectory(
                knowledgeBaseID: knowledgeBaseID,
                folderPath: normalizedFolderPath,
                rootURL: rootURL
            )

            for id in uniqueIDs {
                if let draft = try locateInboxDraft(id: id, rootURL: rootURL) {
                    let destinationURL = destinationDirectory.appending(
                        path: "\(id.uuidString).studyitem",
                        directoryHint: .isDirectory
                    )
                    guard !fileManager.fileExists(atPath: destinationURL.path) else {
                        throw StudyNotesError.materialAlreadyExists
                    }
                    let manifest = try inboxDraftMaterialManifest(
                        draft,
                        knowledgeBaseID: knowledgeBaseID,
                        folderPath: normalizedFolderPath
                    )
                    draftPlans.append((draft, destinationURL, manifest))
                    continue
                }
                guard let located = try locateMaterial(
                    id: id,
                    rootURL: rootURL,
                    includeRecycled: false
                ) else {
                    throw StudyNotesError.materialNotFound
                }

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
            var materializedDraftDestinations: [URL] = []
            var materializedDraftSources: [URL] = []
            do {
                for plan in draftPlans {
                    try materializeInboxDraft(
                        plan.draft,
                        destinationURL: plan.destinationURL,
                        manifest: plan.manifest
                    )
                    materializedDraftDestinations.append(plan.destinationURL)
                    materializedDraftSources.append(plan.draft.packageURL)
                }
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
                for destinationURL in materializedDraftDestinations {
                    try? fileManager.removeItem(at: destinationURL)
                }
                throw error
            }
            for sourceURL in materializedDraftSources {
                try? fileManager.removeItem(at: sourceURL)
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
        let revisionID = UUID()
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
            originalLocation: nil,
            sourceFileName: "original.md",
            contentVersionID: revisionID,
            sourceFingerprint: ContentFingerprint.sha256(markdown),
            contentFingerprint: ContentFingerprint.sha256(markdown)
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
        let sourceURL = temporaryURL
            .appending(path: "source", directoryHint: .isDirectory)
            .appending(path: "original.md")
        let revisionURL = temporaryURL
            .appending(path: "revisions", directoryHint: .isDirectory)
            .appending(path: "\(revisionID.uuidString).md")

        for directory in [
            contentURL.deletingLastPathComponent(),
            sourceURL.deletingLastPathComponent(),
            revisionURL.deletingLastPathComponent()
        ] {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        do {
            try encode(manifest).write(
                to: temporaryURL.appending(path: "manifest.json"),
                options: .atomic
            )
            try Data(markdown.utf8).write(to: contentURL, options: .atomic)
            try Data(markdown.utf8).write(to: sourceURL, options: .atomic)
            try Data(markdown.utf8).write(to: revisionURL, options: .atomic)
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

    private func importRequest(
        data: Data,
        fileExtension: String,
        fallbackTitle: String
    ) throws -> ImportRequest {
        let normalizedExtension = fileExtension.lowercased()
        switch normalizedExtension {
        case "md", "markdown", "mdown":
            guard let markdown = String(data: data, encoding: .utf8) else {
                throw StudyNotesContentError.unreadableFile
            }
            return ImportRequest(
                kind: .markdown,
                title: titleForImportedMarkdown(markdown, fallback: fallbackTitle),
                markdown: markdown
            )
        case "html", "htm":
            guard let html = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
                throw StudyNotesContentError.unreadableFile
            }
            let markdown = HTMLTextExtractor.htmlToMarkdown(
                HTMLTextExtractor.extractReadableHTML(html)
            )
            guard !markdown.isEmpty else {
                throw StudyNotesContentError.invalidWebArticle
            }
            return ImportRequest(
                kind: .html,
                title: HTMLTextExtractor.title(from: html) ?? fallbackTitle,
                markdown: markdown
            )
        case "pdf":
            guard PDFDocument(data: data) != nil else {
                throw StudyNotesContentError.invalidPDF
            }
            return ImportRequest(
                kind: .pdf,
                title: fallbackTitle,
                markdown: ""
            )
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "avif", "tif", "tiff", "bmp":
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
                throw StudyNotesContentError.invalidImage
            }
            return ImportRequest(
                kind: .image,
                title: fallbackTitle,
                markdown: ""
            )
        default:
            throw StudyNotesContentError.unsupportedFileType(normalizedExtension)
        }
    }

    private func titleForImportedMarkdown(_ markdown: String, fallback: String) -> String {
        let heading = markdown
            .split(separator: "\n")
            .first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("# ") }
            .map {
                String($0.trimmingCharacters(in: .whitespaces).dropFirst(2))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        return heading?.isEmpty == false ? heading! : fallback
    }

    private func createImportedPackage(
        request: ImportRequest,
        sourceData: Data,
        sourceFileName: String,
        fingerprint: String,
        knowledgeBaseID: UUID?,
        folderPath: String,
        tags: [String],
        rootURL: URL
    ) throws -> StudyMaterialSummary {
        let now = Date()
        let materialID = UUID()
        let revisionID = UUID()
        let manifest = MaterialManifest(
            schemaVersion: StudyNotesKit.schemaVersion,
            id: materialID,
            knowledgeBaseID: knowledgeBaseID,
            kind: request.kind,
            title: request.title.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: now,
            updatedAt: now,
            folderPath: folderPath,
            tags: normalizedTags(tags),
            deletedAt: nil,
            originalLocation: nil,
            originalSourceURL: request.originalSourceURL,
            sourceFileName: sourceFileName,
            contentVersionID: revisionID,
            sourceFingerprint: fingerprint,
            contentFingerprint: ContentFingerprint.sha256(request.markdown)
        )
        let destinationDirectory = try destinationDirectory(
            knowledgeBaseID: knowledgeBaseID,
            folderPath: folderPath,
            rootURL: rootURL
        )
        let destinationURL = destinationDirectory.appending(
            path: "\(materialID.uuidString).studyitem",
            directoryHint: .isDirectory
        )
        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            throw StudyNotesError.materialAlreadyExists
        }
        let temporaryURL = destinationDirectory.appending(
            path: ".tmp-\(materialID.uuidString)",
            directoryHint: .isDirectory
        )
        let sourceURL = temporaryURL
            .appending(path: "source", directoryHint: .isDirectory)
            .appending(path: sourceFileName)
        let contentURL = temporaryURL
            .appending(path: "content", directoryHint: .isDirectory)
            .appending(path: request.kind == .note ? "note.md" : "readable.md")
        let revisionURL = temporaryURL
            .appending(path: "revisions", directoryHint: .isDirectory)
            .appending(path: "\(revisionID.uuidString).md")

        do {
            for directory in [
                sourceURL.deletingLastPathComponent(),
                contentURL.deletingLastPathComponent(),
                revisionURL.deletingLastPathComponent()
            ] {
                try fileManager.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
            }
            try sourceData.write(to: sourceURL, options: .atomic)
            if request.kind.isTextDocument {
                try Data(request.markdown.utf8).write(to: contentURL, options: .atomic)
                try Data(request.markdown.utf8).write(to: revisionURL, options: .atomic)
            }
            if !request.media.isEmpty {
                let mediaDirectory = temporaryURL
                    .appending(path: "source", directoryHint: .isDirectory)
                    .appending(path: "media", directoryHint: .isDirectory)
                try fileManager.createDirectory(
                    at: mediaDirectory,
                    withIntermediateDirectories: true
                )
                for item in request.media {
                    try item.data.write(
                        to: mediaDirectory.appending(path: item.fileName),
                        options: .atomic
                    )
                }
            }
            try encode(manifest).write(
                to: temporaryURL.appending(path: "manifest.json"),
                options: .atomic
            )
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }

        return manifest.summary(
            knowledgeBaseID: knowledgeBaseID,
            folderPath: folderPath,
            conflictCopies: []
        )
    }

    private func findDuplicate(
        fingerprint: String,
        rootURL: URL
    ) throws -> StudyMaterialSummary? {
        for knowledgeBase in try loadKnowledgeBases(rootURL: rootURL) {
            let scan = try scanMaterialPackages(
                in: knowledgeBaseURL(id: knowledgeBase.id, rootURL: rootURL),
                knowledgeBaseID: knowledgeBase.id
            )
            if let package = scan.packages.first(where: {
                $0.manifest?.sourceFingerprint == fingerprint
            }), let manifest = package.manifest {
                return manifest.summary(
                    knowledgeBaseID: knowledgeBase.id,
                    folderPath: package.folderPath,
                    conflictCopies: []
                )
            }
        }
        let inbox = try scanMaterialPackages(
            in: inboxURL(at: rootURL),
            knowledgeBaseID: nil
        )
        if let package = inbox.packages.first(where: {
            $0.manifest?.sourceFingerprint == fingerprint
        }), let manifest = package.manifest {
            return manifest.summary(
                knowledgeBaseID: nil,
                folderPath: package.folderPath,
                conflictCopies: []
            )
        }
        return nil
    }

    private func editorDocumentState(
        for located: LocatedMaterial
    ) throws -> EditorDocumentState {
        let content = try loadEditorDocumentContent(for: located)
        return EditorDocumentState(
            materialID: located.manifest.id,
            title: located.manifest.title,
            markdown: content.markdown,
            blocks: content.blocks,
            isLocked: located.manifest.isLocked,
            currentGenerationID: content.generationID,
            contentFingerprint: content.fingerprint,
            derivedRebuildPending: located.manifest.derivedRebuildPending
        )
    }

    private func loadEditorDocumentContent(
        for located: LocatedMaterial
    ) throws -> EditorDocumentContent {
        try loadEditorDocumentContent(
            packageURL: located.packageURL,
            manifest: located.manifest
        )
    }

    private func loadEditorDocumentContent(
        packageURL: URL,
        manifest: MaterialManifest
    ) throws -> EditorDocumentContent {
        guard manifest.kind.isTextDocument else {
            throw StudyNotesError.materialNotFound
        }
        if let generationID = manifest.currentGenerationID {
            let generationURL = editorGenerationURL(
                generationID: generationID,
                packageURL: packageURL
            )
            guard fileManager.fileExists(atPath: generationURL.path) else {
                throw StudyNotesError.malformedMaterialPackage
            }
            return try loadEditorGenerationContent(
                at: generationURL,
                generationID: generationID
            )
        }

        let markdown: String
        if let contentURL = contentFileURL(
            kind: manifest.kind,
            packageURL: packageURL
        ), fileManager.fileExists(atPath: contentURL.path) {
            markdown = try String(contentsOf: contentURL, encoding: .utf8)
        } else {
            markdown = ""
        }
        _ = try validateEditorDocumentBlocks([], markdown: markdown)
        return EditorDocumentContent(
            markdown: markdown,
            blocks: [],
            generationID: nil,
            fingerprint: ContentFingerprint.sha256(markdown)
        )
    }

    private func loadEditorGenerationContent(
        at generationURL: URL,
        generationID: UUID
    ) throws -> EditorDocumentContent {
        let documentURL = generationURL.appending(path: "document.md")
        guard fileManager.fileExists(atPath: documentURL.path) else {
            throw StudyNotesError.malformedMaterialPackage
        }
        let markdown = try String(contentsOf: documentURL, encoding: .utf8)
        let markers = try EditorDocumentBlockMarkerParser.parse(markdown)
        var blocks: [EditorDocumentBlockEnvelope] = []

        for marker in markers {
            let blockURL = generationURL
                .appending(path: "blocks", directoryHint: .isDirectory)
                .appending(path: marker.id.uuidString, directoryHint: .isDirectory)
                .appending(path: "block.json")
            guard fileManager.fileExists(atPath: blockURL.path) else {
                throw StudyNotesError.editorDocumentBlockMissing(blockID: marker.id)
            }
            do {
                let data = try Data(contentsOf: blockURL)
                blocks.append(try decoder.decode(
                    EditorDocumentBlockEnvelope.self,
                    from: data
                ))
            } catch {
                throw StudyNotesError.editorDocumentBlockInvalid(
                    blockID: marker.id,
                    reason: error.localizedDescription
                )
            }
        }
        _ = try validateEditorDocumentBlocks(blocks, markdown: markdown)
        return EditorDocumentContent(
            markdown: markdown,
            blocks: blocks,
            generationID: generationID,
            fingerprint: try EditorDocumentFingerprint.make(
                markdown: markdown,
                blocks: blocks
            )
        )
    }

    private func commitEditorDocument(
        _ located: LocatedMaterial,
        request: EditorDocumentSaveRequest,
        createUserVisibleRevision: Bool,
        ensureRevisionExists: Bool
    ) throws -> EditorDocumentCommitResult {
        let current = try loadEditorDocumentContent(for: located)
        guard !located.manifest.isLocked else {
            throw StudyNotesError.editorDocumentLocked
        }
        guard current.fingerprint == request.expectedContentFingerprint else {
            throw StudyNotesError.editorDocumentConflict(
                expected: request.expectedContentFingerprint,
                current: current.fingerprint
            )
        }
        let markers = try validateEditorDocumentBlocks(
            request.blocks,
            markdown: request.markdown
        )
        let blocksByID = Dictionary(
            uniqueKeysWithValues: request.blocks.map { ($0.id, $0) }
        )
        let orderedBlocks = markers.compactMap { blocksByID[$0.id] }

        let normalizedTitle = request.title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let title = normalizedTitle.isEmpty
            ? located.manifest.title
            : normalizedTitle
        let generationID = UUID()
        let contentFingerprint = try EditorDocumentFingerprint.make(
            markdown: request.markdown,
            blocks: orderedBlocks
        )
        let transaction = EditorDocumentTransaction(
            id: request.transactionID,
            materialID: located.manifest.id,
            createdAt: request.createdAt,
            baseContentFingerprint: request.expectedContentFingerprint,
            generationID: generationID,
            contentFingerprint: contentFingerprint,
            title: title,
            markdown: request.markdown,
            blocks: orderedBlocks
        )
        try writeEditorDocumentTransaction(
            transaction,
            packageURL: located.packageURL
        )

        let existingRevisions = try revisions(
            packageURL: located.packageURL,
            materialID: located.manifest.id
        )
        let revision: TextRevision?
        if createUserVisibleRevision {
            revision = try appendRevision(
                text: request.markdown,
                packageURL: located.packageURL,
                materialID: located.manifest.id
            )
        } else if ensureRevisionExists,
                  let currentRevision = existingRevisions.first(where: {
                      $0.id == located.manifest.contentVersionID
                  }) {
            revision = currentRevision
        } else if ensureRevisionExists {
            revision = try appendRevision(
                text: request.markdown,
                packageURL: located.packageURL,
                materialID: located.manifest.id
            )
        } else {
            revision = existingRevisions.first {
                $0.id == located.manifest.contentVersionID
            }
        }

        var manifest = located.manifest
        manifest.title = title
        manifest.contentVersionID = revision?.id
        manifest.currentGenerationID = generationID
        manifest.contentFingerprint = contentFingerprint
        manifest.derivedRebuildPending = false
        manifest.updatedAt = request.createdAt
        let generationURL = editorGenerationURL(
            generationID: generationID,
            packageURL: located.packageURL
        )

        do {
            try writeEditorGeneration(
                markdown: request.markdown,
                blocks: orderedBlocks,
                to: generationURL
            )
            try writeManifest(manifest, to: located.packageURL)
        } catch {
            try? fileManager.removeItem(at: generationURL)
            throw error
        }

        if let oldGenerationID = current.generationID,
           oldGenerationID != generationID {
            try? fileManager.removeItem(
                at: editorGenerationURL(
                    generationID: oldGenerationID,
                    packageURL: located.packageURL
                )
            )
        }
        removeEditorDocumentTransactions(packageURL: located.packageURL)

        var updated = located
        updated.manifest = manifest
        do {
            try refreshAnnotationStatuses(
                packageURL: located.packageURL,
                materialID: located.manifest.id,
                text: request.markdown,
                kind: located.manifest.kind
            )
        } catch {
            updated.manifest.derivedRebuildPending = true
            updated.manifest.updatedAt = Date()
            try? writeManifest(updated.manifest, to: located.packageURL)
        }

        return EditorDocumentCommitResult(
            state: try editorDocumentState(for: updated),
            revision: revision
        )
    }

    private func writeEditorGeneration(
        markdown: String,
        blocks: [EditorDocumentBlockEnvelope],
        to generationURL: URL
    ) throws {
        let parentURL = generationURL.deletingLastPathComponent()
        let temporaryURL = parentURL.appending(
            path: ".tmp-\(generationURL.lastPathComponent)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(
            at: parentURL,
            withIntermediateDirectories: true
        )
        try? fileManager.removeItem(at: temporaryURL)
        try? fileManager.removeItem(at: generationURL)

        do {
            try fileManager.createDirectory(
                at: temporaryURL,
                withIntermediateDirectories: false
            )
            let documentURL = temporaryURL.appending(path: "document.md")
            try Data(markdown.utf8).write(to: documentURL, options: .atomic)

            for block in blocks {
                let blockDirectory = temporaryURL
                    .appending(path: "blocks", directoryHint: .isDirectory)
                    .appending(
                        path: block.id.uuidString,
                        directoryHint: .isDirectory
                    )
                try fileManager.createDirectory(
                    at: blockDirectory,
                    withIntermediateDirectories: true
                )
                try encode(block).write(
                    to: blockDirectory.appending(path: "block.json"),
                    options: .atomic
                )
            }

            guard try String(contentsOf: documentURL, encoding: .utf8) == markdown else {
                throw StudyNotesError.malformedMaterialPackage
            }
            for block in blocks {
                let blockURL = temporaryURL
                    .appending(path: "blocks", directoryHint: .isDirectory)
                    .appending(path: block.id.uuidString, directoryHint: .isDirectory)
                    .appending(path: "block.json")
                let decoded = try decoder.decode(
                    EditorDocumentBlockEnvelope.self,
                    from: Data(contentsOf: blockURL)
                )
                guard decoded == block else {
                    throw StudyNotesError.editorDocumentBlockInvalid(
                        blockID: block.id,
                        reason: "block.json 写入校验失败。"
                    )
                }
            }
            try fileManager.moveItem(at: temporaryURL, to: generationURL)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    private func writeEditorDocumentTransaction(
        _ transaction: EditorDocumentTransaction,
        packageURL: URL
    ) throws {
        let directory = editorTransactionsURL(packageURL: packageURL)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try encode(transaction).write(
            to: directory.appending(
                path: "\(transaction.id.uuidString).json"
            ),
            options: .atomic
        )
    }

    private func pendingEditorDocumentTransaction(
        packageURL: URL,
        materialID: UUID,
        committedGenerationID: UUID?
    ) throws -> EditorDocumentTransaction? {
        let directory = editorTransactionsURL(packageURL: packageURL)
        guard fileManager.fileExists(atPath: directory.path) else {
            return nil
        }
        let files = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        let transactions = try files
            .filter { $0.pathExtension.lowercased() == "json" }
            .map { fileURL -> EditorDocumentTransaction in
                do {
                    let transaction = try decoder.decode(
                        EditorDocumentTransaction.self,
                        from: Data(contentsOf: fileURL)
                    )
                    guard transaction.schemaVersion
                        == EditorDocumentTransaction.currentSchemaVersion else {
                        throw StudyNotesError.editorDocumentTransactionInvalid(
                            "不支持的事务版本 \(transaction.schemaVersion)。"
                        )
                    }
                    guard transaction.materialID == materialID else {
                        throw StudyNotesError.editorDocumentTransactionInvalid(
                            "事务 materialID 与材料包不一致。"
                        )
                    }
                    return transaction
                } catch let error as StudyNotesError {
                    throw error
                } catch {
                    throw StudyNotesError.editorDocumentTransactionInvalid(
                        "\(fileURL.lastPathComponent)：\(error.localizedDescription)"
                    )
                }
            }
            .filter { $0.generationID != committedGenerationID }
            .sorted { $0.createdAt > $1.createdAt }
        return transactions.first
    }

    private func removeEditorDocumentTransactions(packageURL: URL) {
        try? fileManager.removeItem(
            at: editorTransactionsURL(packageURL: packageURL)
        )
    }

    private func editorGenerationURL(
        generationID: UUID,
        packageURL: URL
    ) -> URL {
        packageURL
            .appending(path: "content", directoryHint: .isDirectory)
            .appending(path: "generations", directoryHint: .isDirectory)
            .appending(path: generationID.uuidString, directoryHint: .isDirectory)
    }

    private func editorTransactionsURL(packageURL: URL) -> URL {
        packageURL
            .appending(path: "content", directoryHint: .isDirectory)
            .appending(path: "transactions", directoryHint: .isDirectory)
    }

    private func contentFileURL(
        kind: StudyMaterialKind,
        packageURL: URL
    ) -> URL? {
        guard kind.isTextDocument else {
            return nil
        }
        return packageURL
            .appending(path: "content", directoryHint: .isDirectory)
            .appending(path: kind == .note ? "note.md" : "readable.md")
    }

    private func mediaFileURLs(in packageURL: URL) -> [String: URL] {
        let directory = packageURL
            .appending(path: "source", directoryHint: .isDirectory)
            .appending(path: "media", directoryHint: .isDirectory)
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: files.map { ($0.lastPathComponent, $0) })
    }

    private func readerText(
        packageURL: URL,
        manifest: MaterialManifest
    ) throws -> String {
        if manifest.kind.isTextDocument {
            return try loadEditorDocumentContent(
                packageURL: packageURL,
                manifest: manifest
            ).markdown
        }
        guard manifest.kind == .pdf else {
            return ""
        }
        let sourceURL = packageURL
            .appending(path: "source", directoryHint: .isDirectory)
            .appending(path: "original.pdf")
        guard let document = PDFDocument(url: sourceURL) else {
            throw StudyNotesContentError.invalidPDF
        }
        return (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")
    }

    private func revisions(
        packageURL: URL,
        materialID: UUID
    ) throws -> [TextRevision] {
        let directory = packageURL
            .appending(path: "revisions", directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: directory.path) else {
            return []
        }
        let files = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        return try files
            .filter { $0.pathExtension.lowercased() == "md" }
            .compactMap { url -> TextRevision? in
                guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else {
                    return nil
                }
                let values = try url.resourceValues(
                    forKeys: [.creationDateKey, .contentModificationDateKey]
                )
                return TextRevision(
                    id: id,
                    materialID: materialID,
                    createdAt: values.creationDate ?? values.contentModificationDate ?? .distantPast,
                    text: try String(contentsOf: url, encoding: .utf8)
                )
            }
            .sorted {
                if $0.createdAt == $1.createdAt {
                    return $0.id.uuidString > $1.id.uuidString
                }
                return $0.createdAt > $1.createdAt
            }
    }

    private func appendRevision(
        text: String,
        packageURL: URL,
        materialID: UUID
    ) throws -> TextRevision {
        let id = UUID()
        let directory = packageURL
            .appending(path: "revisions", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appending(path: "\(id.uuidString).md")
        try Data(text.utf8).write(to: fileURL, options: .atomic)
        let revision = TextRevision(
            id: id,
            materialID: materialID,
            createdAt: Date(),
            text: text
        )
        let all = try revisions(packageURL: packageURL, materialID: materialID)
        for oldRevision in all.dropFirst(10) {
            try? fileManager.removeItem(
                at: directory.appending(
                    path: "\(oldRevision.id.uuidString).md"
                )
            )
        }
        return revision
    }

    private func loadAnnotationFiles(
        packageURL: URL,
        materialID: UUID
    ) throws -> [MaterialAnnotation] {
        let directory = packageURL
            .appending(path: "annotations", directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: directory.path) else {
            return []
        }
        let files = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        var annotations: [MaterialAnnotation] = []
        for url in files where url.pathExtension.lowercased() == "json" {
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                preserveUnreadableStudyArtifact(
                    at: url,
                    packageURL: packageURL,
                    layer: "annotations",
                    reason: error.localizedDescription
                )
                continue
            }
            do {
                let annotation = try decoder.decode(MaterialAnnotation.self, from: data)
                guard annotation.materialID == materialID else {
                    preserveUnreadableStudyArtifact(
                        at: url,
                        data: data,
                        packageURL: packageURL,
                        layer: "annotations",
                        reason: "标注 materialID 与材料包不一致。"
                    )
                    continue
                }
                annotations.append(annotation)
            } catch {
                preserveUnreadableStudyArtifact(
                    at: url,
                    data: data,
                    packageURL: packageURL,
                    layer: "annotations",
                    reason: error.localizedDescription
                )
            }
        }
        return annotations.sorted {
            if $0.createdAt == $1.createdAt {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.createdAt > $1.createdAt
        }
    }

    private func writeAnnotation(
        _ annotation: MaterialAnnotation,
        packageURL: URL
    ) throws {
        let directory = packageURL
            .appending(path: "annotations", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try encode(annotation).write(
            to: directory.appending(path: "\(annotation.id.uuidString).json"),
            options: .atomic
        )
    }

    private func resolvedAnnotationStatus(
        _ annotation: MaterialAnnotation,
        text: String,
        packageURL: URL,
        kind: StudyMaterialKind
    ) -> AnnotationStatus {
        switch annotation.anchor.kind {
        case .text:
            if annotation.anchor.elementType != nil {
                return ElementAnchorResolver.resolves(annotation.anchor, in: text)
                    ? .active
                    : .unresolved
            }
            return TextAnchorResolver.range(for: annotation.anchor, in: text) == nil
                ? .unresolved
                : .active
        case .pdfText:
            return TextAnchorResolver.range(for: annotation.anchor, in: text) == nil
                ? AnnotationStatus.unresolved
                : AnnotationStatus.active
        case .imageRect:
            return annotation.anchor.rect == nil
                ? AnnotationStatus.unresolved
                : AnnotationStatus.active
        case .pdfPageRect:
            guard let pageIndex = annotation.anchor.pageIndex,
                  annotation.anchor.rect != nil else {
                return .unresolved
            }
            guard kind == .pdf else {
                return .unresolved
            }
            let sourceURL = packageURL
                .appending(path: "source", directoryHint: .isDirectory)
                .appending(path: "original.pdf")
            guard let document = PDFDocument(url: sourceURL),
                  (0..<document.pageCount).contains(pageIndex) else {
                return .unresolved
            }
            return .active
        }
    }

    private func refreshAnnotationStatuses(
        packageURL: URL,
        materialID: UUID,
        text: String,
        kind: StudyMaterialKind
    ) throws {
        let annotations = try loadAnnotationFiles(
            packageURL: packageURL,
            materialID: materialID
        )
        for annotation in annotations {
            var resolved = annotation
            resolved.status = resolvedAnnotationStatus(
                annotation,
                text: text,
                packageURL: packageURL,
                kind: kind
            )
            if annotation.anchor.kind == .text,
               annotation.anchor.elementType == nil,
               let range = TextAnchorResolver.range(
                   for: annotation.anchor,
                   in: text
               ) {
                resolved.anchor = refreshedTextAnchor(
                    annotation.anchor,
                    range: range,
                    text: text
                )
            }
            guard resolved.status != annotation.status
                    || resolved.anchor != annotation.anchor else {
                continue
            }
            resolved.updatedAt = Date()
            try writeAnnotation(resolved, packageURL: packageURL)
        }
    }

    private func refreshedTextAnchor(
        _ anchor: AnnotationAnchor,
        range: NSRange,
        text: String
    ) -> AnnotationAnchor {
        let source = text as NSString
        let excerpt = source.substring(with: range)
        let prefixStart = max(0, range.location - 48)
        let prefix = source.substring(
            with: NSRange(
                location: prefixStart,
                length: range.location - prefixStart
            )
        )
        let suffixStart = range.location + range.length
        let suffixLength = min(48, source.length - suffixStart)
        let suffix = source.substring(
            with: NSRange(location: suffixStart, length: suffixLength)
        )
        let blockPath = markdownBlockPath(
            atUTF16Offset: range.location,
            in: text
        )
        let blockText = markdownBlock(
            at: blockPath.first,
            in: text
        )
        return AnnotationAnchor(
            kind: anchor.kind,
            excerpt: excerpt,
            prefix: prefix,
            suffix: suffix,
            offset: range.location,
            blockPath: blockPath,
            pageIndex: anchor.pageIndex,
            rect: anchor.rect,
            elementType: anchor.elementType,
            contentFingerprint: ContentFingerprint.sha256(blockText),
            contentSummary: excerpt
        )
    }

    private func markdownBlockPath(
        atUTF16Offset offset: Int,
        in text: String
    ) -> [Int] {
        let blocks = text.components(separatedBy: "\n\n")
        var cursor = 0
        for (index, block) in blocks.enumerated() {
            let length = (block as NSString).length
            if offset <= cursor + length {
                return [index]
            }
            cursor += length + 2
        }
        return blocks.isEmpty ? [] : [blocks.count - 1]
    }

    private func markdownBlock(
        at index: Int?,
        in text: String
    ) -> String {
        let blocks = text.components(separatedBy: "\n\n")
        guard let index, blocks.indices.contains(index) else {
            return text
        }
        return blocks[index]
    }

    private func sameAnchorLocation(
        _ left: AnnotationAnchor,
        _ right: AnnotationAnchor
    ) -> Bool {
        guard left.kind == right.kind,
              left.elementType == right.elementType else {
            return false
        }
        if let leftFingerprint = left.contentFingerprint,
           let rightFingerprint = right.contentFingerprint,
           leftFingerprint != rightFingerprint {
            return false
        }
        if let leftRect = left.rect, let rightRect = right.rect {
            return left.pageIndex == right.pageIndex
                && abs(leftRect.x - rightRect.x) < 0.005
                && abs(leftRect.y - rightRect.y) < 0.005
                && abs(leftRect.width - rightRect.width) < 0.005
                && abs(leftRect.height - rightRect.height) < 0.005
        }
        if left.elementType != nil {
            if left.blockPath == right.blockPath {
                return true
            }
            let leftRecovery = left.excerpt.isEmpty
                ? (left.contentSummary ?? "")
                : left.excerpt
            let rightRecovery = right.excerpt.isEmpty
                ? (right.contentSummary ?? "")
                : right.excerpt
            return leftRecovery == rightRecovery
                && left.prefix == right.prefix
                && left.suffix == right.suffix
        }
        guard left.excerpt == right.excerpt else {
            return false
        }
        if let leftOffset = left.offset, let rightOffset = right.offset {
            return abs(leftOffset - rightOffset) <= 2
        }
        return left.prefix == right.prefix && left.suffix == right.suffix
    }

    private func conversationFiles(packageURL: URL) throws -> [AIConversation] {
        let directory = packageURL
            .appending(path: "ai", directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: directory.path) else {
            return []
        }
        let files = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        var conversations: [AIConversation] = []
        for url in files where url.pathExtension.lowercased() == "json" {
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                preserveUnreadableStudyArtifact(
                    at: url,
                    packageURL: packageURL,
                    layer: "ai",
                    reason: error.localizedDescription
                )
                continue
            }
            do {
                conversations.append(try decoder.decode(AIConversation.self, from: data))
            } catch {
                preserveUnreadableStudyArtifact(
                    at: url,
                    data: data,
                    packageURL: packageURL,
                    layer: "ai",
                    reason: error.localizedDescription
                )
            }
        }
        return conversations.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func preserveUnreadableStudyArtifact(
        at fileURL: URL,
        data: Data? = nil,
        packageURL: URL,
        layer: String,
        reason: String
    ) {
        let conflictDirectory = layer.isEmpty
            ? packageURL.appending(path: "conflicts", directoryHint: .isDirectory)
            : packageURL
                .appending(path: layer, directoryHint: .isDirectory)
                .appending(path: "conflicts", directoryHint: .isDirectory)
        do {
            try fileManager.createDirectory(
                at: conflictDirectory,
                withIntermediateDirectories: true
            )
            let suffix = "\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8))"
            let baseName = fileURL.deletingPathExtension().lastPathComponent
            let preservedURL = conflictDirectory.appending(
                path: "\(baseName).\(suffix).unreadable.json"
            )
            let preservedData = try data ?? Data(contentsOf: fileURL)
            try preservedData.write(to: preservedURL, options: .atomic)
            try Data(reason.utf8).write(
                to: preservedURL
                    .deletingPathExtension()
                    .appendingPathExtension("error.txt"),
                options: .atomic
            )
        } catch {
            // Preserve other readable study data even if the diagnostic copy fails.
        }
    }

    private func searchableDocuments(rootURL: URL) throws -> [SearchableDocument] {
        var packages: [(ScannedPackage, UUID?)] = []
        for knowledgeBase in try loadKnowledgeBases(rootURL: rootURL) {
            let scan = try scanMaterialPackages(
                in: knowledgeBaseURL(id: knowledgeBase.id, rootURL: rootURL),
                knowledgeBaseID: knowledgeBase.id
            )
            packages.append(contentsOf: scan.packages.map { ($0, knowledgeBase.id) })
        }
        let inbox = try scanMaterialPackages(
            in: inboxURL(at: rootURL),
            knowledgeBaseID: nil
        )
        packages.append(contentsOf: inbox.packages.map { ($0, nil) })

        return try packages.compactMap { package, knowledgeBaseID in
            guard let manifest = package.manifest else {
                return nil
            }
            let text = try readerText(
                packageURL: package.packageURL,
                manifest: manifest
            )
            let annotations = try loadAnnotationFiles(
                packageURL: package.packageURL,
                materialID: manifest.id
            )
            .map { [$0.quote, $0.note].joined(separator: "\n") }
            .joined(separator: "\n")
            let ai = try conversationFiles(packageURL: package.packageURL)
                .flatMap(\.messages)
                .map(\.content)
                .joined(separator: "\n")
            return SearchableDocument(
                materialID: manifest.id,
                knowledgeBaseID: knowledgeBaseID,
                kind: manifest.kind,
                title: manifest.title,
                body: text,
                annotations: annotations,
                ai: ai,
                tags: manifest.tags,
                updatedAt: manifest.updatedAt
            )
        }
    }

    private func ensureSearchIndex(rootURL: URL) throws -> StudyNotesSearchIndex {
        if let searchIndex {
            return searchIndex
        }
        let databaseURL: URL
        if let explicitDerivedDataURL {
            databaseURL = explicitDerivedDataURL
        } else {
            let applicationSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            databaseURL = applicationSupport
                .appending(path: "StudyNotes", directoryHint: .isDirectory)
                .appending(path: "Index", directoryHint: .isDirectory)
                .appending(
                    path: "\(ContentFingerprint.sha256(rootURL.path).prefix(20)).sqlite"
                )
        }
        let index = StudyNotesSearchIndex(databaseURL: databaseURL)
        searchIndex = index
        return index
    }

    private func publishMediaItems(packageURL: URL) throws -> [PublishMediaItem] {
        let directory = packageURL
            .appending(path: "source", directoryHint: .isDirectory)
            .appending(path: "media", directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: directory.path) else {
            return []
        }
        return try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        .map { url in
            let data = try Data(contentsOf: url)
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            return PublishMediaItem(
                id: url.lastPathComponent,
                fileName: url.lastPathComponent,
                localPath: url.path,
                contentHash: ContentFingerprint.sha256(data),
                mediaType: mediaType(forFileName: url.lastPathComponent),
                byteCount: values.fileSize ?? data.count,
                state: .pendingCredentials
            )
        }
        .sorted { $0.fileName < $1.fileName }
    }

    private func mediaType(forFileName fileName: String) -> String {
        switch URL(fileURLWithPath: fileName).pathExtension.lowercased() {
        case "png":
            "image/png"
        case "gif":
            "image/gif"
        case "webp":
            "image/webp"
        case "heic":
            "image/heic"
        case "avif":
            "image/avif"
        default:
            "image/jpeg"
        }
    }

    private func localizeWebMediaReferences(
        _ markdown: String,
        media: [WebArticleMedia]
    ) -> String {
        var result = markdown
        for item in media {
            result = result.replacingOccurrences(
                of: item.sourceURL.absoluteString,
                with: "media://\(item.fileName)"
            )
        }
        return result
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

    private func scanInboxDrafts(in containerURL: URL) throws -> [InboxDraftPackage] {
        guard fileManager.fileExists(atPath: containerURL.path) else {
            return []
        }
        let children = try fileManager.contentsOfDirectory(
            at: containerURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var drafts: [InboxDraftPackage] = []
        for childURL in children where
            childURL.pathExtension == "inboxitem" && isRegularDirectory(childURL) {
            let manifestURL = childURL.appending(path: "manifest.json")
            do {
                let data = try Data(contentsOf: manifestURL)
                let manifest = try decoder.decode(
                    CrossPlatformInboxManifest.self,
                    from: data
                )
                guard fileManager.fileExists(
                    atPath: childURL.appending(path: manifest.payloadFile).path
                ) else {
                    preserveUnreadableStudyArtifact(
                        at: manifestURL,
                        data: data,
                        packageURL: childURL,
                        layer: "",
                        reason: "收件箱草稿缺少载荷文件 \(manifest.payloadFile)。"
                    )
                    continue
                }
                drafts.append(
                    InboxDraftPackage(packageURL: childURL, manifest: manifest)
                )
            } catch {
                preserveUnreadableStudyArtifact(
                    at: manifestURL,
                    packageURL: childURL,
                    layer: "",
                    reason: error.localizedDescription
                )
            }
        }
        return drafts.sorted { $0.manifest.createdAt > $1.manifest.createdAt }
    }

    private func locateInboxDraft(
        id: UUID,
        rootURL: URL
    ) throws -> InboxDraftPackage? {
        try scanInboxDrafts(in: inboxURL(at: rootURL)).first {
            $0.manifest.id == id
        }
    }

    private func inboxDraftSummary(_ draft: InboxDraftPackage) -> StudyMaterialSummary {
        StudyMaterialSummary(
            id: draft.manifest.id,
            knowledgeBaseID: nil,
            kind: draft.studyMaterialKind,
            title: draft.manifest.title,
            updatedAt: draft.manifest.createdAt,
            conflictCopies: [],
            folderPath: "",
            tags: [],
            originalSourceURL: draft.originalSourceURL
        )
    }

    private func loadInboxDraftDocument(
        _ draft: InboxDraftPackage
    ) throws -> MaterialDocument {
        let payloadURL = draft.packageURL.appending(path: draft.manifest.payloadFile)
        let data = try Data(contentsOf: payloadURL)
        let markdown: String
        switch draft.manifest.kind {
        case .url:
            let value = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? draft.manifest.title
            markdown = "# \(draft.manifest.title)\n\n[打开原始链接](\(value))"
        case .text:
            markdown = String(data: data, encoding: .utf8) ?? ""
        case .image:
            markdown = ""
        }
        let mediaURLs = draft.manifest.kind == .image
            ? [draft.manifest.payloadFile: payloadURL]
            : [:]
        let content = ReaderContentBuilder.build(
            markdown: markdown,
            title: draft.manifest.title,
            mediaURLs: mediaURLs
        )
        return MaterialDocument(
            summary: inboxDraftSummary(draft),
            markdown: markdown,
            renderedHTML: content.html,
            headings: content.headings,
            sourceURL: draft.packageURL,
            sourceFileURL: draft.manifest.kind == .image ? payloadURL : nil,
            mediaURLs: mediaURLs
        )
    }

    private func inboxDraftMaterialManifest(
        _ draft: InboxDraftPackage,
        knowledgeBaseID: UUID?,
        folderPath: String
    ) throws -> MaterialManifest {
        let payload = try Data(contentsOf: draft.payloadURL)
        let payloadExtension = draft.payloadURL.pathExtension.lowercased()
        let kind = draft.studyMaterialKind
        return MaterialManifest(
            schemaVersion: StudyNotesKit.schemaVersion,
            id: draft.manifest.id,
            knowledgeBaseID: knowledgeBaseID,
            kind: kind,
            title: draft.manifest.title,
            createdAt: draft.manifest.createdAt,
            updatedAt: Date(),
            folderPath: folderPath,
            tags: [],
            deletedAt: nil,
            originalLocation: nil,
            originalSourceURL: draft.originalSourceURL,
            sourceFileName: kind == .image && !payloadExtension.isEmpty
                ? "original.\(payloadExtension)"
                : nil,
            contentVersionID: UUID(),
            sourceFingerprint: ContentFingerprint.sha256(payload),
            contentFingerprint: String(data: payload, encoding: .utf8).map {
                ContentFingerprint.sha256(Data($0.utf8))
            }
        )
    }

    private func materializeInboxDraft(
        _ draft: InboxDraftPackage,
        destinationURL: URL,
        manifest: MaterialManifest
    ) throws {
        let parentURL = destinationURL.deletingLastPathComponent()
        let temporaryURL = parentURL.appending(
            path: ".tmp-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(
            at: temporaryURL,
            withIntermediateDirectories: false
        )
        do {
            let contentDirectory = temporaryURL.appending(
                path: "content",
                directoryHint: .isDirectory
            )
            let sourceDirectory = temporaryURL.appending(
                path: "source",
                directoryHint: .isDirectory
            )
            try fileManager.createDirectory(
                at: contentDirectory,
                withIntermediateDirectories: true
            )
            let payload = try Data(contentsOf: draft.payloadURL)
            if manifest.kind == .image {
                try fileManager.createDirectory(
                    at: sourceDirectory,
                    withIntermediateDirectories: true
                )
                try payload.write(
                    to: sourceDirectory.appending(path: manifest.sourceFileName ?? "original"),
                    options: .atomic
                )
            } else {
                let markdown: String
                switch draft.manifest.kind {
                case .url:
                    let value = String(data: payload, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        ?? draft.manifest.title
                    markdown = "# \(draft.manifest.title)\n\n[打开原始链接](\(value))"
                case .text, .image:
                    markdown = String(data: payload, encoding: .utf8) ?? ""
                }
                try Data(markdown.utf8).write(
                    to: contentDirectory.appending(
                        path: manifest.kind == .note ? "note.md" : "readable.md"
                    ),
                    options: .atomic
                )
            }
            try encode(manifest).write(
                to: temporaryURL.appending(path: "manifest.json"),
                options: .atomic
            )
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
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
        CrossPlatformJSON.encoder()
    }

    private var decoder: JSONDecoder {
        CrossPlatformJSON.decoder()
    }
}

private struct MaterialManifest: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let id: UUID
    var knowledgeBaseID: UUID?
    let kind: StudyMaterialKind
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var folderPath: String
    var tags: [String]
    var deletedAt: Date?
    var originalLocation: MaterialOriginalLocation?
    var linkedMaterialIDs: [UUID]
    var originalSourceURL: URL?
    var sourceFileName: String?
    var contentVersionID: UUID?
    var sourceFingerprint: String?
    var contentFingerprint: String?
    var currentGenerationID: UUID?
    var isLocked: Bool
    var derivedRebuildPending: Bool
    var publishMapping: PublishMapping?

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
        originalLocation: MaterialOriginalLocation?,
        linkedMaterialIDs: [UUID] = [],
        originalSourceURL: URL? = nil,
        sourceFileName: String? = nil,
        contentVersionID: UUID? = nil,
        sourceFingerprint: String? = nil,
        contentFingerprint: String? = nil,
        currentGenerationID: UUID? = nil,
        isLocked: Bool = false,
        derivedRebuildPending: Bool = false,
        publishMapping: PublishMapping? = nil
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
        self.linkedMaterialIDs = linkedMaterialIDs
        self.originalSourceURL = originalSourceURL
        self.sourceFileName = sourceFileName
        self.contentVersionID = contentVersionID
        self.sourceFingerprint = sourceFingerprint
        self.contentFingerprint = contentFingerprint
        self.currentGenerationID = currentGenerationID
        self.isLocked = isLocked
        self.derivedRebuildPending = derivedRebuildPending
        self.publishMapping = publishMapping
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case knowledgeBaseID
        case kind
        case title
        case createdAt
        case updatedAt
        case folderPath
        case tags
        case deletedAt
        case originalLocation
        case linkedMaterialIDs
        case originalSourceURL
        case sourceFileName
        case contentVersionID
        case sourceFingerprint
        case contentFingerprint
        case currentGenerationID
        case isLocked = "locked"
        case derivedRebuildPending
        case publishMapping
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
        linkedMaterialIDs = try container.decodeIfPresent(
            [UUID].self,
            forKey: .linkedMaterialIDs
        ) ?? []
        originalSourceURL = try container.decodeIfPresent(URL.self, forKey: .originalSourceURL)
        sourceFileName = try container.decodeIfPresent(String.self, forKey: .sourceFileName)
        contentVersionID = try container.decodeIfPresent(UUID.self, forKey: .contentVersionID)
        sourceFingerprint = try container.decodeIfPresent(String.self, forKey: .sourceFingerprint)
        contentFingerprint = try container.decodeIfPresent(String.self, forKey: .contentFingerprint)
        currentGenerationID = try container.decodeIfPresent(
            UUID.self,
            forKey: .currentGenerationID
        )
        isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        derivedRebuildPending = try container.decodeIfPresent(
            Bool.self,
            forKey: .derivedRebuildPending
        ) ?? false
        publishMapping = try container.decodeIfPresent(PublishMapping.self, forKey: .publishMapping)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(knowledgeBaseID, forKey: .knowledgeBaseID)
        try container.encode(kind, forKey: .kind)
        try container.encode(title, forKey: .title)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(folderPath, forKey: .folderPath)
        try container.encode(tags, forKey: .tags)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try container.encodeIfPresent(originalLocation, forKey: .originalLocation)
        try container.encode(linkedMaterialIDs, forKey: .linkedMaterialIDs)
        try container.encodeIfPresent(originalSourceURL, forKey: .originalSourceURL)
        try container.encodeIfPresent(sourceFileName, forKey: .sourceFileName)
        try container.encodeIfPresent(contentVersionID, forKey: .contentVersionID)
        try container.encodeIfPresent(sourceFingerprint, forKey: .sourceFingerprint)
        if let contentFingerprint {
            try container.encode(contentFingerprint, forKey: .contentFingerprint)
        } else {
            try container.encodeNil(forKey: .contentFingerprint)
        }
        if let currentGenerationID {
            try container.encode(currentGenerationID, forKey: .currentGenerationID)
        } else {
            try container.encodeNil(forKey: .currentGenerationID)
        }
        try container.encode(isLocked, forKey: .isLocked)
        try container.encode(derivedRebuildPending, forKey: .derivedRebuildPending)
        try container.encodeIfPresent(publishMapping, forKey: .publishMapping)
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
            deletedAt: deletedAt,
            linkedMaterialIDs: linkedMaterialIDs,
            originalSourceURL: originalSourceURL,
            publishMapping: publishMapping
        )
    }
}

private struct MaterialOriginalLocation: Codable, Equatable, Sendable {
    let knowledgeBaseID: UUID?
    let folderPath: String
}

private struct ImportRequest: Sendable {
    let kind: StudyMaterialKind
    let title: String
    let markdown: String
    var originalSourceURL: URL? = nil
    var media: [WebArticleMedia] = []
    var mediaFailures: [WebArticleMediaFailure] = []
}

private struct ScannedPackage {
    let packageURL: URL
    let folderPath: String
    let manifest: MaterialManifest?
}

private struct EditorDocumentCommitResult {
    let state: EditorDocumentState
    let revision: TextRevision?
}

private struct InboxDraftPackage {
    let packageURL: URL
    let manifest: CrossPlatformInboxManifest

    var payloadURL: URL {
        packageURL.appending(path: manifest.payloadFile)
    }

    var studyMaterialKind: StudyMaterialKind {
        switch manifest.kind {
        case .url:
            .webArticle
        case .image:
            .image
        case .text:
            .note
        }
    }

    var originalSourceURL: URL? {
        guard manifest.kind == .url,
              let value = try? String(contentsOf: payloadURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }
        return URL(string: value)
    }
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
