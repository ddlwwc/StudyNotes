import XCTest
@testable import StudyCore

final class MarkdownLayoutTests: XCTestCase {

    func testRenderedTextOmitsMarkdownSyntax() {
        let layout = MarkdownLayout.build(source: "# 标题\n\n这是 **重点** 内容")
        XCTAssertEqual(layout.text, "标题\n这是 重点 内容")
    }

    func testSkipsFrontMatter() {
        let source = "---\ntags: [a]\n---\n# 标题"
        let layout = MarkdownLayout.build(source: source)
        XCTAssertEqual(layout.text, "标题")
        XCTAssertFalse(layout.text.contains("tags"))
    }

    func testMapsRenderedSelectionBackToSource() {
        let source = "# 标题\n\n正文内容"
        let layout = MarkdownLayout.build(source: source)
        let rendered = (layout.text as NSString).range(of: "正文内容")
        let sourceRange = layout.sourceRange(forRendered: rendered)
        XCTAssertNotNil(sourceRange)
        XCTAssertEqual((source as NSString).substring(with: sourceRange!), "正文内容")
    }

    func testMapsBoldSelectionBackToPlainText() {
        let source = "这是 **重点** 内容"
        let layout = MarkdownLayout.build(source: source)
        let rendered = (layout.text as NSString).range(of: "重点")
        let sourceRange = layout.sourceRange(forRendered: rendered)
        XCTAssertEqual((source as NSString).substring(with: sourceRange!), "重点")
    }

    func testMapsBulletSelection() {
        let source = "- 第一点\n- 第二点"
        let layout = MarkdownLayout.build(source: source)
        let rendered = (layout.text as NSString).range(of: "第二点")
        let sourceRange = layout.sourceRange(forRendered: rendered)
        XCTAssertEqual((source as NSString).substring(with: sourceRange!), "第二点")
    }

    func testMapsCardQuestion() {
        let source = """
        ```card
        id: c1
        q: 什么是 CAS？
        a: 比较并交换
        ```
        """
        let layout = MarkdownLayout.build(source: source)
        XCTAssertTrue(layout.text.contains("什么是 CAS？"))
        let rendered = (layout.text as NSString).range(of: "什么是 CAS？")
        let sourceRange = layout.sourceRange(forRendered: rendered)
        XCTAssertEqual((source as NSString).substring(with: sourceRange!), "什么是 CAS？")
    }

    func testRowsAreSeparated() {
        let layout = MarkdownLayout.build(source: "# A\n# B")
        XCTAssertEqual(layout.text, "A\nB")
    }

    func testEmptySourceProducesEmptyText() {
        XCTAssertEqual(MarkdownLayout.build(source: "").text, "")
    }

    func testCodeBlockKeepsContent() {
        let source = "```swift\nlet x = 1\n```"
        let layout = MarkdownLayout.build(source: source)
        XCTAssertEqual(layout.text, "let x = 1")
    }
}

final class NoteAnnotationsTests: XCTestCase {

    func testApplyWrapsSelectedText() {
        let source = "这是正文内容"
        let range = (source as NSString).range(of: "正文")
        let updated = NoteAnnotations.apply(highlightTo: source, range: range)
        XCTAssertEqual(updated, "这是==正文==内容")
    }

    func testApplyPreservesLengthOutsideSelection() {
        let source = "前缀选中后缀"
        let range = (source as NSString).range(of: "选中")
        let updated = NoteAnnotations.apply(highlightTo: source, range: range)!
        XCTAssertTrue(updated.contains("==选中=="))
        XCTAssertTrue(updated.hasPrefix("前缀"))
        XCTAssertTrue(updated.hasSuffix("后缀"))
    }

    func testRejectsEmptySelection() {
        XCTAssertNil(NoteAnnotations.apply(highlightTo: "正文", range: NSRange(location: 0, length: 0)))
    }

    func testRejectsWhitespaceOnlySelection() {
        let source = "a   b"
        let range = (source as NSString).range(of: "   ")
        XCTAssertNil(NoteAnnotations.apply(highlightTo: source, range: range))
    }

