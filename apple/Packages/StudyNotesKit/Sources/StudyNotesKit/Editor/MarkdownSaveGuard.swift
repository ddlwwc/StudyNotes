public enum MarkdownSaveDecision: Equatable, Sendable {
    case save
    case conflict(
        expectedFingerprint: String,
        currentFingerprint: String
    )
}

public struct MarkdownSaveGuard: Sendable {
    public init() {}

    public func decision(
        expectedFingerprint: String,
        currentFingerprint: String
    ) -> MarkdownSaveDecision {
        guard expectedFingerprint == currentFingerprint else {
            return .conflict(
                expectedFingerprint: expectedFingerprint,
                currentFingerprint: currentFingerprint
            )
        }
        return .save
    }
}
