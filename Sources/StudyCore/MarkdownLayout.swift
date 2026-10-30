import Foundation

public struct MarkdownSpan: Equatable, Sendable {
    public enum Role: Equatable, Sendable {
        case heading(level: Int)
        case paragraph
        case bullet(indent: Int)
        case numbered(index: String, indent: Int)
        case quote
        case code(language: String)
        case cardQuestion
        case cardAnswer
        case cardLabel
        case divider
    }

    public enum Emphasis: Equatable, Sendable {
        case none
        case bold
        case italic
        case code
        case highlight
    }

    public var text: String
    public var role: Role
    public var emphasis: Emphasis
    public var sourceRange: NSRange
    public var startsNewLine: Bool

    public init(
        text: String,
        role: Role,
        emphasis: Emphasis = .none,
        sourceRange: NSRange,
        startsNewLine: Bool
    ) {
        self.text = text
        self.role = role
        self.emphasis = emphasis
        self.sourceRange = sourceRange
        self.startsNewLine = startsNewLine
    }
}

public struct MarkdownPiece: Equatable, Sendable {
    public var renderedRange: NSRange
    public var sourceRange: NSRange?
    public var role: MarkdownSpan.Role
    public var emphasis: MarkdownSpan.Emphasis
}

public struct MarkdownLayout: Equatable, Sendable {
    public var text: String
    public var pieces: [MarkdownPiece]
    public var source: String

    public static func build(source: String) -> MarkdownLayout {
        let spans = parseSpans(source)
        return assemble(spans: spans, source: source)
    }

    public func sourceRange(forRendered range: NSRange) -> NSRange? {
        guard range.length > 0 else { return nil }
        let end = range.location + range.length
        var lower: Int?
        var upper: Int?

        for piece in pieces {
            let pStart = piece.renderedRange.location
            let pEnd = pStart + piece.renderedRange.length
            guard pEnd > range.location, pStart < end else { continue }
            guard let sourceRange = piece.sourceRange else { continue }
            lower = min(lower ?? sourceRange.location, sourceRange.location)
            upper = max(upper ?? (sourceRange.location + sourceRange.length),
                        sourceRange.location + sourceRange.length)
        }

        guard let lower, let upper, upper > lower else { return nil }
        return NSRange(location: lower, length: upper - lower)
    }

    public func renderedRange(forSource range: NSRange) -> NSRange? {
        guard range.length > 0 else { return nil }
        let end = range.location + range.length
        var lower: Int?
        var upper: Int?

        for piece in pieces {
            guard let s = piece.sourceRange else { continue }
            let sEnd = s.location + s.length
            guard sEnd > range.location, s.location < end else { continue }
            lower = min(lower ?? piece.renderedRange.location, piece.renderedRange.location)
            upper = max(upper ?? (piece.renderedRange.location + piece.renderedRange.length),
                        piece.renderedRange.location + piece.renderedRange.length)
        }

        guard let lower, let upper, upper > lower else { return nil }
        return NSRange(location: lower, length: upper - lower)
    }

    static func assemble(spans: [MarkdownSpan], source: String) -> MarkdownLayout {
        let result = NSMutableString()
        var pieces: [MarkdownPiece] = []
        var isFirst = true

        for span in spans {
            if span.startsNewLine && !isFirst {
                result.append("\n")
            }
            isFirst = false
            let start = result.length
            result.append(span.text)
            pieces.append(
                MarkdownPiece(
                    renderedRange: NSRange(location: start, length: (span.text as NSString).length),
                    sourceRange: span.sourceRange,
                    role: span.role,
                    emphasis: span.emphasis
                )
            )
        }

        return MarkdownLayout(text: result as String, pieces: pieces, source: source)
    }

