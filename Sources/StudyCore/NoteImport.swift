import Foundation

public enum NoteImport {
    public enum Decision: Equatable, Sendable {
        case write(targetName: String)
        case skip(reason: String)
    }

    public static func decide(
        sourceName: String,
        content: String,
        existingNames: Set<String>
    ) -> Decision {
        let stem: String
        if let dot = sourceName.lastIndex(of: "."), dot > sourceName.startIndex {
            stem = String(sourceName[sourceName.startIndex..<dot])
        } else if let dot = sourceName.lastIndex(of: "."), dot == sourceName.startIndex {
            stem = ""
        } else {
            stem = sourceName
        }
        let trimmedBase = stem.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedBase.isEmpty else {
            return .skip(reason: "文件名是空的")
        }
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .skip(reason: "文件是空的")
        }

        let candidate = "\(trimmedBase).md"
        if existingNames.contains(candidate) {
            return .skip(reason: "已存在同名笔记")
        }
        return .write(targetName: candidate)
    }

    public static func sanitizedName(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = name.components(separatedBy: illegal).joined(separator: "-")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未命名" : trimmed
    }
}
