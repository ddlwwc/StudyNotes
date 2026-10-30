import XCTest
@testable import StudyCore

final class NearestAnnotationTests: XCTestCase {

    private struct Box {
        let range: NSRange
        let top: CGFloat
        let bottom: CGFloat
    }

    private func nearest(
        _ boxes: [Box],
        to visibleBottom: CGFloat
    ) -> NSRange? {
        var best: (range: NSRange, distance: CGFloat)?
        for box in boxes {
            let distance = abs(box.bottom - visibleBottom)
            if best == nil || distance < best!.distance {
                best = (box.range, distance)
            }
        }
        return best?.range
    }

    func testPicksClosestToBottomEdge() {
        let boxes = [
            Box(range: NSRange(location: 0, length: 5), top: 0, bottom: 20),
            Box(range: NSRange(location: 10, length: 5), top: 100, bottom: 120),
            Box(range: NSRange(location: 20, length: 5), top: 300, bottom: 320),
        ]
        XCTAssertEqual(nearest(boxes, to: 118)?.location, 10)
        XCTAssertEqual(nearest(boxes, to: 315)?.location, 20)
        XCTAssertEqual(nearest(boxes, to: 5)?.location, 0)
    }

    func testPicksAboveWhenBottomBelowViewport() {
        let boxes = [
            Box(range: NSRange(location: 0, length: 5), top: 40, bottom: 60),
            Box(range: NSRange(location: 10, length: 5), top: 500, bottom: 520),
        ]
        XCTAssertEqual(nearest(boxes, to: 70)?.location, 0)
    }

    func testReturnsNilWhenEmpty() {
        XCTAssertNil(nearest([], to: 100))
    }

    func testTiePicksFirst() {
        let boxes = [
            Box(range: NSRange(location: 1, length: 2), top: 0, bottom: 50),
            Box(range: NSRange(location: 3, length: 2), top: 50, bottom: 150),
        ]
        // 两者与视口底部距离相同，实现保留先出现者
        XCTAssertEqual(nearest(boxes, to: 100)?.location, 1)
    }

    func testMultipleOnSameLine() {
        let boxes = [
            Box(range: NSRange(location: 0, length: 3), top: 10, bottom: 30),
            Box(range: NSRange(location: 8, length: 3), top: 10, bottom: 30),
        ]
        let result = nearest(boxes, to: 25)
        XCTAssertNotNil(result)
        XCTAssertTrue(result == NSRange(location: 0, length: 3)
                      || result == NSRange(location: 8, length: 3))
    }
}

final class AnnotationScrollMappingTests: XCTestCase {

    func testRenderedRangeBackToSource() {
        let source = "# 标题\n\n正文段落\n\n结尾"
        let layout = MarkdownLayout.build(source: source)
        let rendered = (layout.text as NSString).range(of: "正文段落")
        let sourceRange = layout.sourceRange(forRendered: rendered)
        XCTAssertNotNil(sourceRange)
        XCTAssertEqual((source as NSString).substring(with: sourceRange!), "正文段落")
    }

    func testSourceRangeForwardMapping() {
        let source = "# 标题\n\n正文段落"
        let layout = MarkdownLayout.build(source: source)
        let sourceRange = (source as NSString).range(of: "正文段落")
        let rendered = layout.renderedRange(forSource: sourceRange)
        XCTAssertNotNil(rendered)
        XCTAssertEqual((layout.text as NSString).substring(with: rendered!), "正文段落")
    }

    func testMappingRoundTripsThroughMultipleBlocks() {
        let source = "第一段\n\n第二段\n\n第三段"
        let layout = MarkdownLayout.build(source: source)
        for word in ["第一段", "第二段", "第三段"] {
            let sr = (source as NSString).range(of: word)
            guard let rr = layout.renderedRange(forSource: sr) else {
                XCTFail("\(word) 应能映射到渲染位置")
                continue
            }
            guard let back = layout.sourceRange(forRendered: rr) else {
                XCTFail("\(word) 应能映射回原文")
                continue
            }
            XCTAssertEqual((source as NSString).substring(with: back), word)
        }
    }
}
