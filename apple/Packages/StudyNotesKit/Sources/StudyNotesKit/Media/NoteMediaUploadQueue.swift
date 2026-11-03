import Foundation

public enum NoteMediaUploadState: Equatable, Sendable {
    case waiting
    case uploading(progress: Double)
    case failed(message: String)
    case cancelled
    case uploaded
}

extension NoteMediaUploadState: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case progress
        case message
    }

    private enum Kind: String, Codable {
        case waiting
        case uploading
        case failed
        case cancelled
        case uploaded
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .waiting:
            self = .waiting
        case .uploading:
            let progress = try container.decode(
                Double.self,
                forKey: .progress
            )
            guard (0...1).contains(progress) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .progress,
                    in: container,
                    debugDescription: "Upload progress must be between 0 and 1."
                )
            }
            self = .uploading(progress: progress)
        case .failed:
            self = .failed(
                message: try container.decode(String.self, forKey: .message)
            )
        case .cancelled:
            self = .cancelled
        case .uploaded:
            self = .uploaded
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .waiting:
            try container.encode(Kind.waiting, forKey: .kind)
        case .uploading(let progress):
            try container.encode(Kind.uploading, forKey: .kind)
            try container.encode(progress, forKey: .progress)
        case .failed(let message):
            try container.encode(Kind.failed, forKey: .kind)
            try container.encode(message, forKey: .message)
        case .cancelled:
            try container.encode(Kind.cancelled, forKey: .kind)
        case .uploaded:
            try container.encode(Kind.uploaded, forKey: .kind)
        }
    }
}

public struct NoteMediaUploadItem:
    Codable,
    Equatable,
    Identifiable,
    Sendable {
    public let id: UUID
    public let reference: NoteMediaReference
    public let contentHash: String
    public let contentType: String
    public let byteCount: Int
    public let sourceFileName: String
    public let queueFileName: String
    public internal(set) var state: NoteMediaUploadState
}

public enum NoteMediaUploadQueueError:
    Error,
    Equatable,
    Sendable,
    LocalizedError {
    case itemNotFound
    case invalidTransition
    case invalidProgress
    case contentChanged
    case contentTypeMismatch

    public var errorDescription: String? {
        switch self {
        case .itemNotFound:
            "找不到媒体上传任务。"
        case .invalidTransition:
            "当前媒体上传状态不允许此操作。"
        case .invalidProgress:
            "上传进度必须在 0 到 1 之间。"
        case .contentChanged:
            "媒体文件在复制期间发生变化。"
        case .contentTypeMismatch:
            "相同内容已使用不同的媒体类型登记。"
        }
    }
}

