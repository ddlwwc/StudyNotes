import Foundation

public enum MarkdownCardParser {

    public static func parseNote(relativePath: String, content: String) -> Note {
        let lines = content.components(separatedBy: .newlines)
        let (tags, bodyStart) = parseFrontMatter(lines)
        let bodyLines = Array(lines[bodyStart...])
        let body = bodyLines.joined(separator: "\n")
        let title = firstHeading(in: bodyLines) ?? fileNameTitle(relativePath)
        let cards = parseCards(in: content, sourceNotePath: relativePath)
        return Note(id: relativePath, title: title, tags: tags, body: body, cards: cards)
    }

    public static func parseCards(in markdown: String, sourceNotePath: String? = nil) -> [Card] {
        let lines = markdown.components(separatedBy: .newlines)
        var cards: [Card] = []
        var index = 0

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard trimmed == "```card" || trimmed.hasPrefix("```card ") else {
                index += 1
                continue
            }

            var block: [String] = []
            var cursor = index + 1
            var closed = false
            while cursor < lines.count {
                if lines[cursor].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    closed = true
                    break
                }
                block.append(lines[cursor])
                cursor += 1
            }

            if closed, let card = makeCard(block, sourceNotePath: sourceNotePath) {
                cards.append(card)
            }
            index = cursor + 1
        }

        return cards
    }

    static func makeCard(_ block: [String], sourceNotePath: String?) -> Card? {
        var id: String?
        var question: String?
        var answerLines: [String] = []
        var inAnswer = false

        for raw in block {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if !inAnswer {
                if trimmed.hasPrefix("id:") {
                    id = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    continue
                }
                if trimmed.hasPrefix("q:") {
                    question = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                    continue
                }
                if trimmed.hasPrefix("a:") {
                    inAnswer = true
                    let rest = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                    if !rest.isEmpty { answerLines.append(rest) }
                    continue
                }
                continue
            }
            answerLines.append(raw)
        }

        guard let question, !question.isEmpty else { return nil }
        let answer = answerLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedID = (id?.isEmpty == false ? id! : Self.stableID(question))
        return Card(id: resolvedID, question: question, answer: answer, sourceNotePath: sourceNotePath)
    }

    public static func stableID(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
        return "c" + String(hash, radix: 16)
    }

    public static func withTags(_ tags: [String], in content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        let (_, bodyStart) = parseFrontMatter(lines)
        let bodyLines = Array(lines[bodyStart...])
        let body = bodyLines.joined(separator: "\n")

        let cleaned = tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if cleaned.isEmpty {
            return body.hasPrefix("\n") ? String(body.dropFirst()) : body
        }
        let list = cleaned.joined(separator: ", ")
        return "---\ntags: [\(list)]\n---\n" + body
    }

    public static func bodyLineIndex(_ lines: [String]) -> Int {
        parseFrontMatter(lines).bodyStart
    }

    static func parseFrontMatter(_ lines: [String]) -> (tags: [String], bodyStart: Int) {
        guard let first = lines.first?.trimmingCharacters(in: .whitespaces), first == "---" else {
            return ([], 0)
        }
        var tags: [String] = []
        var cursor = 1
        while cursor < lines.count {
            let trimmed = lines[cursor].trimmingCharacters(in: .whitespaces)
            if trimmed == "---" { return (tags, cursor + 1) }
            if trimmed.hasPrefix("tags:") {
                tags = parseTagList(String(trimmed.dropFirst(5)))
            }
            cursor += 1
        }
        return ([], 0)
    }

    static func parseTagList(_ raw: String) -> [String] {
        var value = raw.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("[") && value.hasSuffix("]") {
            value = String(value.dropFirst().dropLast())
        }
        return value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func firstHeading(in lines: [String]) -> String? {
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                let title = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !title.isEmpty { return title }
            }
        }
        return nil
    }

    static func fileNameTitle(_ relativePath: String) -> String {
        let name = (relativePath as NSString).lastPathComponent
        return (name as NSString).deletingPathExtension
    }
}