    static func parseSpans(_ source: String) -> [MarkdownSpan] {
        let ns = source as NSString
        var spans: [MarkdownSpan] = []
        var lineStarts: [Int] = []
        var index = 0
        while index < ns.length {
            lineStarts.append(index)
            let lineRange = ns.lineRange(for: NSRange(location: index, length: 0))
            let next = lineRange.location + lineRange.length
            if next <= index { break }
            index = next
        }

        var lineIndex = 0
        let bodyStart = MarkdownCardParser.bodyLineIndex(
            source.components(separatedBy: .newlines)
        )

        while lineIndex < lineStarts.count {
            let start = lineStarts[lineIndex]
            let rawLine = ns.lineRange(for: NSRange(location: start, length: 0))
            var content = ns.substring(with: rawLine)
            content = content.replacingOccurrences(of: "\n", with: "")
            content = content.replacingOccurrences(of: "\r", with: "")

            if lineIndex < bodyStart {
                lineIndex += 1
                continue
            }

            let trimmed = content.trimmingCharacters(in: .whitespaces)
            let leadingSpaces = content.prefix { $0 == " " || $0 == "\t" }.count

            if trimmed.isEmpty {
                lineIndex += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                let isCard = language.lowercased() == "card"
                var cursor = lineIndex + 1
                var cardSection = ""

                while cursor < lineStarts.count {
                    let cursorStart = lineStarts[cursor]
                    let cursorRange = ns.lineRange(for: NSRange(location: cursorStart, length: 0))
                    var inner = ns.substring(with: cursorRange)
                    inner = inner.replacingOccurrences(of: "\n", with: "")
                    inner = inner.replacingOccurrences(of: "\r", with: "")
                    let innerTrimmed = inner.trimmingCharacters(in: .whitespaces)
                    if innerTrimmed.hasPrefix("```") { break }

                    if isCard {
                        if innerTrimmed.hasPrefix("q:") {
                            cardSection = "question"
                            if let placed = inlinePlacement(inner, marker: "q:", text: String(innerTrimmed.dropFirst(2))) {
                                spans.append(MarkdownSpan(
                                    text: placed.text,
                                    role: .cardQuestion,
                                    sourceRange: NSRange(
                                        location: cursorStart + placed.offset,
                                        length: (placed.text as NSString).length
                                    ),
                                    startsNewLine: cursor == lineIndex + 1
                                ))
                            }
                        } else if innerTrimmed.hasPrefix("a:") {
                            cardSection = "answer"
                            if let placed = inlinePlacement(inner, marker: "a:", text: String(innerTrimmed.dropFirst(2))) {
                                spans.append(MarkdownSpan(
                                    text: placed.text,
                                    role: .cardAnswer,
                                    sourceRange: NSRange(
                                        location: cursorStart + placed.offset,
                                        length: (placed.text as NSString).length
                                    ),
                                    startsNewLine: true
                                ))
                            }
                        } else if !innerTrimmed.isEmpty, innerTrimmed != "---" {
                            let offset = cursorStart + leadingSpaces
                            let text = innerTrimmed
                            spans.append(MarkdownSpan(
                                text: text,
                                role: cardSection == "answer" ? .cardAnswer : .cardQuestion,
                                sourceRange: NSRange(
                                    location: offset,
                                    length: (text as NSString).length
                                ),
                                startsNewLine: true
                            ))
                        }
                    } else {
                        let text = inner
                        let offset = cursorStart
                        spans.append(MarkdownSpan(
                            text: text,
                            role: .code(language: language),
                            emphasis: .code,
                            sourceRange: NSRange(location: offset, length: (text as NSString).length),
                            startsNewLine: true
                        ))
                    }

                    cursor += 1
                }

                lineIndex = max(cursor + 1, lineIndex + 1)
                continue
            }

            if trimmed == "---" || trimmed == "***" {
                spans.append(MarkdownSpan(
                    text: "",
                    role: .divider,
                    sourceRange: NSRange(location: start, length: (trimmed as NSString).length),
                    startsNewLine: true
                ))
                lineIndex += 1
                continue
            }

            var markerLength = 0
            var role: MarkdownSpan.Role = .paragraph

            if trimmed.hasPrefix("#") {
                var level = 0
                for character in trimmed {
                    if character == "#" { level += 1 } else { break }
                }
                let afterHashes = trimmed.dropFirst(level)
                if level <= 6, afterHashes.hasPrefix(" ") {
                    role = .heading(level: level)
                    markerLength = level + 1
                }
            }

            if case .paragraph = role {
                if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                    role = .bullet(indent: leadingSpaces / 2)
                    markerLength = 2
                } else if let quoted = Self.quotePrefix(trimmed) {
                    role = .quote
                    markerLength = quoted
                } else if let numbered = Self.numberedMarker(trimmed) {
                    role = .numbered(index: numbered.index, indent: leadingSpaces / 2)
                    markerLength = numbered.length
                }
            }

            let contentOffsetInTrimmed = leadingSpaces + markerLength
            let inlineText = String(trimmed.dropFirst(markerLength))
            let inlineStart = start + contentOffsetInTrimmed

            appendInlineSpans(
                text: inlineText,
                sourceOffset: inlineStart,
                role: role,
                into: &spans
            )

            lineIndex += 1
        }

