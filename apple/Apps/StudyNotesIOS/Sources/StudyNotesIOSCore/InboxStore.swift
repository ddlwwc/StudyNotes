import Foundation

public actor InboxStore {
    private let rootURL: URL
    private let pendingRootURL: URL
    private let fileManager: FileManager
    private let encoder = StudyNotesFileSupport.encoder()
    private let decoder = StudyNotesFileSupport.decoder()

    public init(
        rootURL: URL,
        fileManager: FileManager = .default
    ) throws {
        self.rootURL = rootURL
        self.fileManager = fileManager
        let support = try StudyNotesFileSupport.applicationSupportDirectory(
            fileManager: fileManager
        )
        self.pendingRootURL = support.appending(
            path: "InboxPending",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(
            at: pendingRootURL,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: rootURL.appending(path: "Inbox", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
    }

    public func listItems() throws -> [InboxItem] {
        var items = try readItems(
            in: inboxURL,
            extension: "inboxitem",
            status: .collected
        )
        let pendingItems = try readItems(
            in: pendingRootURL,
            extension: "pending",
            status: .pending
        )
        let deliveredIDs = Set(items.map(\.id))
        for pending in pendingItems where !deliveredIDs.contains(pending.id) {
            items.append(pending)
        }
        return items.sorted { $0.createdAt > $1.createdAt }
    }

    public func collect(_ draft: InboxDraft) async throws -> InboxItem {
        let pendingURL = try persistPending(draft)
        do {
            try deliverPending(at: pendingURL, draft: draft)
            try fileManager.removeItem(at: pendingURL)
            return item(from: draft, status: .collected, payloadURL: nil)
        } catch {
            return item(
                from: draft,
                status: .failed(error.localizedDescription),
                payloadURL: pendingURL
            )
        }
    }

    public func retry(itemID: UUID) async throws -> InboxItem {
        guard let pendingURL = try pendingItemURL(id: itemID) else {
            throw StudyNotesIOSError.inboxWriteFailed("没有可重试的本地收件箱草稿。")
        }
        let manifest = try readManifest(
            at: pendingURL.appending(path: "manifest.json")
        )
        let draft = InboxDraft(
            id: manifest.id,
            kind: manifest.kind,
            title: manifest.title,
            payloadFileExtension: URL(fileURLWithPath: manifest.payloadFile).pathExtension,
            payloadData: try Data(
                contentsOf: pendingURL.appending(path: manifest.payloadFile)
            ),
            source: manifest.source,
            createdAt: manifest.createdAt
        )
        do {
            try deliverPending(at: pendingURL, draft: draft)
            try fileManager.removeItem(at: pendingURL)
            return item(from: draft, status: .collected, payloadURL: nil)
        } catch {
            return item(
                from: draft,
                status: .failed(error.localizedDescription),
                payloadURL: pendingURL
            )
        }
    }

    public func discardPending(itemID: UUID) throws {
        if let pendingURL = try pendingItemURL(id: itemID) {
            try fileManager.removeItem(at: pendingURL)
        }
    }

    private var inboxURL: URL {
        rootURL.appending(path: "Inbox", directoryHint: .isDirectory)
    }

    private func persistPending(_ draft: InboxDraft) throws -> URL {
        let destinationURL = pendingRootURL.appending(
            path: "\(draft.id.uuidString).pending",
            directoryHint: .isDirectory
        )
        let temporaryURL = pendingRootURL.appending(
            path: ".tmp-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(
            at: temporaryURL,
            withIntermediateDirectories: false
        )
        do {
            let payloadName = "payload.\(draft.payloadFileExtension)"
            let manifest = InboxManifest(
                id: draft.id,
                kind: draft.kind,
                title: draft.title,
                createdAt: draft.createdAt,
                payloadFile: payloadName,
                source: draft.source
            )
            try encoder.encode(manifest).write(
                to: temporaryURL.appending(path: "manifest.json"),
                options: .atomic
            )
            try draft.payloadData.write(
                to: temporaryURL.appending(path: payloadName),
                options: .atomic
            )
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            return destinationURL
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw StudyNotesIOSError.inboxWriteFailed(error.localizedDescription)
        }
    }

    private func deliverPending(at pendingURL: URL, draft: InboxDraft) throws {
        guard fileManager.fileExists(
            atPath: pendingURL.appending(path: "manifest.json").path
        ) else {
            throw StudyNotesIOSError.inboxWriteFailed("本地草稿缺少 manifest.json。")
        }
        let temporaryURL = inboxURL.appending(
            path: ".tmp-\(draft.id.uuidString)",
            directoryHint: .isDirectory
        )
        let destinationURL = inboxURL.appending(
            path: "\(draft.id.uuidString).inboxitem",
            directoryHint: .isDirectory
        )
        try? fileManager.removeItem(at: temporaryURL)
        do {
            try fileManager.copyItem(at: pendingURL, to: temporaryURL)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw StudyNotesIOSError.inboxWriteFailed(error.localizedDescription)
        }
    }

    private func readItems(
        in directoryURL: URL,
        extension pathExtension: String,
        status: InboxItem.Status
    ) throws -> [InboxItem] {
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return []
        }
        let directories = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return directories.compactMap { directory in
            guard directory.pathExtension == pathExtension else {
                return nil
            }
            let manifestURL = directory.appending(path: "manifest.json")
            guard let manifest = try? readManifest(at: manifestURL) else {
                return nil
            }
            return InboxItem(
                id: manifest.id,
                kind: manifest.kind,
                title: manifest.title,
                createdAt: manifest.createdAt,
                status: status,
                localPayloadURL: status == .pending
                    ? directory.appending(path: manifest.payloadFile)
                    : nil
            )
        }
    }

    private func readManifest(at url: URL) throws -> InboxManifest {
        try decoder.decode(InboxManifest.self, from: Data(contentsOf: url))
    }

    private func item(
        from draft: InboxDraft,
        status: InboxItem.Status,
        payloadURL: URL?
    ) -> InboxItem {
        InboxItem(
            id: draft.id,
            kind: draft.kind,
            title: draft.title,
            createdAt: draft.createdAt,
            status: status,
            localPayloadURL: payloadURL
        )
    }

    private func pendingItemURL(id: UUID) throws -> URL? {
        let directories = try fileManager.contentsOfDirectory(
            at: pendingRootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return directories.first {
            $0.pathExtension == "pending"
                && UUID(uuidString: $0.deletingPathExtension().lastPathComponent) == id
        }
    }
}
