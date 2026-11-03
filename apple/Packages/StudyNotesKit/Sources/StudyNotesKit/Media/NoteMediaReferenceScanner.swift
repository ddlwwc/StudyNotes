import Foundation

public struct NoteMediaReferenceScanResult: Equatable, Sendable {
    public let currentObjectKeys: [String]
    public let historicalObjectKeys: [String]
    public let referencedObjectKeys: [String]
    public let unreferencedObjectKeys: [String]
}

public enum NoteMediaReferenceScanner {
    public static func scan(
        currentMarkdown: String,
        historicalMarkdowns: [String],
        knownObjectKeys: [String] = []
    ) -> NoteMediaReferenceScanResult {
        let current = objectKeys(in: currentMarkdown)
        let historical = Set(
            historicalMarkdowns.flatMap { objectKeys(in: $0) }
        )
        let referenced = current.union(historical)
        let known = Set(knownObjectKeys.compactMap { objectKey in
            try? NoteMediaReference(objectKey: objectKey).objectKey
        })
        return NoteMediaReferenceScanResult(
            currentObjectKeys: current.sorted(),
            historicalObjectKeys: historical.sorted(),
            referencedObjectKeys: referenced.sorted(),
            unreferencedObjectKeys: known
                .subtracting(referenced)
                .sorted()
        )
    }

    public static func cleanupCandidates(
        knownObjectKeys: [String],
        currentMarkdown: String,
        historicalMarkdowns: [String]
    ) -> [String] {
        scan(
            currentMarkdown: currentMarkdown,
            historicalMarkdowns: historicalMarkdowns,
            knownObjectKeys: knownObjectKeys
        ).unreferencedObjectKeys
    }

    public static func objectKeys(in markdown: String) -> Set<String> {
        let pattern = #"media://qiniu/library-media/[0-9a-f]{64}\.[a-z0-9]{1,8}(?![A-Za-z0-9.%?#/\\_-])"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let range = NSRange(markdown.startIndex..., in: markdown)
        return Set(expression.matches(in: markdown, range: range).compactMap {
            match in
            guard let matchRange = Range(match.range, in: markdown),
                  let reference = try? NoteMediaReference(
                      string: String(markdown[matchRange])
                  ) else {
                return nil
            }
            return reference.objectKey
        })
    }
}
