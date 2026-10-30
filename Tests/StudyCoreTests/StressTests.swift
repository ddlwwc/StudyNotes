import XCTest
@testable import StudyCore

final class StressTests: XCTestCase {

    func testLargeDocumentParsesQuickly() {
        var md = "# 标题\n\n"
        for i in 0..<400 {
            md += "第 \(i) 段正文，包含 **粗体** 和 `代码` 以及 _斜体_。\n"
        }
        let start = Date()
        let layout = MarkdownLayout.build(source: md)
        let elapsed = Date().timeIntervalSince(start)
        print("400 段解析耗时: \(elapsed * 1000) ms, 片段数: \(layout.pieces.count)")
        XCTAssertLessThan(elapsed, 3.0, "解析不应超过 3 秒")
    }

    func testUnclosedFenceDoesNotHang() {
        let md = "```card\nq: 没有结束\n"
        let layout = MarkdownLayout.build(source: md)
        XCTAssertFalse(layout.text.isEmpty)
    }

    func testManyFencesDoNotHang() {
        var md = ""
        for i in 0..<200 {
            md += "```card\nid: c\(i)\nq: 问题\(i)\na: 答案\(i)\n```\n"
        }
        let layout = MarkdownLayout.build(source: md)
        XCTAssertGreaterThan(layout.pieces.count, 0)
    }

    func testManyAnnotationsResolve() {
        var source = ""
        for i in 0..<100 {
            source += "独特词\(i) "
        }
        var file = AnnotationFile()
        for i in 0..<100 {
            file.upsert(Annotation(id: "a\(i)", anchorText: "独特词\(i)", createdAt: Date(timeIntervalSince1970: Double(i))))
        }
        let start = Date()
        let resolved = AnnotationAnchor.resolve(file, in: source)
        let elapsed = Date().timeIntervalSince(start)
        print("100 条标注定位耗时: \(elapsed * 1000) ms, 命中: \(resolved.count)")
        XCTAssertEqual(resolved.count, 100)
        XCTAssertLessThan(elapsed, 3.0)
    }

    func testDuplicateAnchorsDoNotHang() {
        let source = String(repeating: "重复 ", count: 200)
        var file = AnnotationFile()
        for i in 0..<100 {
            file.upsert(Annotation(id: "a\(i)", anchorText: "重复", createdAt: Date(timeIntervalSince1970: Double(i))))
        }
        let resolved = AnnotationAnchor.resolve(file, in: source)
        XCTAssertEqual(resolved.count, 100)
    }

    func testPathologicalMarkerOnly() {
        let layout = MarkdownLayout.build(source: String(repeating: "=", count: 5000))
        XCTAssertNotNil(layout.text)
    }
}