        return spans
    }

    private static func leadingOffset(_ line: String, marker: String) -> Int {
        guard let range = line.range(of: marker) else { return 0 }
        return line.distance(from: line.startIndex, to: range.lowerBound)
    }

    static func quotePrefix(_ trimmed: String) -> Int? {
        guard trimmed.hasPrefix(">") else { return nil }
        var consumed = 0
        var index = trimmed.startIndex
        while index < trimmed.endIndex, trimmed[index] == ">" {
            consumed += 1
            index = trimmed.index(after: index)
            while index < trimmed.endIndex, trimmed[index] == " " || trimmed[index] == "\t" {
                consumed += 1
                index = trimmed.index(after: index)
            }
        }
        guard consumed > 0 else { return nil }
        return consumed
    }

    static func inlinePlacement(_ line: String, marker: String, text: String) -> (text: String, offset: Int)? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        guard let markerRange = line.range(of: marker) else { return nil }
        let afterMarker = line.index(markerRange.upperBound, offsetBy: 0)
        let rest = line[afterMarker...]
        let leadingSpaces = rest.prefix { $0 == " " || $0 == "\t" }.count
        let offset = line.distance(from: line.startIndex, to: afterMarker) + leadingSpaces
        guard offset + (trimmed as NSString).length <= (line as NSString).length else { return nil }
        return (trimmed, offset)
    }

    private static func numberedMarker(_ trimmed: String) -> (index: String, length: Int)? {
        guard let dot = trimmed.firstIndex(of: ".") else { return nil }
        let prefix = trimmed[trimmed.startIndex..<dot]
        guard !prefix.isEmpty, prefix.count <= 3, prefix.allSatisfy(\.isNumber) else { return nil }
        let after = trimmed[trimmed.index(after: dot)...]
        guard after.hasPrefix(" ") else { return nil }
        return (String(prefix), prefix.count + 2)
    }

    private static func appendInlineSpans(
        text: String,
        sourceOffset: Int,
        role: MarkdownSpan.Role,
        into spans: inout [MarkdownSpan]
    ) {
        let ns = text as NSString
        var buffer = ""
        var bufferStart = 0
        var index = 0
        var isFirst = true

        func flush(_ emphasis: MarkdownSpan.Emphasis, _ markerLength: Int, _ innerLength: Int) {
            if !buffer.isEmpty {
                spans.append(MarkdownSpan(
                    text: buffer,
                    role: role,
                    sourceRange: NSRange(
                        location: sourceOffset + bufferStart,
                        length: (buffer as NSString).length
                    ),
                    startsNewLine: isFirst
                ))
                isFirst = false
                buffer = ""
            }
            _ = emphasis
            _ = markerLength
            _ = innerLength
        }

        while index < ns.length {
            let rest = ns.substring(from: index)

            if rest.hasPrefix("**"), let close = rest.dropFirst(2).range(of: "**") {
                flush(.none, 0, 0)
                let innerStart = index + 2
                let innerLength = close.lowerBound.utf16Offset(in: rest.dropFirst(2))
                let inner = ns.substring(with: NSRange(location: innerStart, length: innerLength))
                if !inner.isEmpty {
                    spans.append(MarkdownSpan(
                        text: inner,
                        role: role,
                        emphasis: .bold,
                        sourceRange: NSRange(
                            location: sourceOffset + innerStart,
                            length: innerLength
                        ),
                        startsNewLine: isFirst
                    ))
                    isFirst = false
                }
                index = innerStart + innerLength + 2
                bufferStart = index
                continue
            }

            if rest.hasPrefix("=="), let close = rest.dropFirst(2).range(of: "==") {
                flush(.none, 0, 0)
                let innerStart = index + 2
                let innerLength = close.lowerBound.utf16Offset(in: rest.dropFirst(2))
                let inner = ns.substring(with: NSRange(location: innerStart, length: innerLength))
                if !inner.isEmpty {
                    spans.append(MarkdownSpan(
                        text: inner,
                        role: role,
                        emphasis: .highlight,
                        sourceRange: NSRange(
                            location: sourceOffset + index,
                            length: innerLength + 4
                        ),
                        startsNewLine: isFirst
                    ))
                    isFirst = false
                }
                index = innerStart + innerLength + 2
                bufferStart = index
                continue
            }

            if rest.hasPrefix("`"), let close = rest.dropFirst().firstIndex(of: "`") {
                flush(.none, 0, 0)
                let innerStart = index + 1
                let innerLength = close.utf16Offset(in: rest)
                let inner = ns.substring(with: NSRange(location: innerStart, length: innerLength))
                if !inner.isEmpty {
                    spans.append(MarkdownSpan(
                        text: inner,
                        role: role,
                        emphasis: .code,
                        sourceRange: NSRange(
                            location: sourceOffset + innerStart,
                            length: innerLength
                        ),
                        startsNewLine: isFirst
                    ))
                    isFirst = false
                }
                index = innerStart + innerLength + 1
                bufferStart = index
                continue
            }

            if rest.hasPrefix("_"), let close = rest.dropFirst().range(of: "_") {
                flush(.none, 0, 0)
                let innerStart = index + 1
                let innerLength = close.lowerBound.utf16Offset(in: rest.dropFirst())
                let inner = ns.substring(with: NSRange(location: innerStart, length: innerLength))
                if !inner.isEmpty {
                    spans.append(MarkdownSpan(
                        text: inner,
                        role: role,
                        emphasis: .italic,
                        sourceRange: NSRange(
                            location: sourceOffset + innerStart,
                            length: innerLength
                        ),
                        startsNewLine: isFirst
                    ))
                    isFirst = false
                }
                index = innerStart + innerLength + 1
                bufferStart = index
                continue
            }

            if buffer.isEmpty { bufferStart = index }
            buffer.append(ns.substring(with: NSRange(location: index, length: 1)))
            index += 1
        }

        flush(.none, 0, 0)
    }
}
