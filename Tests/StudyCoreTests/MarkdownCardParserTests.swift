import XCTest
@testable import StudyCore

final class MarkdownCardParserTests: XCTestCase {

    func testParsesFrontMatterTagsAndTitle() {
        let content = """
        ---
        tags: [java, 并发]
        ---
        # 线程池

        正文内容。
        """
        let note = MarkdownCardParser.parseNote(relativePath: "notes/线程池.md", content: content)
        XCTAssertEqual(note.title, "线程池")
        XCTAssertEqual(note.tags, ["java", "并发"])
        XCTAssertTrue(note.cards.isEmpty)
    }

    func testParsesCardBlockWithMultiLineAnswer() {
        let content = """
        # 集合

        ```card
        id: c1
        q: ArrayList 和 LinkedList 的区别？
        a: 底层结构不同。
        随机访问 ArrayList 是 O(1)，LinkedList 是 O(n)。
        ```

        正文。
        """
        let cards = MarkdownCardParser.parseCards(in: content, sourceNotePath: "notes/集合.md")
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].id, "c1")
        XCTAssertEqual(cards[0].question, "ArrayList 和 LinkedList 的区别？")
        XCTAssertTrue(cards[0].answer.contains("O(1)"))
        XCTAssertTrue(cards[0].answer.contains("\n"))
        XCTAssertEqual(cards[0].sourceNotePath, "notes/集合.md")
    }

    func testGeneratesStableIDWhenMissing() {
        let content = """
        ```card
        q: 什么是重入锁？
        a: 同一线程可重复获取的锁。
        ```
        """
        let first = MarkdownCardParser.parseCards(in: content)
        let second = MarkdownCardParser.parseCards(in: content)
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first[0].id, second[0].id)
    }

    func testIgnoresUnclosedCardBlock() {
        let content = """
        ```card
        q: 未闭合
        a: 不应该被解析
        """
        XCTAssertTrue(MarkdownCardParser.parseCards(in: content).isEmpty)
    }

    func testParsesMultipleCards() {
        let content = """
        ```card
        q: 第一题
        a: 答案一
        ```

        中间正文。

        ```card
        q: 第二题
        a: 答案二
        ```
        """
        let cards = MarkdownCardParser.parseCards(in: content)
        XCTAssertEqual(cards.count, 2)
        XCTAssertEqual(cards[1].question, "第二题")
    }
}
