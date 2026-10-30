import Foundation

public enum ModelOutput {
    public static func extractJSON(from raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if text.hasPrefix("```") {
            if let firstNewline = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: firstNewline)...])
            }
            if let fence = text.range(of: "```", options: .backwards) {
                text = String(text[..<fence.lowerBound])
            }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let start = firstJSONStart(in: text) else { return text }
        let opener = text[start]
        let closer: Character = opener == "{" ? "}" : "]"

        guard let end = text.lastIndex(of: closer), end > start else { return text }
        return String(text[start...end])
    }

    private static func firstJSONStart(in text: String) -> String.Index? {
        let brace = text.firstIndex(of: "{")
        let bracket = text.firstIndex(of: "[")
        switch (brace, bracket) {
        case let (b?, k?):
            return min(b, k)
        case let (b?, nil):
            return b
        case let (nil, k?):
            return k
        case (nil, nil):
            return nil
        }
    }

    public static func parseCards(from raw: String, sourceNotePath: String? = nil) -> [Card]? {
        let json = extractJSON(from: raw)
        guard
            let data = json.data(using: .utf8),
            let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return nil
        }
        let cards = items.compactMap { item -> Card? in
            guard let question = string(in: item, keys: ["q", "question", "Q", "问题"]) else {
                return nil
            }
            let answer = string(in: item, keys: ["a", "answer", "A", "答案"]) ?? ""
            return Card(
                id: MarkdownCardParser.stableID(question),
                question: question,
                answer: answer,
                sourceNotePath: sourceNotePath
            )
        }
        return cards.isEmpty ? nil : cards
    }

    private static func string(in item: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = item[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }
}
