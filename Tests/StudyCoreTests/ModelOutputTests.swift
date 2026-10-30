import XCTest
@testable import StudyCore

final class ModelOutputTests: XCTestCase {

    func testPlainObjectPassesThrough() {
        let raw = #"{"grade": 3, "feedback": "还行"}"#
        XCTAssertEqual(ModelOutput.extractJSON(from: raw), raw)
    }

    func testStripsMarkdownFence() {
        let raw = """
        ```json
        {"grade": 3, "feedback": "还行"}
        ```
        """
        XCTAssertEqual(ModelOutput.extractJSON(from: raw), #"{"grade": 3, "feedback": "还行"}"#)
    }

    func testStripsFenceWithoutLanguage() {
        let raw = """
        ```
        [{"q": "问题", "a": "答案"}]
        ```
        """
        XCTAssertEqual(ModelOutput.extractJSON(from: raw), #"[{"q": "问题", "a": "答案"}]"#)
    }

    func testExtractsObjectFromSurroundingProse() {
        let raw = #"好的，这是结果：{"grade": 2, "feedback": "漏了要点"} 希望有帮助。"#
        XCTAssertEqual(ModelOutput.extractJSON(from: raw), #"{"grade": 2, "feedback": "漏了要点"}"#)
    }

    func testExtractsArrayFromSurroundingProse() {
        let raw = #"生成如下：[{"q": "A"}, {"q": "B"}] 完毕"#
        XCTAssertEqual(ModelOutput.extractJSON(from: raw), #"[{"q": "A"}, {"q": "B"}]"#)
    }

    func testPrefersEarliestStartWhenBothPresent() {
        let raw = #"{"items": [1, 2]}"#
        XCTAssertEqual(ModelOutput.extractJSON(from: raw), raw)
    }

    func testTrimsWhitespaceAndNewlines() {
        let raw = "\n\n   {\"grade\": 4}   \n\n"
        XCTAssertEqual(ModelOutput.extractJSON(from: raw), #"{"grade": 4}"#)
    }

    func testReturnsInputWhenNoJSONPresent() {
        let raw = "抱歉，我无法回答。"
        XCTAssertEqual(ModelOutput.extractJSON(from: raw), raw)
    }

    func testParsesCardsWithShortKeys() {
        let raw = #"[{"q": "什么是 CAS？", "a": "比较并交换"}]"#
        let cards = ModelOutput.parseCards(from: raw)
        XCTAssertEqual(cards?.count, 1)
        XCTAssertEqual(cards?.first?.question, "什么是 CAS？")
        XCTAssertEqual(cards?.first?.answer, "比较并交换")
    }

    func testParsesCardsWithLongKeys() {
        let raw = #"[{"question": "什么是 CAS？", "answer": "比较并交换"}]"#
        let cards = ModelOutput.parseCards(from: raw)
        XCTAssertEqual(cards?.count, 1)
        XCTAssertEqual(cards?.first?.question, "什么是 CAS？")
    }

    func testParsesCardsWithChineseKeys() {
        let raw = #"[{"问题": "什么是 CAS？", "答案": "比较并交换"}]"#
        let cards = ModelOutput.parseCards(from: raw)
        XCTAssertEqual(cards?.count, 1)
        XCTAssertEqual(cards?.first?.answer, "比较并交换")
    }

    func testParsesCardsInsideFenceWithProse() {
        let raw = """
        好的，这是卡片：
        ```json
        [{"q": "A", "a": "1"}, {"q": "B", "a": "2"}]
        ```
        """
        XCTAssertEqual(ModelOutput.parseCards(from: raw)?.count, 2)
    }

    func testReturnsNilForEmptyArray() {
        XCTAssertNil(ModelOutput.parseCards(from: "[]"))
    }

    func testReturnsNilWhenNoQuestionField() {
        XCTAssertNil(ModelOutput.parseCards(from: #"[{"foo": "bar"}]"#))
    }

    func testCardIDIsStableAcrossSameQuestion() {
        let a = ModelOutput.parseCards(from: #"[{"q": "同一个问题", "a": "1"}]"#)
        let b = ModelOutput.parseCards(from: #"[{"q": "同一个问题", "a": "2"}]"#)
        XCTAssertEqual(a?.first?.id, b?.first?.id)
    }

    func testTrimsWhitespaceInFields() {
        let cards = ModelOutput.parseCards(from: #"[{"q": "  问题  ", "a": "  答案  "}]"#)
        XCTAssertEqual(cards?.first?.question, "问题")
        XCTAssertEqual(cards?.first?.answer, "答案")
    }

    func testSkipsItemsMissingAnswer() {
        let raw = #"[{"q": "有问题没答案"}, {"q": "正常", "a": "答案"}]"#
        let cards = ModelOutput.parseCards(from: raw)
        XCTAssertEqual(cards?.count, 2)
        XCTAssertEqual(cards?.first?.answer, "")
        XCTAssertEqual(cards?.last?.answer, "答案")
    }
}
