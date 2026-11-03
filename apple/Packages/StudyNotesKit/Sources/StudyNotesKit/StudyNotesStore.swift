import Foundation

public enum StudyNotesError: Error, Equatable, Sendable, LocalizedError {
    case knowledgeBaseNotFound
    case malformedMaterialPackage
    case materialNotFound
    case unsupportedSchemaVersion(Int)
    case fileCoordinationFailed

    public var errorDescription: String? {
        switch self {
        case .knowledgeBaseNotFound:
            "没有找到对应的知识库。"
        case .malformedMaterialPackage:
            "学习材料包已损坏或缺少必要文件。"
        case .materialNotFound:
            "没有找到对应的学习材料。"
        case .unsupportedSchemaVersion(let version):
            "学习材料包使用了不受支持的格式版本：\(version)。"
        case .fileCoordinationFailed:
            "无法协调文件访问，请稍后重试。"
        }
    }
}

public actor StudyNotesStore {
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
        try prepareLibraryDirectories(at: rootURL)

        let knowledgeBase = KnowledgeBase(
            id: UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: Date()
        )
        let temporaryURL = librariesURL(at: rootURL).appending(
            path: ".tmp-\(knowledgeBase.id.uuidString)",
            directoryHint: .isDirectory
        )
        let destinationURL = knowledgeBaseURL(id: knowledgeBase.id, rootURL: rootURL)

        try coordinatedWrite(at: librariesURL(at: rootURL)) {
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
        }

        return knowledgeBase
    }

    public func createMarkdownNote(
        title: String,
        in knowledgeBaseID: UUID,
        markdown: String
    ) throws -> MarkdownNote {
        let rootURL = try availableRootURL()
        let knowledgeBaseURL = knowledgeBaseURL(id: knowledgeBaseID, rootURL: rootURL)

        guard fileManager.fileExists(atPath: knowledgeBaseURL.path) else {
            throw StudyNotesError.knowledgeBaseNotFound
        }

        let now = Date()
        let materialID = UUID()
        let manifest = MaterialManifest(
            schemaVersion: StudyNotesKit.schemaVersion,
            id: materialID,
            knowledgeBaseID: knowledgeBaseID,
            kind: .note,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: now,
            updatedAt: now
        )
        let packageName = "\(materialID.uuidString).studyitem"
        let temporaryURL = knowledgeBaseURL.appending(
            path: ".tmp-\(materialID.uuidString)",
            directoryHint: .isDirectory
        )
        let destinationURL = knowledgeBaseURL.appending(
            path: packageName,
            directoryHint: .isDirectory
        )
        let contentURL = temporaryURL
            .appending(path: "content", directoryHint: .isDirectory)
            .appending(path: "note.md")

        try coordinatedWrite(at: knowledgeBaseURL) {
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
        }

        return MarkdownNote(
            summary: manifest.summary(conflictCopies: []),
            markdown: markdown
        )
    }

    public func loadIndex() throws -> LibraryIndex {
        let rootURL = try availableRootURL()
        try prepareLibraryDirectories(at: rootURL)

        return try coordinatedRead(at: rootURL) {
            let knowledgeBases = try loadKnowledgeBases(rootURL: rootURL)
            var materials: [StudyMaterialSummary] = []

            for knowledgeBase in knowledgeBases {
                materials.append(
                    contentsOf: try loadMaterials(in: knowledgeBase.id, rootURL: rootURL)
                )
            }

            return LibraryIndex(
                knowledgeBases: knowledgeBases,
                materials: materials.sorted {
                    if $0.updatedAt == $1.updatedAt {
                        return $0.title.localizedStandardCompare($1.title) == .orderedAscending
                    }
                    return $0.updatedAt > $1.updatedAt
                }
            )
        }
    }

    public func loadMarkdownNote(id: UUID) throws -> MarkdownNote {
        let rootURL = try availableRootURL()
        return try coordinatedRead(at: rootURL) {
            guard let locatedMaterial = try locateMaterial(id: id, rootURL: rootURL) else {
                throw StudyNotesError.materialNotFound
            }

            let packageURLs = try fileManager.contentsOfDirectory(
                at: locatedMaterial.packageURL.deletingLastPathComponent(),
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            let conflictCopiesByMaterialID = try loadConflictCopies(
                from: packageURLs.filter {
                    $0.pathExtension == "studyitem" && isConflictCopy($0)
                }
            )
            let markdownURL = locatedMaterial.packageURL
                .appending(path: "content", directoryHint: .isDirectory)
                .appending(path: "note.md")
            let markdown = try String(contentsOf: markdownURL, encoding: .utf8)
            let conflictCopies = (conflictCopiesByMaterialID[id] ?? [])
                + nestedConflictCopies(in: locatedMaterial.packageURL)

            return MarkdownNote(
                summary: locatedMaterial.manifest.summary(
                    conflictCopies: conflictCopies
                ),
                markdown: markdown
            )
        }
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

    private func prepareLibraryDirectories(at rootURL: URL) throws {
        let librariesURL = librariesURL(at: rootURL)
        try coordinatedWrite(at: rootURL) {
            try fileManager.createDirectory(
                at: librariesURL,
                withIntermediateDirectories: true
            )
        }
    }

    private func loadKnowledgeBases(rootURL: URL) throws -> [KnowledgeBase] {
        let directoryURLs = try fileManager.contentsOfDirectory(
            at: librariesURL(at: rootURL),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        return try directoryURLs
            .filter { $0.pathExtension.isEmpty }
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

    private func loadMaterials(
        in knowledgeBaseID: UUID,
        rootURL: URL
    ) throws -> [StudyMaterialSummary] {
        let knowledgeBaseURL = knowledgeBaseURL(id: knowledgeBaseID, rootURL: rootURL)
        let packageURLs = try fileManager.contentsOfDirectory(
            at: knowledgeBaseURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        let regularPackageURLs = packageURLs.filter {
            $0.pathExtension == "studyitem" && !isConflictCopy($0)
        }
        let conflictCopiesByMaterialID = try loadConflictCopies(
            from: packageURLs.filter {
                $0.pathExtension == "studyitem" && isConflictCopy($0)
            }
        )

        return try regularPackageURLs
            .map { packageURL in
                let manifest = try loadManifest(from: packageURL)
                let conflictCopies = (conflictCopiesByMaterialID[manifest.id] ?? [])
                    + nestedConflictCopies(in: packageURL)
                return manifest.summary(
                    conflictCopies: conflictCopies
                )
            }
    }

    private func locateMaterial(id: UUID, rootURL: URL) throws -> LocatedMaterial? {
        for knowledgeBase in try loadKnowledgeBases(rootURL: rootURL) {
            let knowledgeBaseURL = knowledgeBaseURL(
                id: knowledgeBase.id,
                rootURL: rootURL
            )
            let packageURLs = try fileManager.contentsOfDirectory(
                at: knowledgeBaseURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )

            for packageURL in packageURLs where
                packageURL.pathExtension == "studyitem" && !isConflictCopy(packageURL)
            {
                let manifest = try loadManifest(from: packageURL)
                guard manifest.id == id else { continue }
                return LocatedMaterial(packageURL: packageURL, manifest: manifest)
            }
        }

        return nil
    }

    private func loadConflictCopies(
        from packageURLs: [URL]
    ) throws -> [UUID: [ConflictCopy]] {
        var copiesByMaterialID: [UUID: [ConflictCopy]] = [:]

        for packageURL in packageURLs {
            guard let materialID = materialID(forConflictCopyAt: packageURL) else {
                continue
            }
            let relativePath = packageURL.lastPathComponent
            let conflictCopy = ConflictCopy(
                id: relativePath,
                displayName: packageURL.deletingPathExtension().lastPathComponent,
                relativePath: relativePath
            )
            copiesByMaterialID[materialID, default: []].append(conflictCopy)
        }

        return copiesByMaterialID.mapValues {
            $0.sorted {
                $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
            }
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

    private func isConflictCopy(_ packageURL: URL) -> Bool {
        let name = packageURL.lastPathComponent.lowercased()
        return name.contains("conflicted copy") || name.contains("conflict")
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

    private func knowledgeBaseURL(id: UUID, rootURL: URL) -> URL {
        librariesURL(at: rootURL).appending(path: id.uuidString, directoryHint: .isDirectory)
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
    let knowledgeBaseID: UUID
    let kind: StudyMaterialKind
    let title: String
    let createdAt: Date
    let updatedAt: Date

    func summary(conflictCopies: [ConflictCopy]) -> StudyMaterialSummary {
        StudyMaterialSummary(
            id: id,
            knowledgeBaseID: knowledgeBaseID,
            kind: kind,
            title: title,
            updatedAt: updatedAt,
            conflictCopies: conflictCopies
        )
    }
}

private struct LocatedMaterial {
    let packageURL: URL
    let manifest: MaterialManifest
}