    func testFindsHighlights() {
        let source = "这是==重点==内容"
        let found = NoteAnnotations.highlights(in: source)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual((source as NSString).substring(with: found[0].range), "重点")
    }

    func testFindsMultipleHighlights() {
        let source = "==甲==中间==乙=="
        let found = NoteAnnotations.highlights(in: source)
        XCTAssertEqual(found.count, 2)
        XCTAssertEqual((source as NSString).substring(with: found[0].range), "甲")
        XCTAssertEqual((source as NSString).substring(with: found[1].range), "乙")
    }

    func testIgnoresUnpairedMarkers() {
        XCTAssertEqual(NoteAnnotations.highlights(in: "只有 == 一个").count, 0)
    }

    func testHighlightRoundTripsThroughLayout() {
        let source = "开头==重点==结尾"
        let found = NoteAnnotations.highlights(in: source)
        XCTAssertEqual(found.count, 1)
        let layout = MarkdownLayout.build(source: source)
        XCTAssertNotNil(layout.renderedRange(forSource: found[0].range))
    }

    func testRemoveHighlightRestoresOriginal() {
        let source = "这是==重点==内容"
        let found = NoteAnnotations.highlights(in: source)
        let restored = NoteAnnotations.removeHighlight(from: source, range: found[0].range)
        XCTAssertEqual(restored, "这是重点内容")
    }
}

final class MarkdownQuoteTests: XCTestCase {

    func testSingleQuoteStripsMarker() {
        let layout = MarkdownLayout.build(source: "> 引用内容")
        XCTAssertEqual(layout.text, "引用内容")
        XCTAssertFalse(layout.text.contains(">"))
    }

    func testNestedQuoteStripsAllMarkers() {
        let layout = MarkdownLayout.build(source: "> > 嵌套引用")
        XCTAssertEqual(layout.text, "嵌套引用")
        XCTAssertFalse(layout.text.contains(">"))
    }

    func testTripleNestedQuote() {
        let layout = MarkdownLayout.build(source: "> > > 三层")
        XCTAssertEqual(layout.text, "三层")
        XCTAssertFalse(layout.text.contains(">"))
    }

    func testQuoteWithoutSpaceStillStrips() {
        let layout = MarkdownLayout.build(source: ">注意这一点")
        XCTAssertEqual(layout.text, "注意这一点")
        XCTAssertFalse(layout.text.contains(">"))
    }

    func testDoubleAngleNoSpace() {
        let layout = MarkdownLayout.build(source: ">>连续")
        XCTAssertEqual(layout.text, "连续")
        XCTAssertFalse(layout.text.contains(">"))
    }

    func testBareQuoteLineProducesNoVisibleMarker() {
        let layout = MarkdownLayout.build(source: ">\n正文")
        XCTAssertFalse(layout.text.contains(">"))
        XCTAssertTrue(layout.text.contains("正文"))
    }

    func testQuoteWithExtraIndent() {
        let layout = MarkdownLayout.build(source: "   > 缩进引用")
        XCTAssertEqual(layout.text, "缩进引用")
        XCTAssertFalse(layout.text.contains(">"))
    }

    func testQuoteMapsBackToSource() {
        let source = "> 引用内容"
        let layout = MarkdownLayout.build(source: source)
        let rendered = (layout.text as NSString).range(of: "引用内容")
        let sourceRange = layout.sourceRange(forRendered: rendered)
        XCTAssertEqual((source as NSString).substring(with: sourceRange!), "引用内容")
    }

    func testGreaterThanInsideTextIsKept() {
        let layout = MarkdownLayout.build(source: "判断 a > b 的大小")
        XCTAssertTrue(layout.text.contains("a > b"), "句中大于号属于正文，必须保留")
    }

    func testManyQuoteLines() {
        let source = """
        > 第一行
        > 第二行
        > > 嵌套
        """
        let layout = MarkdownLayout.build(source: source)
        XCTAssertFalse(layout.text.contains(">"))
        XCTAssertTrue(layout.text.contains("第一行"))
        XCTAssertTrue(layout.text.contains("嵌套"))
    }
}
