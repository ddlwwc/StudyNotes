import Foundation

public struct CardReviewState: Codable, Equatable, Sendable {
    public var state: SchedulerState
    public var lastGrade: Grade

    public init(state: SchedulerState, lastGrade: Grade) {
        self.state = state
        self.lastGrade = lastGrade
    }
}

public struct ReviewState: Codable, Equatable, Sendable {
    public var deviceID: String
    public var cards: [String: CardReviewState]

    public init(deviceID: String, cards: [String: CardReviewState] = [:]) {
        self.deviceID = deviceID
        self.cards = cards
    }
}

public enum ReviewStateMerge {

    public static func merge(_ shards: [ReviewState]) -> [String: CardReviewState] {
        var result: [String: CardReviewState] = [:]
        for shard in shards {
            for (cardID, entry) in shard.cards {
                if let existing = result[cardID] {
                    if isNewer(entry, than: existing) {
                        result[cardID] = entry
                    }
                } else {
                    result[cardID] = entry
                }
            }
        }
        return result
    }

    static func isNewer(_ lhs: CardReviewState, than rhs: CardReviewState) -> Bool {
        let left = lhs.state.lastReview ?? .distantPast
        let right = rhs.state.lastReview ?? .distantPast
        if left != right { return left > right }
        return lhs.state.reps > rhs.state.reps
    }

    public static func dueCardIDs(from merged: [String: CardReviewState], at now: Date) -> [String] {
        merged
            .filter { $0.value.state.due <= now }
            .sorted { $0.value.state.due < $1.value.state.due }
            .map(\.key)
    }
}
