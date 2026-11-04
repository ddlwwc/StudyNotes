import Foundation

public enum EditorMarkdownFallbackError: Error, Equatable, Sendable,
    LocalizedError {
    case malformedMarker(String)
    case missingBlock(UUID)
    case unsupportedVersion(UUID, Int)

    public var errorDescription: String? {
        switch self {
        case let .malformedMarker(marker):
            "复杂块标记格式无效：\(marker)"
        case let .missingBlock(id):
            "复杂块 \(id.uuidString) 缺少旁路数据。"
        case let .unsupportedVersion(id, version):
            "复杂块 \(id.uuidString) 使用未知版本 \(version)。"
        }
    }
}

public struct EditorMarkdownFallback: Sendable {
    public init() {}

    public func readableMarkdown(
        _ markdown: String,
        blocks: [EditorBlockEnvelope]
    ) throws -> String {
        let blocksByID = Dictionary(
            uniqueKeysWithValues: blocks.map { ($0.id, $0) }
        )
        let pattern = #"(?s)<!--\s*studynotes:block\s+([^>]*?)-->(.*?)<!--\s*/studynotes:block\s*-->"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return markdown
        }
        let range = NSRange(markdown.startIndex..., in: markdown)
        let matches = regex.matches(in: markdown, range: range)
        var output = ""
        var cursor = markdown.startIndex

        for match in matches {
            guard let wholeRange = Range(match.range, in: markdown),
                  let attributeRange = Range(match.range(at: 1), in: markdown)
            else {
                continue
            }
            output += String(markdown[cursor..<wholeRange.lowerBound])
            let attributes = String(markdown[attributeRange])
            let marker = String(markdown[wholeRange])
            guard let idText = attributeValue("id", in: attributes),
                  let id = UUID(uuidString: idText)
            else {
                throw EditorMarkdownFallbackError.malformedMarker(marker)
            }
            let version = attributeValue("version", in: attributes)
                .flatMap(Int.init)
            guard let block = blocksByID[id] else {
                throw EditorMarkdownFallbackError.missingBlock(id)
            }
            if let version, version != block.version {
                throw EditorMarkdownFallbackError.unsupportedVersion(
                    id,
                    version
                )
            }
            try block.validate()
            output += block.fallback
            if !block.fallback.hasSuffix("\n") {
                output += "\n"
            }
            cursor = wholeRange.upperBound
        }
        output += String(markdown[cursor...])
        return output
    }

    public func packageFiles(
        markdown: String,
        blocks: [EditorBlockEnvelope],
        annotationsJSON: Data?,
        conversationsJSON: Data?
    ) throws -> [String: Data] {
        try blocks.forEach { try $0.validate() }
        var files: [String: Data] = [
            "document.md": Data(markdown.utf8),
            "readable.md": Data(
                try readableMarkdown(markdown, blocks: blocks).utf8
            )
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        files["blocks.json"] = try encoder.encode(blocks)
        if let annotationsJSON {
            files["annotations.json"] = annotationsJSON
        }
        if let conversationsJSON {
            files["ai.json"] = conversationsJSON
        }
        return files
    }

    private func attributeValue(
        _ name: String,
        in attributes: String
    ) -> String? {
        let pattern = #"\b\#(name)\s*=\s*"([^"]*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: attributes,
                range: NSRange(attributes.startIndex..., in: attributes)
              ),
              let range = Range(match.range(at: 1), in: attributes)
        else {
            return nil
        }
        return String(attributes[range])
    }
}
