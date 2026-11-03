import Foundation

public struct MarkdownEditorDocument: Equatable, Sendable {
    public let markdown: String
    public let compatibilityBlocks: [MarkdownCompatibilityBlock]

    public init(
        markdown: String,
        compatibilityBlocks: [MarkdownCompatibilityBlock] = []
    ) {
        self.markdown = markdown
        self.compatibilityBlocks = compatibilityBlocks
    }
}

public struct MarkdownCompatibilityBlock: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case frontMatter
        case rawHTML
        case footnoteReference
        case footnoteDefinition
        case unknownFencedBlock
    }

    public let kind: Kind
    public let source: String
    public let startLine: Int
    public let endLine: Int

    public init(
        kind: Kind,
        source: String,
        startLine: Int,
        endLine: Int
    ) {
        self.kind = kind
        self.source = source
        self.startLine = startLine
        self.endLine = endLine
    }
}

public enum MarkdownEditorCodecError: Error, Equatable, Sendable, LocalizedError {
    case unsupportedControlCharacter(line: Int)
    case invalidFrontMatter(line: Int)
    case unclosedFence(line: Int)
    case lostCompatibilityBlock(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedControlCharacter(let line):
            "第 \(line) 行包含无法无损保存的控制字符。"
        case .invalidFrontMatter(let line):
            "第 \(line) 行开始的 Front Matter 缺少结束分隔线。"
        case .unclosedFence(let line):
            "第 \(line) 行开始的围栏块缺少结束标记。"
        case .lostCompatibilityBlock(let kind):
            "编辑结果缺少兼容内容块：\(kind)。"
        }
    }
}

public struct MarkdownEditorCodec: Sendable {
    public init() {}

    public func decode(_ markdown: String) throws -> MarkdownEditorDocument {
        let normalized = try normalize(markdown)
        let lines = normalized.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).map(String.init)
        var blocks: [MarkdownCompatibilityBlock] = []
        var index = 0

        if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
            guard let closing = lines.indices.dropFirst().first(where: {
                let marker = lines[$0].trimmingCharacters(in: .whitespaces)
                return marker == "---" || marker == "..."
            }) else {
                throw MarkdownEditorCodecError.invalidFrontMatter(line: 1)
            }
            blocks.append(
                block(
                    .frontMatter,
                    lines: lines,
                    start: 0,
                    end: closing
                )
            )
            index = closing + 1
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                index += 1
                continue
            }

            if let fence = fenceStart(trimmed) {
                guard let closing = lines.indices.dropFirst(index + 1).first(where: {
                    isFenceEnd(lines[$0], fence: fence)
                }) else {
                    throw MarkdownEditorCodecError.unclosedFence(line: index + 1)
                }
                if !knownFenceLanguages.contains(fence.language) {
                    blocks.append(
                        block(
                            .unknownFencedBlock,
                            lines: lines,
                            start: index,
                            end: closing
                        )
                    )
                }
                index = closing + 1
                continue
            }

            if let footnote = footnoteDefinitionEnd(in: lines, at: index) {
                blocks.append(
                    block(
                        .footnoteDefinition,
                        lines: lines,
                        start: index,
                        end: footnote
                    )
                )
                index = footnote + 1
                continue
            }

            if startsHTMLBlock(trimmed) {
                var end = index
                while end + 1 < lines.count,
                      !lines[end + 1].trimmingCharacters(in: .whitespaces).isEmpty {
                    end += 1
                }
                blocks.append(
                    block(.rawHTML, lines: lines, start: index, end: end)
                )
                index = end + 1
                continue
            }

            if containsFootnoteReference(line) {
                blocks.append(
                    block(
                        .footnoteReference,
                        lines: lines,
                        start: index,
                        end: index
                    )
                )
            }
            index += 1
        }

        return MarkdownEditorDocument(
            markdown: normalized,
            compatibilityBlocks: blocks
        )
    }

    public func encode(_ document: MarkdownEditorDocument) throws -> String {
        let normalized = try normalize(document.markdown)
        let encodedBlocks = try decode(normalized).compatibilityBlocks
        guard encodedBlocks.count == document.compatibilityBlocks.count else {
            let missingKind = document.compatibilityBlocks.first {
                expected in
                !encodedBlocks.contains(expected)
            }
            throw MarkdownEditorCodecError.lostCompatibilityBlock(
                missingKind?.kind.rawValue ?? "unknown"
            )
        }
        for (expected, encoded) in zip(
            document.compatibilityBlocks,
            encodedBlocks
        ) where expected.kind != encoded.kind
            || expected.source != encoded.source {
            throw MarkdownEditorCodecError.lostCompatibilityBlock(
                expected.kind.rawValue
            )
        }
        return normalized
    }

    public func normalize(_ markdown: String) throws -> String {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        for (offset, line) in normalized.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).enumerated() {
            if line.unicodeScalars.contains(where: {
                $0.value < 0x20 && $0 != "\t" && $0 != "\r" && $0 != "\n"
            }) {
                throw MarkdownEditorCodecError.unsupportedControlCharacter(
                    line: offset + 1
                )
            }
        }
        return normalized
    }
}

