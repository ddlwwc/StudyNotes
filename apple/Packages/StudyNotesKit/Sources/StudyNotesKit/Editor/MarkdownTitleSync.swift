import Foundation

public enum MarkdownTitleSyncPlan: Equatable, Sendable {
    case synchronized(title: String, markdown: String)
    case confirmation(manifestTitle: String, headingTitle: String)
}

public enum MarkdownTitleSyncError: Error, Equatable, Sendable, LocalizedError {
    case emptyTitle

    public var errorDescription: String? {
        switch self {
        case .emptyTitle:
            "标题不能为空。"
        }
    }
}

public struct MarkdownTitleSync: Sendable {
    private let codec: MarkdownEditorCodec

    public init(codec: MarkdownEditorCodec = MarkdownEditorCodec()) {
        self.codec = codec
    }

    public func plan(
        manifestTitle: String,
        markdown: String
    ) throws -> MarkdownTitleSyncPlan {
        let title = try normalizedTitle(manifestTitle)
        let document = try codec.decode(markdown)
        guard let heading = try firstHeading(in: document) else {
            return .synchronized(
                title: title,
                markdown: try applying(title: title, to: document.markdown)
            )
        }
        if heading.text == title {
            return .synchronized(title: title, markdown: document.markdown)
        }
        return .confirmation(
            manifestTitle: title,
            headingTitle: heading.text
        )
    }

    public func applying(
        title manifestTitle: String,
        to markdown: String
    ) throws -> String {
        let title = try normalizedTitle(manifestTitle)
        let document = try codec.decode(markdown)
        var lines = document.markdown.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).map(String.init)

        if let heading = try firstHeading(in: document) {
            lines[heading.lineIndex] = "# \(title)"
        } else {
            let insertionIndex = document.compatibilityBlocks.first(where: {
                $0.kind == .frontMatter
            })?.endLine ?? 0
            let nextLineIsBlank = insertionIndex < lines.count
                && lines[insertionIndex]
                    .trimmingCharacters(in: .whitespaces)
                    .isEmpty
            lines.insert(
                contentsOf: nextLineIsBlank
                    ? ["# \(title)"]
                    : ["# \(title)", ""],
                at: insertionIndex
            )
        }
        return lines.joined(separator: "\n")
    }

    private func normalizedTitle(_ title: String) throws -> String {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw MarkdownTitleSyncError.emptyTitle
        }
        return normalized
    }

    private func firstHeading(
        in document: MarkdownEditorDocument
    ) throws -> (text: String, lineIndex: Int)? {
        let lines = document.markdown.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).map(String.init)
        let compatibilityLines = Set(document.compatibilityBlocks.flatMap {
            ($0.startLine...$0.endLine).map { $0 - 1 }
        })
        var index = 0
        while index < lines.count {
            if compatibilityLines.contains(index) {
                index += 1
                continue
            }
            let line = lines[index]
            if let fence = fenceStart(
                line.trimmingCharacters(in: .whitespaces)
            ) {
                guard let closing = lines.indices.dropFirst(index + 1).first(
                    where: { isFenceEnd(lines[$0], fence: fence) }
                ) else {
                    throw MarkdownEditorCodecError.unclosedFence(line: index + 1)
                }
                index = closing + 1
                continue
            }
            if let text = levelOneHeadingText(line) {
                return (text, index)
            }
            index += 1
        }
        return nil
    }

    private func levelOneHeadingText(_ line: String) -> String? {
        let indent = line.prefix { $0 == " " }.count
        guard indent <= 3 else {
            return nil
        }
        let content = line.dropFirst(indent)
        guard content.hasPrefix("# ") else {
            return nil
        }
        return headingText(String(content.dropFirst(2)))
    }

    private func headingText(_ source: String) -> String {
        var text = source.trimmingCharacters(in: .whitespaces)
        if let closing = text.range(
            of: #"\s+#+\s*$"#,
            options: .regularExpression
        ) {
            text.removeSubrange(closing)
        }
        return text.trimmingCharacters(in: .whitespaces)
    }
}