public actor NoteMediaUploadQueue {
    private let queueDirectory: URL
    private let manifestURL: URL
    private var storedItems: [NoteMediaUploadItem]

    public init(applicationSupportRoot: URL) throws {
        let root = applicationSupportRoot.standardizedFileURL
        queueDirectory = root.appending(
            path: "NoteMediaUploadQueue",
            directoryHint: .isDirectory
        )
        manifestURL = queueDirectory.appending(path: "queue.json")
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: queueDirectory,
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: manifestURL.path) {
            let data = try Data(contentsOf: manifestURL)
            storedItems = try JSONDecoder().decode(
                [NoteMediaUploadItem].self,
                from: data
            )
        } else {
            storedItems = []
        }
        var resetInterruptedUploads = false
        for index in storedItems.indices {
            if case .uploading = storedItems[index].state {
                storedItems[index].state = .waiting
                resetInterruptedUploads = true
            }
        }
        if resetInterruptedUploads {
            try Self.persist(storedItems, to: manifestURL)
        }
    }

    public func items() -> [NoteMediaUploadItem] {
        storedItems
    }

    public func item(id: UUID) -> NoteMediaUploadItem? {
        storedItems.first { $0.id == id }
    }

    public func localFileURL(for id: UUID) -> URL? {
        guard let item = item(id: id),
              item.queueFileName == URL(
                  fileURLWithPath: item.queueFileName
              ).lastPathComponent,
              !item.queueFileName.contains("..") else {
            return nil
        }
        let url = queueDirectory.appending(path: item.queueFileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    public func enqueue(
        fileAt sourceURL: URL,
        contentType: String
    ) throws -> NoteMediaUploadItem {
        let attributes = try FileManager.default.attributesOfItem(
            atPath: sourceURL.path
        )
        guard let size = attributes[.size] as? NSNumber else {
            throw CocoaError(.fileReadUnknown)
        }
        let byteCount = size.intValue
        try NoteMediaPolicy.validate(byteCount: byteCount)
        let data = try Data(contentsOf: sourceURL)
        guard data.count == byteCount else {
            throw NoteMediaUploadQueueError.contentChanged
        }
        let digest = ContentFingerprint.sha256(data)
        let contentHash = "sha256:\(digest)"
        let contentType = contentType
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if let existing = storedItems.first(
            where: { $0.contentHash == contentHash }
        ) {
            guard existing.contentType == contentType else {
                throw NoteMediaUploadQueueError.contentTypeMismatch
            }
            let existingURL = queueDirectory.appending(
                path: existing.queueFileName
            )
            if !queueFileMatches(
                at: existingURL,
                byteCount: byteCount,
                digest: digest
            ) {
                try restoreQueueFile(
                    existing: existing,
                    sourceURL: sourceURL,
                    expectedDigest: digest,
                    expectedSize: byteCount
                )
                guard let restored = item(id: existing.id) else {
                    throw NoteMediaUploadQueueError.itemNotFound
                }
                return restored
            }
            return existing
        }

        let fileExtension = resolvedFileExtension(
            contentType: contentType
        )
        let reference = try NoteMediaReference.make(
            data: data,
            fileExtension: fileExtension
        )
        let id = UUID()
        let queueFileName = "\(id.uuidString.lowercased()).\(fileExtension)"
        let temporaryURL = queueDirectory.appending(
            path: ".\(id.uuidString.lowercased()).tmp"
        )
        let destinationURL = queueDirectory.appending(path: queueFileName)

        do {
            try FileManager.default.copyItem(
                at: sourceURL,
                to: temporaryURL
            )
            let copiedData = try Data(contentsOf: temporaryURL)
            guard copiedData.count == byteCount,
                  ContentFingerprint.sha256(copiedData) == digest else {
                throw NoteMediaUploadQueueError.contentChanged
            }
            try FileManager.default.moveItem(
                at: temporaryURL,
                to: destinationURL
            )
            let item = NoteMediaUploadItem(
                id: id,
                reference: reference,
                contentHash: contentHash,
                contentType: contentType,
                byteCount: byteCount,
                sourceFileName: sourceURL.lastPathComponent,
                queueFileName: queueFileName,
                state: .waiting
            )
            storedItems.append(item)
            do {
                try persist()
            } catch {
                storedItems.removeAll { $0.id == id }
                try? FileManager.default.removeItem(at: destinationURL)
                throw error
            }
            return item
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
    }

    public func updateProgress(id: UUID, progress: Double) throws {
        guard (0...1).contains(progress) else {
            throw NoteMediaUploadQueueError.invalidProgress
        }
        try update(id: id) { item in
            switch item.state {
            case .waiting, .uploading:
                item.state = .uploading(progress: progress)
            case .failed, .cancelled, .uploaded:
                throw NoteMediaUploadQueueError.invalidTransition
            }
        }
    }

    public func markFailed(id: UUID, message: String) throws {
        try update(id: id) { item in
            switch item.state {
            case .waiting, .uploading:
                item.state = .failed(message: message)
            case .failed, .cancelled, .uploaded:
                throw NoteMediaUploadQueueError.invalidTransition
            }
        }
    }

    public func retry(id: UUID) throws {
        try update(id: id) { item in
            switch item.state {
            case .failed, .cancelled:
                item.state = .waiting
            case .waiting, .uploading, .uploaded:
                throw NoteMediaUploadQueueError.invalidTransition
            }
        }
    }

    public func cancel(id: UUID) throws {
        try update(id: id) { item in
            switch item.state {
            case .waiting, .uploading, .failed:
                item.state = .cancelled
            case .cancelled, .uploaded:
                throw NoteMediaUploadQueueError.invalidTransition
            }
        }
    }

    public func markUploaded(id: UUID) throws {
        try update(id: id) { item in
            switch item.state {
            case .waiting, .uploading, .failed:
                item.state = .uploaded
            case .cancelled, .uploaded:
                throw NoteMediaUploadQueueError.invalidTransition
            }
        }
    }

    private func update(
        id: UUID,
        change: (inout NoteMediaUploadItem) throws -> Void
    ) throws {
        guard let index = storedItems.firstIndex(
            where: { $0.id == id }
        ) else {
            throw NoteMediaUploadQueueError.itemNotFound
        }
        let previous = storedItems
        try change(&storedItems[index])
        do {
            try persist()
        } catch {
            storedItems = previous
            throw error
        }
    }

    private func persist() throws {
        try Self.persist(storedItems, to: manifestURL)
    }

    private static func persist(
        _ items: [NoteMediaUploadItem],
        to url: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(items)
        try data.write(to: url, options: .atomic)
    }

    private func resolvedFileExtension(
        contentType: String
    ) -> String {
        NoteMediaPolicy.objectKeyFileExtension(
            forContentType: contentType
        )
    }

    private func restoreQueueFile(
        existing: NoteMediaUploadItem,
        sourceURL: URL,
        expectedDigest: String,
        expectedSize: Int
    ) throws {
        let fileName = existing.queueFileName
        guard fileName == URL(fileURLWithPath: fileName).lastPathComponent,
              !fileName.contains("..") else {
            throw NoteMediaUploadQueueError.itemNotFound
        }
        let destinationURL = queueDirectory.appending(
            path: fileName
        )
        let temporaryURL = queueDirectory.appending(
            path: ".\(UUID().uuidString.lowercased()).tmp"
        )
        let previous = storedItems
        do {
            try FileManager.default.copyItem(
                at: sourceURL,
                to: temporaryURL
            )
            let copiedData = try Data(contentsOf: temporaryURL)
            guard copiedData.count == expectedSize,
                  ContentFingerprint.sha256(copiedData) == expectedDigest else {
                throw NoteMediaUploadQueueError.contentChanged
            }
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(
                at: temporaryURL,
                to: destinationURL
            )
            guard let index = storedItems.firstIndex(
                where: { $0.id == existing.id }
            ) else {
                throw NoteMediaUploadQueueError.itemNotFound
            }
            storedItems[index].state = .waiting
            do {
                try persist()
            } catch {
                storedItems = previous
                try? FileManager.default.removeItem(at: destinationURL)
                throw error
            }
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
    }

    private func queueFileMatches(
        at url: URL,
        byteCount: Int,
        digest: String
    ) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path),
              let attributes = try? FileManager.default.attributesOfItem(
                  atPath: url.path
              ),
              let size = attributes[.size] as? NSNumber,
              size.intValue == byteCount,
              let data = try? Data(contentsOf: url) else {
            return false
        }
        return ContentFingerprint.sha256(data) == digest
    }
}