struct MarkdownFence {
    let marker: Character
    let count: Int
    let language: String
}

private let knownFenceLanguages: Set<String> = [
    "", "bash", "c", "cpp", "css", "diff", "dockerfile", "go", "html",
    "ini", "java", "javascript", "js", "json", "kotlin", "markdown", "md",
    "objc", "objectivec", "plaintext", "py", "python", "rust", "sh",
    "shell", "sql", "swift", "text", "toml", "ts", "typescript", "xml",
    "yaml", "yml", "zsh"
]

func fenceStart(_ line: String) -> MarkdownFence? {
    guard let marker = line.first, marker == "`" || marker == "~" else {
        return nil
    }
    let count = line.prefix { $0 == marker }.count
    guard count >= 3 else {
        return nil
    }
    let info = line.dropFirst(count).trimmingCharacters(in: .whitespaces)
    let language = info.split(whereSeparator: \.isWhitespace).first
        .map(String.init)?
        .lowercased() ?? ""
    return MarkdownFence(marker: marker, count: count, language: language)
}

func isFenceEnd(_ line: String, fence: MarkdownFence) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    let count = trimmed.prefix { $0 == fence.marker }.count
    return count >= fence.count
        && trimmed.dropFirst(count).allSatisfy(\.isWhitespace)
}

private func footnoteDefinitionEnd(
    in lines: [String],
    at index: Int
) -> Int? {
    let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix("[^"),
          let separator = trimmed.range(of: "]:") else {
        return nil
    }
    let identifier = trimmed[
        trimmed.index(trimmed.startIndex, offsetBy: 2)..<separator.lowerBound
    ]
    guard !identifier.isEmpty,
          !identifier.contains(where: \.isWhitespace) else {
        return nil
    }
    var end = index
    while end + 1 < lines.count {
        let next = lines[end + 1]
        guard !next.trimmingCharacters(in: .whitespaces).isEmpty,
              next.first?.isWhitespace == true else {
            break
        }
        end += 1
    }
    return end
}

private func containsFootnoteReference(_ line: String) -> Bool {
    line.range(
        of: #"\[\^[^\]\s]+\]"#,
        options: .regularExpression
    ) != nil
}

func startsHTMLBlock(_ line: String) -> Bool {
    guard line.hasPrefix("<") else {
        return false
    }
    if line.hasPrefix("<!--")
        || line.hasPrefix("<![CDATA[")
        || line.lowercased().hasPrefix("<!doctype")
        || line.hasPrefix("<?") {
        return true
    }
    var characters = line.dropFirst()
    if characters.first == "/" {
        characters = characters.dropFirst()
    }
    guard let first = characters.first, first.isASCII, first.isLetter else {
        return false
    }
    characters = characters.dropFirst()
    while let character = characters.first,
          character.isASCII,
          character.isLetter || character.isNumber || character == "-" {
        characters = characters.dropFirst()
    }
    guard let separator = characters.first else {
        return false
    }
    return separator == ">"
        || separator == "/"
        || separator.isWhitespace
}

private func block(
    _ kind: MarkdownCompatibilityBlock.Kind,
    lines: [String],
    start: Int,
    end: Int
) -> MarkdownCompatibilityBlock {
    MarkdownCompatibilityBlock(
        kind: kind,
        source: lines[start...end].joined(separator: "\n"),
        startLine: start + 1,
        endLine: end + 1
    )
}
