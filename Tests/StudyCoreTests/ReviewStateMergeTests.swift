import XCTest
@testable import StudyCore

final class ReviewStateMergeTests: XCTestCase {

    let base = Date(timeIntervalSince1970: 1_700_000_000)

    func makeState(_ offset: Double, reps: Int) -> CardReviewState {
        CardReviewState(
            state: SchedulerState(
                stability: 5,
                difficulty: 5,
                due: base.addingTimeInterval(offset),
                lastReview: base.addingTimeInterval(offset),
                reps: reps,
                lapses: 0
            ),
            lastGrade: .good
        )
    }

    func testNewerLastReviewWins() {
        let stale = ReviewState(deviceID: "mac", cards: ["c1": makeState(100, reps: 1)])
        let fresh = ReviewState(deviceID: "iphone", cards: ["c1": makeState(200, reps: 2)])

        let merged = ReviewStateMerge.merge([stale, fresh])
        XCTAssertEqual(merged["c1"]?.state.reps, 2)
    }

    func testMergeIsOrderIndependent() {
        let a = ReviewState(deviceID: "mac", cards: ["c1": makeState(100, reps: 1)])
        let b = ReviewState(deviceID: "iphone", cards: ["c1": makeState(200, reps: 2)])

        let forward = ReviewStateMerge.merge([a, b])
        let backward = ReviewStateMerge.merge([b, a])
        XCTAssertEqual(forward, backward)
    }

    func testDisjointCardsAreCombined() {
        let a = ReviewState(deviceID: "mac", cards: ["c1": makeState(100, reps: 1)])
        let b = ReviewState(deviceID: "iphone", cards: ["c2": makeState(200, reps: 1)])

        let merged = ReviewStateMerge.merge([a, b])
        XCTAssertEqual(Set(merged.keys), ["c1", "c2"])
    }

    func testDueCardsAreSortedAndFiltered() {
        let state = ReviewState(deviceID: "mac", cards: [
            "later": makeState(10_000, reps: 1),
            "now": makeState(-10, reps: 1),
            "earlier": makeState(-100, reps: 1),
        ])

        let due = ReviewStateMerge.dueCardIDs(from: state.cards, at: base)
        XCTAssertEqual(due, ["earlier", "now"])
    }
}
