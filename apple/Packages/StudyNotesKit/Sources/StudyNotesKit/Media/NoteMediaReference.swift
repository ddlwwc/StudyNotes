import CryptoKit
import Foundation

public enum NoteMediaReferenceError:
    Error,
    Equatable,
    Sendable,
    LocalizedError {
    case invalidReference
    case invalidObjectKey
    case invalidExtension

    public var errorDescription: String? {
        switch self {
        case .invalidReference:
            "媒体引用必须是 media://qiniu/library-media/...。"
        case .invalidObjectKey:
            "媒体对象键必须位于 library-media 内容寻址命名空间。"
        case .invalidExtension:
            "媒体文件扩展名无效。"
        }
    }
}

public struct NoteMediaReference: Codable, Hashable, Sendable {
    public static let scheme = "media"
    public static let host = "qiniu"
    public static let objectPrefix = "library-media/"
    public static let hashPrefixLength = 64

    public let objectKey: String

    public var stringValue: String {
        "\(Self.scheme)://\(Self.host)/\(objectKey)"
    }

    public init(objectKey: String) throws {
        guard Self.isValidObjectKey(objectKey) else {
            throw NoteMediaReferenceError.invalidObjectKey
        }
        self.objectKey = objectKey
    }

    public init(string: String) throws {
        guard !string.contains("%"),
              !string.contains("?"),
              !string.contains("#"),
              !string.contains("\\"),
              string.hasPrefix(
                "\(Self.scheme)://\(Self.host)/\(Self.objectPrefix)"
              ) else {
            throw NoteMediaReferenceError.invalidReference
        }
        let objectKey = String(
            string.dropFirst(
                "\(Self.scheme)://\(Self.host)/".count
            )
        )
        do {
            try self.init(objectKey: objectKey)
        } catch {
            throw NoteMediaReferenceError.invalidReference
        }
    }

    private enum CodingKeys: String, CodingKey {
        case objectKey
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let objectKey = try container.decode(String.self, forKey: .objectKey)
        do {
            try self.init(objectKey: objectKey)
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .objectKey,
                in: container,
                debugDescription: "Invalid note media object key."
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(objectKey, forKey: .objectKey)
    }

    public static func make(
        data: Data,
        fileExtension: String
    ) throws -> NoteMediaReference {
        let fileExtension = normalizedExtension(fileExtension)
        guard !fileExtension.isEmpty else {
            throw NoteMediaReferenceError.invalidExtension
        }
        let digest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        let prefix = digest.prefix(hashPrefixLength)
        return try NoteMediaReference(
            objectKey: "\(objectPrefix)\(prefix).\(fileExtension)"
        )
    }

    private static func normalizedExtension(_ value: String) -> String {
        let value = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard (1...8).contains(value.count),
              value.allSatisfy({
                  $0.isASCII && ($0.isLetter || $0.isNumber)
              }) else {
            return ""
        }
        return value
    }

    private static func isValidObjectKey(_ value: String) -> Bool {
        guard value.hasPrefix(objectPrefix),
              !value.contains("%"),
              !value.contains("\\"),
              !value.contains("?"),
              !value.contains("#") else {
            return false
        }
        let components = value.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        guard components.count == 2,
              components[0] == "library-media" else {
            return false
        }
        let fileName = String(components[1])
        guard !fileName.hasPrefix("."),
              !fileName.contains(".."),
              fileName.allSatisfy({
                  $0.isASCII && (
                      $0.isLetter || $0.isNumber || $0 == "-"
                          || $0 == "_" || $0 == "."
                  )
              }),
              let separator = fileName.firstIndex(of: ".") else {
            return false
        }
        let hash = fileName[..<separator]
        let fileExtension = fileName[fileName.index(after: separator)...]
        return hash.count == hashPrefixLength
            && hash.allSatisfy {
                $0.isASCII && ($0.isNumber || ("a"..."f").contains($0))
            }
            && (1...8).contains(fileExtension.count)
            && fileExtension.allSatisfy {
                $0.isASCII && ($0.isNumber || ("a"..."z").contains($0))
            }
    }
}
