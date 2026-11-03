import Foundation

public struct ResolvedTextAnchor: Equatable, Sendable {
    public let range: Range<Int>
    public let blockPath: String

    public init(range: Range<Int>, blockPath: String) {
        self.range = range
        self.blockPath = blockPath
    }
}

public enum TextAnchorResolver {
    public static func resolve(
        _ anchor: TextAnchor,
        in source: String
    ) -> ResolvedTextAnchor? {
        let quote = normalizedWhitespace(anchor.quote)
        guard !quote.isEmpty else {
            return nil
        }

        let block = blockText(at: anchor.blockPath, in: source)
            ?? source
        let normalizedBlock = normalizedWhitespace(block)
        let normalizedPrefix = normalizedWhitespace(anchor.prefix)
        let normalizedSuffix = normalizedWhitespace(anchor.suffix)
        let candidates = occurrences(of: quote, in: normalizedBlock)
        guard !candidates.isEmpty else {
            return nil
        }

        let scored = candidates.map { range -> (Range<Int>, Int) in
            var score = 0
            let before = String(normalizedBlock[..<normalizedBlock.index(
                normalizedBlock.startIndex,
                offsetBy: range.lowerBound
            )])
            let afterStart = normalizedBlock.index(
                normalizedBlock.startIndex,
                offsetBy: range.upperBound
            )
            let after = String(normalizedBlock[afterStart...])

            if !normalizedPrefix.isEmpty, before.hasSuffix(normalizedPrefix) {
                score += 8
            }
            if !normalizedSuffix.isEmpty, after.hasPrefix(normalizedSuffix) {
                score += 8
            }
            let distance = abs(range.lowerBound - anchor.startOffset)
            score -= min(distance, 6)
            if range.lowerBound == anchor.startOffset, range.upperBound == anchor.endOffset {
                score += 4
            }
            return (range, score)
        }

        guard let best = scored.max(by: { $0.1 < $1.1 }),
              best.1 > -6 || candidates.count == 1 else {
            return nil
        }
        return ResolvedTextAnchor(
            range: best.0,
            blockPath: anchor.blockPath
        )
    }

    public static func anchorsAreEquivalent(
        _ lhs: AnnotationAnchor,
        _ rhs: AnnotationAnchor
    ) -> Bool {
        switch (lhs, rhs) {
        case let (.text(left), .text(right)):
            return left.blockPath == right.blockPath
                && left.startOffset == right.startOffset
                && left.endOffset == right.endOffset
                && normalizedWhitespace(left.quote) == normalizedWhitespace(right.quote)
        case let (.imageRectangle(left), .imageRectangle(right)):
            return left.isApproximatelyEqual(to: right)
        case let (.pageRectangle(leftPage, leftRect), .pageRectangle(rightPage, rightRect)):
            return leftPage == rightPage && leftRect.isApproximatelyEqual(to: rightRect)
        case (.wholeMaterial, .wholeMaterial):
            return true
        default:
            return false
        }
    }

    public static func isResolved(
        _ anchor: AnnotationAnchor,
        in source: String?
    ) -> AnnotationResolution {
        switch anchor {
        case let .text(textAnchor):
            guard let source else {
                return .needsRecovery
            }
            return resolve(textAnchor, in: source) == nil ? .needsRecovery : .resolved
        case .imageRectangle, .pageRectangle, .wholeMaterial:
            return .resolved
        }
    }

    private static func normalizedWhitespace(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func occurrences(
        of needle: String,
        in haystack: String
    ) -> [Range<Int>] {
        guard !needle.isEmpty else {
            return []
        }
        var result: [Range<Int>] = []
        var searchStart = haystack.startIndex
        while searchStart < haystack.endIndex,
              let range = haystack.range(
                  of: needle,
                  options: [.caseInsensitive, .diacriticInsensitive],
                  range: searchStart..<haystack.endIndex
              ) {
            let lower = haystack.distance(from: haystack.startIndex, to: range.lowerBound)
            let upper = haystack.distance(from: haystack.startIndex, to: range.upperBound)
            result.append(lower..<upper)
            searchStart = range.upperBound
        }
        return result
    }

    private static func blockText(at blockPath: String, in source: String) -> String? {
        guard let blockNumber = Int(blockPath.replacingOccurrences(of: "block-", with: "")) else {
            return nil
        }
        let blocks = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard blocks.indices.contains(blockNumber) else {
            return nil
        }
        return blocks[blockNumber]
    }
}
