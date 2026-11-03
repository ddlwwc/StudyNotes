import Foundation

public enum NoteMediaCacheError:
    Error,
    Equatable,
    Sendable,
    LocalizedError {
    case contentHashMismatch

    public var errorDescription: String? {
        "缓存内容与媒体对象键不匹配。"
    }
}

public actor NoteMediaCache {
    private let cacheDirectory: URL

    public init(applicationSupportRoot: URL) throws {
        cacheDirectory = applicationSupportRoot
            .standardizedFileURL
            .appending(path: "NoteMediaCache", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )
    }

    public func data(
        for reference: NoteMediaReference
    ) throws -> Data? {
        let url = fileURL(for: reference)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return try Data(contentsOf: url)
    }

    public func write(
        _ data: Data,
        for reference: NoteMediaReference
    ) throws {
        try NoteMediaPolicy.validate(byteCount: data.count)
        let digest = ContentFingerprint.sha256(data)
        let fileName = reference.objectKey.split(separator: "/").last ?? ""
        let objectHash = fileName.split(separator: ".").first ?? ""
        guard objectHash == digest.prefix(
            NoteMediaReference.hashPrefixLength
        ) else {
            throw NoteMediaCacheError.contentHashMismatch
        }
        let url = fileURL(for: reference)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    public func size() throws -> Int {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: cacheDirectory,
            includingPropertiesForKeys: keys
        ) else {
            return 0
        }
        var total = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isRegularFile == true {
                total += values.fileSize ?? 0
            }
        }
        return total
    }

    public func clear() throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: cacheDirectory.path) {
            try fileManager.removeItem(at: cacheDirectory)
        }
        try fileManager.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )
    }

    public func fileURL(for reference: NoteMediaReference) -> URL {
        reference.objectKey.split(separator: "/").reduce(cacheDirectory) {
            $0.appending(path: String($1))
        }
    }
}
