import XCTest
@testable import StudyCore

final class ReviewDedupTests: XCTestCase {

    func testDuplicateCardIDsAreDeduplicated() {
        let cards = [
            Card(id: "a", question: "同一个问题", answer: "1"),
            Card(id: "a", question: "同一个问题", answer: "2"),
            Card(id: "b", question: "另一个", answer: "3"),
        ]
        var byID: [String: Card] = [:]
        for card in cards where byID[card.id] == nil {
            byID[card.id] = card
        }
        XCTAssertEqual(byID.count, 2)
        XCTAssertEqual(byID["a"]?.answer, "1")
    }

    func testManyDuplicatesDoNotCrash() {
        let cards = (0..<100).map { Card(id: "same", question: "q\($0)", answer: "a") }
        var byID: [String: Card] = [:]
        for card in cards where byID[card.id] == nil {
            byID[card.id] = card
        }
        XCTAssertEqual(byID.count, 1)
    }

    func testStableIDMakesSameQuestionCollide() {
        XCTAssertEqual(
            MarkdownCardParser.stableID("什么是 CAS？"),
            MarkdownCardParser.stableID("什么是 CAS？")
        )
    }

    func testDuplicateQuestionsInNoteProduceSameCardID() {
        let markdown = """
        ```card
        q: 同一个问题
        a: 第一个答案
        ```
        ```card
        q: 同一个问题
        a: 第二个答案
        ```
        """
        let cards = MarkdownCardParser.parseCards(in: markdown)
        XCTAssertEqual(cards.count, 2)
        XCTAssertEqual(cards[0].id, cards[1].id)
    }

    func testReviewStateMergeHandlesEmpty() {
        let ids = ReviewStateMerge.dueCardIDs(from: [:], at: Date())
        XCTAssertTrue(ids.isEmpty)
    }
}
