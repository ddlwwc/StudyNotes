import XCTest
@testable import StudyCore

final class TagGroupingTests: XCTestCase {

    func testParsesInlineTagList() {
        let note = MarkdownCardParser.parseNote(
            relativePath: "notes/a.md",
            content: "---\ntags: [java, 并发]\n---\n# 标题\n"
        )
        XCTAssertEqual(note.tags, ["java", "并发"])
    }

    func testParsesSingleTag() {
        let note = MarkdownCardParser.parseNote(
            relativePath: "notes/a.md",
            content: "---\ntags: [java]\n---\n# 标题\n"
        )
        XCTAssertEqual(note.tags, ["java"])
    }

    func testParsesTagWithoutBrackets() {
        let note = MarkdownCardParser.parseNote(
            relativePath: "notes/a.md",
            content: "---\ntags: java, 并发\n---\n# 标题\n"
        )
        XCTAssertEqual(note.tags, ["java", "并发"])
    }

    func testEmptyTagsWhenNoFrontMatter() {
        let note = MarkdownCardParser.parseNote(
            relativePath: "notes/a.md",
            content: "# 标题\n正文"
        )
        XCTAssertTrue(note.tags.isEmpty)
    }

    func testEmptyTagList() {
        let note = MarkdownCardParser.parseNote(
            relativePath: "notes/a.md",
            content: "---\ntags: []\n---\n# 标题\n"
        )
        XCTAssertTrue(note.tags.isEmpty)
    }

    func testGroupsByFirstTag() {
        let notes = [
            Note(id: "n/1.md", title: "一", tags: ["java"]),
            Note(id: "n/2.md", title: "二", tags: ["java", "并发"]),
            Note(id: "n/3.md", title: "三", tags: ["swift"]),
            Note(id: "n/4.md", title: "四", tags: []),
        ]
        let grouped = groupNotes(notes)
        XCTAssertEqual(grouped["java"]?.count, 2)
        XCTAssertEqual(grouped["swift"]?.count, 1)
        XCTAssertEqual(grouped["未分类"]?.count, 1)
    }

    private func groupNotes(_ notes: [Note]) -> [String: [Note]] {
        Dictionary(grouping: notes) { note in
            note.tags.first ?? "未分类"
        }
    }
}

final class TagRewriteTests: XCTestCase {

    func testAddsTagsToPlainNote() {
        let result = MarkdownCardParser.withTags(["java"], in: "# 标题\n正文")
        XCTAssertTrue(result.contains("tags: [java]"))
        XCTAssertTrue(result.contains("# 标题"))
        XCTAssertTrue(result.contains("正文"))
    }

    func testReplacesExistingTags() {
        let original = "---\ntags: [old]\n---\n# 标题\n"
        let result = MarkdownCardParser.withTags(["new"], in: original)
        XCTAssertTrue(result.contains("tags: [new]"))
        XCTAssertFalse(result.contains("old"))
    }

    func testMultipleTags() {
        let result = MarkdownCardParser.withTags(["java", "并发"], in: "# 标题")
        XCTAssertTrue(result.contains("tags: [java, 并发]"))
    }

    func testRemovingAllTagsDropsFrontMatter() {
        let original = "---\ntags: [java]\n---\n# 标题\n正文"
        let result = MarkdownCardParser.withTags([], in: original)
        XCTAssertFalse(result.contains("tags:"))
        XCTAssertTrue(result.hasPrefix("# 标题"))
        XCTAssertTrue(result.contains("正文"))
    }

    func testRewriteRoundTrips() {
        let original = "# 标题\n正文内容"
        let withTag = MarkdownCardParser.withTags(["k1"], in: original)
        let parsed = MarkdownCardParser.parseNote(relativePath: "n/a.md", content: withTag)
        XCTAssertEqual(parsed.tags, ["k1"])
        XCTAssertTrue(parsed.body.contains("正文内容"))
    }

    func testEmptyTagStringsIgnored() {
        let result = MarkdownCardParser.withTags(["  ", ""], in: "# 标题")
        XCTAssertFalse(result.contains("tags:"))
    }
}
