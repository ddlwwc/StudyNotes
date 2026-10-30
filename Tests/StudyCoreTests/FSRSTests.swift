import XCTest
@testable import StudyCore

final class FSRSTests: XCTestCase {

    let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testGoodGradeSchedulesIntervalOrdered() {
        let fsrs = FSRS()
        let good = fsrs.initialState(grade: .good, now: now)
        let hard = fsrs.initialState(grade: .hard, now: now)
        let easy = fsrs.initialState(grade: .easy, now: now)

        XCTAssertLessThan(hard.stability, good.stability)
        XCTAssertLessThan(good.stability, easy.stability)
        XCTAssertLessThan(hard.due, good.due)
        XCTAssertLessThan(good.due, easy.due)
    }

    func testAgainIncrementsLapses() {
        let fsrs = FSRS()
        let initial = fsrs.initialState(grade: .good, now: now)
        let reviewed = fsrs.next(state: initial, grade: .again, now: now.addingTimeInterval(3 * 86_400))

        XCTAssertEqual(reviewed.lapses, 1)
        XCTAssertLessThanOrEqual(reviewed.stability, initial.stability)
    }

    func testSuccessfulReviewGrowsStability() {
        let fsrs = FSRS()
        let initial = fsrs.initialState(grade: .good, now: now)
        let reviewed = fsrs.next(state: initial, grade: .good, now: now.addingTimeInterval(3 * 86_400))

        XCTAssertGreaterThan(reviewed.stability, initial.stability)
        XCTAssertEqual(reviewed.reps, 2)
        XCTAssertEqual(reviewed.lapses, 0)
    }

    func testRetrievabilityDecaysToHalfAroundStability() {
        let fsrs = FSRS()
        let atStability = fsrs.retrievability(elapsedDays: 10, stability: 10)
        XCTAssertEqual(atStability, 0.9, accuracy: 0.02)

        let fresh = fsrs.retrievability(elapsedDays: 0, stability: 10)
        XCTAssertEqual(fresh, 1.0, accuracy: 0.001)
    }

    func testDifficultyStaysWithinBounds() {
        let fsrs = FSRS()
        var state = fsrs.initialState(grade: .good, now: now)
        for _ in 0..<50 {
            state = fsrs.next(state: state, grade: .again, now: now.addingTimeInterval(86_400))
        }
        XCTAssertGreaterThanOrEqual(state.difficulty, 1)
        XCTAssertLessThanOrEqual(state.difficulty, 10)
    }

    func testIntervalIsBounded() {
        let fsrs = FSRS()
        XCTAssertGreaterThanOrEqual(fsrs.intervalDays(stability: 0.0001), 1)
        XCTAssertLessThanOrEqual(fsrs.intervalDays(stability: 1e9), 365 * 10)
    }
}
