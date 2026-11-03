import Foundation
import StudyNotesKit

public actor IOSLibraryStore {
    public let rootURL: URL

    private let fileManager: FileManager
    private let sharedStore: StudyNotesStore
    private let onDemandRootURL: URL
    private let offlineRootURL: URL
    private let pendingRootURL: URL
    private let decoder = StudyNotesFileSupport.decoder()
    private let encoder = StudyNotesFileSupport.encoder()

    public init(
        rootURL: URL,
        fileManager: FileManager = .default
    ) throws {
        self.rootURL = rootURL
        self.fileManager = fileManager
        self.sharedStore = StudyNotesStore(
            rootURL: rootURL
        )
        let support = try StudyNotesFileSupport.applicationSupportDirectory(
            fileManager: fileManager
        )
        self.onDemandRootURL = support.appending(
            path: "OnDemand",
            directoryHint: .isDirectory
        )
        self.offlineRootURL = support.appending(
            path: "Offline",
            directoryHint: .isDirectory
        )
        self.pendingRootURL = support.appending(
            path: "PendingMutations",
            directoryHint: .isDirectory
        )
        for directory in [onDemandRootURL, offlineRootURL, pendingRootURL] {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
    }

    public func snapshot(isICloud: Bool) async throws -> IOSLibrarySnapshot {
        try prepareRoot()
        _ = try? flushPendingMutations()

        let knowledgeBases = try loadKnowledgeBases()
        let knowledgeBaseNames = Dictionary(
            uniqueKeysWithValues: knowledgeBases.map { ($0.id, $0.name) }
        )
        var materials: [LibraryMaterial] = []

        let librariesURL = rootURL.appending(
            path: "Libraries",
            directoryHint: .isDirectory
        )
        let indexedFolders = (try? await sharedStore.loadIndex().folders) ?? []
        let folders = indexedFolders.map {
            IOSFolder(
                knowledgeBaseID: $0.knowledgeBaseID,
                name: $0.name,
                path: $0.path,
                parentPath: $0.parentPath
            )
        }
        guard fileManager.fileExists(atPath: librariesURL.path) else {
            return IOSLibrarySnapshot(
                knowledgeBases: knowledgeBases,
                materials: [],
                folders: folders,
                rootURL: rootURL,
                isICloud: isICloud
            )
        }

        let libraryDirectories = try fileManager.contentsOfDirectory(
            at: librariesURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        for libraryURL in libraryDirectories where isRegularDirectory(libraryURL) {
            let libraryID = UUID(uuidString: libraryURL.lastPathComponent)
            let fallbackName = libraryID.flatMap { knowledgeBaseNames[$0] }
                ?? libraryURL.lastPathComponent
            for packageURL in try studyItemPackages(in: libraryURL) {
                do {
                    let manifest = try loadManifest(at: packageURL)
                    guard manifest.deletedAt == nil else {
                        continue
                    }
                    materials.append(
                        LibraryMaterial(
                            manifest: manifest,
                            knowledgeBaseName: fallbackName,
                            packageURL: packageURL,
                            accessState: accessState(for: packageURL)
                        )
                    )
                } catch {
                    continue
                }
            }
        }

        materials.sort {
            if $0.manifest.updatedAt == $1.manifest.updatedAt {
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            return $0.manifest.updatedAt > $1.manifest.updatedAt
        }
        return IOSLibrarySnapshot(
            knowledgeBases: knowledgeBases,
            materials: materials,
            folders: folders,
            rootURL: rootURL,
            isICloud: isICloud
        )
    }

    @discardableResult
    public func createFolder(
        named name: String,
        in knowledgeBaseID: UUID,
        parentPath: String = ""
    ) async throws -> IOSFolder {
        let folder = try await sharedStore.createFolder(
            named: name,
            in: knowledgeBaseID,
            parentPath: parentPath
        )
        return iosFolder(folder)
    }

    @discardableResult
    public func renameFolder(
        at path: String,
        in knowledgeBaseID: UUID,
        to name: String
    ) async throws -> IOSFolder {
        let folder = try await sharedStore.renameFolder(
            at: path,
            in: knowledgeBaseID,
            to: name
        )
        return iosFolder(folder)
    }

    @discardableResult
    public func moveFolder(
        at path: String,
        in knowledgeBaseID: UUID,
        toParentPath parentPath: String
    ) async throws -> IOSFolder {
        let folder = try await sharedStore.moveFolder(
            at: path,
            in: knowledgeBaseID,
            toParentPath: parentPath
        )
        return iosFolder(folder)
    }

    @discardableResult
    public func deleteFolder(
        at path: String,
        in knowledgeBaseID: UUID
    ) async throws -> [UUID] {
        try await sharedStore.deleteFolder(
            at: path,
            in: knowledgeBaseID
        )
    }

    @discardableResult
    public func createMarkdownNote(
        title: String,
        in knowledgeBaseID: UUID,
        markdown: String,
        folderPath: String = ""
    ) async throws -> UUID {
        let note = try await sharedStore.createMarkdownNote(
            title: title,
            in: knowledgeBaseID,
            markdown: markdown,
            folderPath: folderPath
        )
        return note.summary.id
    }

    public func moveMaterials(
        ids: [UUID],
        toKnowledgeBaseID knowledgeBaseID: UUID,
        folderPath: String = ""
    ) async throws {
        _ = try await sharedStore.moveMaterials(
            ids: ids,
            toKnowledgeBaseID: knowledgeBaseID,
            folderPath: folderPath
        )
    }

    public func moveMaterialsToRecycleBin(ids: [UUID]) async throws {
        _ = try await sharedStore.moveMaterialsToRecycleBin(ids: ids)
    }

    @discardableResult
    public func saveMarkdown(
        materialID: UUID,
        text: String,
        title: String,
        createRecoveryVersion: Bool
    ) async throws -> String {
        let normalized = try MarkdownEditorCodec().normalize(text)
        _ = try await sharedStore.saveReaderCopy(
            id: materialID,
            text: normalized,
            title: title,
            createRecoveryVersion: createRecoveryVersion
        )
        try synchronizeReadCopies(materialID: materialID)
        return normalized
    }

    public func requestDownload(
        materialID: UUID,
        isICloud: Bool
    ) async throws -> LibraryMaterial {
        guard let material = try await snapshot(isICloud: isICloud).materials.first(
            where: { $0.id == materialID }
        ) else {
            throw StudyNotesIOSError.materialNotFound
        }
        guard isICloud else {
            return material
        }

        try await downloadUbiquitousPackage(at: material.packageURL)
        let localCopy = onDemandRootURL.appending(
            path: "\(materialID.uuidString).studyitem",
            directoryHint: .isDirectory
        )
        try replaceCopy(from: material.packageURL, to: localCopy)
        return LibraryMaterial(
            manifest: material.manifest,
            knowledgeBaseName: material.knowledgeBaseName,
            packageURL: material.packageURL,
            accessState: .downloaded
        )
    }

    public func saveOffline(
        materialID: UUID,
        isICloud: Bool
    ) async throws -> LibraryMaterial {
        let downloaded = try await requestDownload(
            materialID: materialID,
            isICloud: isICloud
        )
        let destinationURL = offlineRootURL.appending(
            path: "\(materialID.uuidString).studyitem",
            directoryHint: .isDirectory
        )
        try replaceCopy(from: downloaded.packageURL, to: destinationURL)
        return LibraryMaterial(
            manifest: downloaded.manifest,
            knowledgeBaseName: downloaded.knowledgeBaseName,
            packageURL: downloaded.packageURL,
            accessState: .offline
        )
    }

    public func removeOffline(
        materialID: UUID,
        isICloud: Bool
    ) async throws -> LibraryMaterial {
        let offlineURL = offlinePackageURL(for: materialID)
        if fileManager.fileExists(atPath: offlineURL.path) {
            try fileManager.removeItem(at: offlineURL)
        }
        let onDemandURL = onDemandPackageURL(for: materialID)
        if fileManager.fileExists(atPath: onDemandURL.path) {
            try fileManager.removeItem(at: onDemandURL)
        }
        guard let material = try await snapshot(isICloud: isICloud).materials.first(
            where: { $0.id == materialID }
        ) else {
            throw StudyNotesIOSError.materialNotFound
        }
        return material
    }

    public func loadDocument(
        materialID: UUID,
        isICloud: Bool
    ) async throws -> MaterialDocument {
        guard let material = try await snapshot(isICloud: isICloud).materials.first(
            where: { $0.id == materialID }
        ) else {
            throw StudyNotesIOSError.materialNotFound
        }
        guard material.isTextSearchable || !isICloud else {
            throw StudyNotesIOSError.materialNotDownloaded
        }
        let packageURL = readPackageURL(for: materialID) ?? material.packageURL
        let contentURL = try resolveContentURL(
            in: packageURL,
            manifest: material.manifest
        )
        let sourceText: String?
        switch material.kind {
        case .markdown, .html, .webArticle, .note, .unknown:
            sourceText = try String(contentsOf: contentURL, encoding: .utf8)
        case .pdf, .image:
            sourceText = nil
        }
        return MaterialDocument(
            material: material,
            packageURL: packageURL,
            contentURL: contentURL,
            sourceText: sourceText
        )
    }

    public func loadAnnotations(
        materialID: UUID,
        sourceText: String?
    ) throws -> [StudyAnnotation] {
        var annotations: [UUID: StudyAnnotation] = [:]
        for packageURL in candidatePackages(for: materialID) {
            let annotationsURL = packageURL.appending(
                path: "annotations",
                directoryHint: .isDirectory
            )
            guard fileManager.fileExists(atPath: annotationsURL.path) else {
                continue
            }
            let files = try fileManager.contentsOfDirectory(
                at: annotationsURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            for fileURL in files where fileURL.pathExtension == "json" {
                let data: Data
                do {
                    data = try Data(contentsOf: fileURL)
                } catch {
                    preserveUnreadableArtifact(
                        at: fileURL,
                        packageURL: packageURL,
                        layer: "annotations",
                        reason: error.localizedDescription
                    )
                    continue
                }
                let annotation: StudyAnnotation
                do {
                    annotation = try decoder.decode(StudyAnnotation.self, from: data)
                } catch {
                    preserveUnreadableArtifact(
                        at: fileURL,
                        data: data,
                        packageURL: packageURL,
                        layer: "annotations",
                        reason: error.localizedDescription
                    )
                    continue
                }
                guard annotation.materialID == materialID else {
                    preserveUnreadableArtifact(
                        at: fileURL,
                        data: data,
                        packageURL: packageURL,
                        layer: "annotations",
                        reason: "标注 materialID 与材料包不一致。"
                    )
                    continue
                }
                var resolved = annotation
                resolved.resolution = TextAnchorResolver.isResolved(
                    annotation.anchor,
                    in: sourceText
                )
                if let existing = annotations[resolved.id],
                   existing.updatedAt > resolved.updatedAt {
                    continue
                }
                annotations[resolved.id] = resolved
            }
        }
        return annotations.values.sorted { $0.createdAt < $1.createdAt }
    }

    @discardableResult
    public func saveAnnotation(
        _ annotation: StudyAnnotation,
        materialID: UUID,
        sourceText: String?
    ) throws -> StudyAnnotation {
        let existing = try loadAnnotations(
            materialID: materialID,
            sourceText: sourceText
        )
        if let equivalent = existing.first(where: {
            $0.id != annotation.id
                && TextAnchorResolver.anchorsAreEquivalent($0.anchor, annotation.anchor)
        }) {
            var updated = equivalent
            updated.note = annotation.note
            updated.updatedAt = Date()
            try writeAnnotation(updated, materialID: materialID)
            return updated
        }
        try writeAnnotation(annotation, materialID: materialID)
        return annotation
    }

    public func deleteAnnotation(
        id: UUID,
        materialID: UUID
    ) throws {
        for packageURL in candidatePackages(for: materialID) {
            let fileURL = packageURL
                .appending(path: "annotations", directoryHint: .isDirectory)
                .appending(path: "\(id.uuidString).json")
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
        }
    }

    public func loadConversations(materialID: UUID) throws -> [AIConversation] {
        var conversations: [UUID: AIConversation] = [:]
        for packageURL in candidatePackages(for: materialID) {
            let directoryURL = packageURL.appending(
                path: "ai",
                directoryHint: .isDirectory
            )
            guard fileManager.fileExists(atPath: directoryURL.path) else {
                continue
            }
            for fileURL in try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) where fileURL.pathExtension == "json" {
                let data: Data
                do {
                    data = try Data(contentsOf: fileURL)
                } catch {
                    preserveUnreadableArtifact(
                        at: fileURL,
                        packageURL: packageURL,
                        layer: "ai",
                        reason: error.localizedDescription
                    )
                    continue
                }
                let conversation: AIConversation
                do {
                    conversation = try decoder.decode(AIConversation.self, from: data)
                } catch {
                    preserveUnreadableArtifact(
                        at: fileURL,
                        data: data,
                        packageURL: packageURL,
                        layer: "ai",
                        reason: error.localizedDescription
                    )
                    continue
                }
                guard conversation.materialID == materialID else {
                    preserveUnreadableArtifact(
                        at: fileURL,
                        data: data,
                        packageURL: packageURL,
                        layer: "ai",
                        reason: "AI 会话 materialID 与材料包不一致。"
                    )
                    continue
                }
                if let existing = conversations[conversation.id],
                   existing.updatedAt > conversation.updatedAt {
                    continue
                }
                conversations[conversation.id] = conversation
            }
        }
        return conversations.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    public func saveConversation(_ conversation: AIConversation) throws {
        let data = try encoder.encode(conversation)
        var wrote = false
        var firstError: Error?
        for packageURL in candidatePackages(for: conversation.materialID) {
            let fileURL = packageURL
                .appending(path: "ai", directoryHint: .isDirectory)
                .appending(path: "\(conversation.id.uuidString).json")
            do {
                try StudyNotesFileSupport.writeAtomically(data, to: fileURL)
                wrote = true
            } catch {
                firstError = firstError ?? error
            }
        }
        guard wrote else {
            throw firstError ?? StudyNotesIOSError.materialNotDownloaded
        }
    }

    public func isDownloaded(_ materialID: UUID) -> Bool {
        fileManager.fileExists(atPath: offlinePackageURL(for: materialID).path)
            || fileManager.fileExists(atPath: onDemandPackageURL(for: materialID).path)
    }

    public func scanTextForSearch(
        materialID: UUID,
        isICloud: Bool
    ) async -> String {
        guard let document = try? await loadDocument(
            materialID: materialID,
            isICloud: isICloud
        ) else {
            return ""
        }
        return (document.sourceText ?? "")
            + "\n"
            + ((try? loadAnnotations(
                materialID: materialID,
                sourceText: document.sourceText
            )) ?? []).map { [$0.quote ?? "", $0.note].joined(separator: " ") }
                .joined(separator: "\n")
            + "\n"
            + ((try? loadConversations(materialID: materialID)) ?? [])
                .flatMap(\.messages)
                .map(\.content)
                .joined(separator: "\n")
    }

    private func iosFolder(_ folder: KnowledgeFolder) -> IOSFolder {
        IOSFolder(
            knowledgeBaseID: folder.knowledgeBaseID,
            name: folder.name,
            path: folder.path,
            parentPath: folder.parentPath
        )
    }

    private func synchronizeReadCopies(materialID: UUID) throws {
        guard let rootPackage = try locatePackage(materialID: materialID) else {
            return
        }
        let rootManifest = try loadManifest(at: rootPackage)
        let rootContentURL = try resolveContentURL(
            in: rootPackage,
            manifest: rootManifest
        )
        let rootContent = try Data(contentsOf: rootContentURL)
        let rootManifestData = try Data(
            contentsOf: rootPackage.appending(path: "manifest.json")
        )

        for packageURL in [
            offlinePackageURL(for: materialID),
            onDemandPackageURL(for: materialID)
        ] where fileManager.fileExists(atPath: packageURL.path) {
            let localManifest = try loadManifest(at: packageURL)
            let localContentURL = try resolveContentURL(
                in: packageURL,
                manifest: localManifest
            )
            try StudyNotesFileSupport.writeAtomically(
                rootContent,
                to: localContentURL
            )
            try StudyNotesFileSupport.writeAtomically(
                rootManifestData,
                to: packageURL.appending(path: "manifest.json")
            )
        }
    }

    private func prepareRoot() throws {
        for directory in [
            rootURL,
            rootURL.appending(path: "Libraries", directoryHint: .isDirectory),
            rootURL.appending(path: "Inbox", directoryHint: .isDirectory)
        ] {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
    }

    private func loadKnowledgeBases() throws -> [KnowledgeBaseSummary] {
        let librariesURL = rootURL.appending(
            path: "Libraries",
            directoryHint: .isDirectory
        )
        guard fileManager.fileExists(atPath: librariesURL.path) else {
            return []
        }
        let directories = try fileManager.contentsOfDirectory(
            at: librariesURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return directories.compactMap { directoryURL in
            let manifestURL = directoryURL.appending(path: "knowledge-base.json")
            guard let data = try? Data(contentsOf: manifestURL) else {
                return nil
            }
            return try? decoder.decode(KnowledgeBaseSummary.self, from: data)
        }.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func studyItemPackages(in directoryURL: URL) throws -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }
        var packages: [URL] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "studyitem", isRegularDirectory(url) else {
                continue
            }
            packages.append(url)
            enumerator.skipDescendants()
        }
        return packages.sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
    }

    private func loadManifest(at packageURL: URL) throws -> MaterialManifestRecord {
        let manifestURL = packageURL.appending(path: "manifest.json")
        do {
            return try decoder.decode(
                MaterialManifestRecord.self,
                from: Data(contentsOf: manifestURL)
            )
        } catch {
            throw StudyNotesIOSError.malformedManifest(error.localizedDescription)
        }
    }

    private func resolveContentURL(
        in packageURL: URL,
        manifest: MaterialManifestRecord
    ) throws -> URL {
        let contentURL = packageURL.appending(
            path: "content",
            directoryHint: .isDirectory
        )
        let sourceURL = packageURL.appending(
            path: "source",
            directoryHint: .isDirectory
        )
        let preferredNames: [String]
        switch manifest.contentKind {
        case .note, .markdown:
            preferredNames = ["note.md", "content.md", "article.md"]
        case .html, .webArticle:
            preferredNames = ["article.html", "content.html", "index.html"]
        case .pdf:
            preferredNames = ["document.pdf", "source.pdf"]
        case .image:
            preferredNames = ["image.jpg", "image.jpeg", "image.png", "image.heic"]
        case .unknown:
            preferredNames = []
        }
        for name in preferredNames {
            for directory in [contentURL, sourceURL, packageURL] {
                let candidate = directory.appending(path: name)
                if fileManager.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
        }
        for directory in [contentURL, sourceURL] {
            guard let files = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            let matching = files.first {
                ["md", "html", "pdf", "png", "jpg", "jpeg", "heic"].contains(
                    $0.pathExtension.lowercased()
                )
            }
            if let matching {
                return matching
            }
        }
        let renderedURL = packageURL.appending(path: "rendered.html")
        if fileManager.fileExists(atPath: renderedURL.path) {
            return renderedURL
        }
        throw StudyNotesIOSError.unreadableContent
    }

    private func accessState(for packageURL: URL) -> MaterialAccessState {
        let materialID = UUID(uuidString: packageURL.deletingPathExtension().lastPathComponent)
        if let materialID,
           fileManager.fileExists(atPath: offlinePackageURL(for: materialID).path) {
            return .offline
        }
        if let materialID,
           fileManager.fileExists(atPath: onDemandPackageURL(for: materialID).path) {
            return .downloaded
        }
        guard let values = try? packageURL.resourceValues(
            forKeys: [
                .isUbiquitousItemKey,
                .ubiquitousItemDownloadingStatusKey
            ]
        ), values.isUbiquitousItem == true else {
            return .downloaded
        }
        if packageContentIsDownloaded(at: packageURL) {
            return .downloaded
        }
        return .metadataOnly
    }

    private func downloadUbiquitousPackage(at packageURL: URL) async throws {
        for fileURL in downloadableFiles(at: packageURL) {
            try? fileManager.startDownloadingUbiquitousItem(at: fileURL)
        }

        for _ in 0..<60 {
            if packageContentIsDownloaded(at: packageURL) {
                return
            }
            if !fileManager.fileExists(atPath: packageURL.path) {
                throw StudyNotesIOSError.materialNotFound
            }
            for fileURL in downloadableFiles(at: packageURL) {
                try? fileManager.startDownloadingUbiquitousItem(at: fileURL)
            }
            try await Task.sleep(for: .milliseconds(500))
        }
        if packageContentIsDownloaded(at: packageURL) {
            return
        }
        throw StudyNotesIOSError.unreadableContent
    }

    private func packageContentIsDownloaded(at packageURL: URL) -> Bool {
        let files = downloadableFiles(at: packageURL)
        guard !files.isEmpty else {
            return false
        }
        return files.allSatisfy { fileURL in
            guard let values = try? fileURL.resourceValues(
                forKeys: [
                    .isUbiquitousItemKey,
                    .ubiquitousItemDownloadingStatusKey
                ]
            ), values.isUbiquitousItem == true else {
                return true
            }
            switch values.ubiquitousItemDownloadingStatus {
            case .current, .downloaded:
                return true
            default:
                return false
            }
        }
    }

    private func downloadableFiles(at packageURL: URL) -> [URL] {
        var files: [URL] = []
        for relativeDirectory in ["content", "source"] {
            let directoryURL = packageURL.appending(
                path: relativeDirectory,
                directoryHint: .isDirectory
            )
            guard let enumerator = fileManager.enumerator(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for case let fileURL as URL in enumerator {
                if (try? fileURL.resourceValues(
                    forKeys: [.isRegularFileKey]
                ).isRegularFile) == true {
                    files.append(fileURL)
                }
            }
        }
        let manifestURL = packageURL.appending(path: "manifest.json")
        if fileManager.fileExists(atPath: manifestURL.path) {
            files.append(manifestURL)
        }
        return files
    }

    private func replaceCopy(from sourceURL: URL, to destinationURL: URL) throws {
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    private func writeAnnotation(
        _ annotation: StudyAnnotation,
        materialID: UUID
    ) throws {
        let data = try encoder.encode(annotation)
        var wrote = false
        var firstError: Error?
        for packageURL in candidatePackages(for: materialID) {
            let destinationURL = packageURL
                .appending(path: "annotations", directoryHint: .isDirectory)
                .appending(path: "\(annotation.id.uuidString).json")
            do {
                try StudyNotesFileSupport.writeAtomically(data, to: destinationURL)
                wrote = true
            } catch {
                firstError = firstError ?? error
            }
        }
        guard wrote else {
            throw firstError ?? StudyNotesIOSError.materialNotDownloaded
        }
    }

    private func preserveUnreadableArtifact(
        at fileURL: URL,
        data: Data? = nil,
        packageURL: URL,
        layer: String,
        reason: String
    ) {
        let conflictDirectory = packageURL
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

    private func candidatePackages(for materialID: UUID) -> [URL] {
        var packages: [URL] = []
        let offlineURL = offlinePackageURL(for: materialID)
        let onDemandURL = onDemandPackageURL(for: materialID)
        if fileManager.fileExists(atPath: offlineURL.path) {
            packages.append(offlineURL)
        }
        if fileManager.fileExists(atPath: onDemandURL.path) {
            packages.append(onDemandURL)
        }
        if let rootPackage = try? locatePackage(materialID: materialID) {
            packages.append(rootPackage)
        }
        return packages
    }

    private func readPackageURL(for materialID: UUID) -> URL? {
        let offlineURL = offlinePackageURL(for: materialID)
        if fileManager.fileExists(atPath: offlineURL.path) {
            return offlineURL
        }
        let onDemandURL = onDemandPackageURL(for: materialID)
        if fileManager.fileExists(atPath: onDemandURL.path) {
            return onDemandURL
        }
        return try? locatePackage(materialID: materialID)
    }

    private func locatePackage(materialID: UUID) throws -> URL? {
        let librariesURL = rootURL.appending(
            path: "Libraries",
            directoryHint: .isDirectory
        )
        guard fileManager.fileExists(atPath: librariesURL.path) else {
            return nil
        }
        let directories = try fileManager.contentsOfDirectory(
            at: librariesURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for libraryURL in directories {
            for packageURL in try studyItemPackages(in: libraryURL) {
                guard let manifest = try? loadManifest(at: packageURL),
                      manifest.id == materialID else {
                    continue
                }
                return packageURL
            }
        }
        return nil
    }

    private func offlinePackageURL(for materialID: UUID) -> URL {
        offlineRootURL.appending(
            path: "\(materialID.uuidString).studyitem",
            directoryHint: .isDirectory
        )
    }

    private func onDemandPackageURL(for materialID: UUID) -> URL {
        onDemandRootURL.appending(
            path: "\(materialID.uuidString).studyitem",
            directoryHint: .isDirectory
        )
    }

    private func isRegularDirectory(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        ) else {
            return false
        }
        return values.isDirectory == true && values.isSymbolicLink != true
    }

    private func flushPendingMutations() throws -> Int {
        // Mutations are written to every available package copy. The hook is kept
        // explicit so a later conflict queue can be added without changing callers.
        0
    }
}
