import Foundation

public enum NoteMediaConnection: String, Codable, Sendable {
    case wifi
    case cellular
    case unknown
}

public enum NoteMediaPolicyError:
    Error,
    Equatable,
    Sendable,
    LocalizedError {
    case emptyFile
    case fileTooLarge

    public var errorDescription: String? {
        switch self {
        case .emptyFile:
            "媒体文件不能为空。"
        case .fileTooLarge:
            "媒体文件不能超过 50MB。"
        }
    }
}

public enum NoteMediaPolicy {
    public static let minimumByteCount = 1
    public static let maximumByteCount = 50 * 1_024 * 1_024
    public static let cellularConfirmationByteCount = 10 * 1_024 * 1_024

    public static func validate(byteCount: Int) throws {
        guard byteCount >= minimumByteCount else {
            throw NoteMediaPolicyError.emptyFile
        }
        guard byteCount <= maximumByteCount else {
            throw NoteMediaPolicyError.fileTooLarge
        }
    }

    public static func requiresCellularConfirmation(
        byteCount: Int,
        connection: NoteMediaConnection
    ) throws -> Bool {
        try validate(byteCount: byteCount)
        return connection == .cellular
            && byteCount > cellularConfirmationByteCount
    }

    public static func contentType(
        forFileExtension fileExtension: String
    ) -> String? {
        contentTypesByExtension[normalized(fileExtension)]
    }

    public static func fileExtension(
        forContentType contentType: String
    ) -> String? {
        let contentType = normalized(
            contentType.split(separator: ";", maxSplits: 1).first.map(String.init)
                ?? contentType
        )
        return fileExtensionsByContentType[contentType]
    }

    public static func objectKeyFileExtension(
        forContentType contentType: String
    ) -> String {
        let contentType = normalized(
            contentType.split(separator: ";", maxSplits: 1)
                .first.map(String.init) ?? contentType
        )
        return serverObjectKeyExtensions[contentType] ?? "bin"
    }

    // Must match the server's library-media object-key extension mapping.
    private static let serverObjectKeyExtensions: [String: String] = [
        "image/png": "png",
        "image/jpeg": "jpg",
        "image/gif": "gif",
        "image/webp": "webp",
        "image/heic": "heic",
        "application/pdf": "pdf",
        "text/plain": "txt",
        "text/markdown": "md",
        "application/zip": "zip"
    ]

    private static let contentTypesByExtension: [String: String] = [
        "png": "image/png",
        "jpg": "image/jpeg",
        "jpeg": "image/jpeg",
        "gif": "image/gif",
        "webp": "image/webp",
        "heic": "image/heic",
        "pdf": "application/pdf",
        "txt": "text/plain",
        "md": "text/markdown",
        "csv": "text/csv",
        "json": "application/json",
        "zip": "application/zip",
        "mp3": "audio/mpeg",
        "m4a": "audio/mp4",
        "mp4": "video/mp4",
        "mov": "video/quicktime",
        "bin": "application/octet-stream"
    ]

    private static let fileExtensionsByContentType: [String: String] = [
        "image/png": "png",
        "image/jpeg": "jpg",
        "image/gif": "gif",
        "image/webp": "webp",
        "image/heic": "heic",
        "application/pdf": "pdf",
        "text/plain": "txt",
        "text/markdown": "md",
        "text/csv": "csv",
        "application/json": "json",
        "application/zip": "zip",
        "audio/mpeg": "mp3",
        "audio/mp4": "m4a",
        "video/mp4": "mp4",
        "video/quicktime": "mov",
        "application/octet-stream": "bin"
    ]

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }
}

public extension NoteMediaReference {
    static func make(
        data: Data,
        contentType: String
    ) throws -> NoteMediaReference {
        let fileExtension = NoteMediaPolicy.objectKeyFileExtension(
            forContentType: contentType
        )
        return try make(data: data, fileExtension: fileExtension)
    }
}
