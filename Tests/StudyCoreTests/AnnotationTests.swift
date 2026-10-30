import XCTest
@testable import StudyCore

final class AnnotationTests: XCTestCase {

    func testMakeFromRange() {
        let source = "这是正文内容"
        let range = (source as NSString).range(of: "正文")
        let annotation = AnnotationAnchor.make(from: source, range: range, existing: [])
        XCTAssertEqual(annotation?.anchorText, "正文")
    }

    func testMakeRejectsEmptySelection() {
        XCTAssertNil(AnnotationAnchor.make(from: "正文", range: NSRange(location: 0, length: 0), existing: []))
    }

    func testMakeRejectsWhitespaceOnly() {
        let source = "a   b"
        let range = (source as NSString).range(of: "   ")
        XCTAssertNil(AnnotationAnchor.make(from: source, range: range, existing: []))
    }

    func testLocateFindsAnchor() {
        let range = AnnotationAnchor.locate(anchorText: "正文", in: "这是正文内容")
        XCTAssertEqual(range, NSRange(location: 2, length: 2))
    }

    func testLocateReturnsNilWhenMissing() {
        XCTAssertNil(AnnotationAnchor.locate(anchorText: "不存在", in: "这是正文"))
    }

    func testLocateSkipsClaimedRanges() {
        let source = "重复重复"
        let first = AnnotationAnchor.locate(anchorText: "重复", in: source)
        XCTAssertEqual(first, NSRange(location: 0, length: 2))
        let second = AnnotationAnchor.locate(
            anchorText: "重复",
            in: source,
            claimed: [first!]
        )
        XCTAssertEqual(second, NSRange(location: 2, length: 2))
    }

    func testResolveMultipleAnnotations() {
        let source = "开头AAA中间BBB结尾"
        var file = AnnotationFile()
        file.upsert(Annotation(id: "1", anchorText: "AAA", createdAt: Date(timeIntervalSince1970: 1)))
        file.upsert(Annotation(id: "2", anchorText: "BBB", createdAt: Date(timeIntervalSince1970: 2)))

        let resolved = AnnotationAnchor.resolve(file, in: source)
        XCTAssertEqual(resolved.count, 2)
        XCTAssertEqual((source as NSString).substring(with: resolved[0].range), "AAA")
        XCTAssertEqual((source as NSString).substring(with: resolved[1].range), "BBB")
    }

    func testResolveSkipsMissingAnchor() {
        let source = "只有AAA"
        var file = AnnotationFile()
        file.upsert(Annotation(id: "1", anchorText: "AAA"))
        file.upsert(Annotation(id: "2", anchorText: "没了"))
        XCTAssertEqual(AnnotationAnchor.resolve(file, in: source).count, 1)
    }
}

final class CommentTests: XCTestCase {

    func testTotalCountIncludesReplies() {
        let root = Comment(text: "根", replies: [
            Comment(text: "回复1", replies: [Comment(text: "深层")]),
            Comment(text: "回复2"),
        ])
        XCTAssertEqual(root.totalCount, 4)
    }

    func testAddReplyToRoot() {
        let root = Comment(id: "r", text: "根")
        let updated = root.addingReply(Comment(id: "c", text: "回复"), to: "r")
        XCTAssertEqual(updated?.replies.count, 1)
        XCTAssertEqual(updated?.replies.first?.text, "回复")
    }

    func testAddReplyToNested() {
        let root = Comment(id: "r", text: "根", replies: [Comment(id: "c1", text: "第一层")])
        let updated = root.addingReply(Comment(id: "c2", text: "第二层"), to: "c1")
        XCTAssertEqual(updated?.replies.first?.replies.count, 1)
        XCTAssertEqual(updated?.replies.first?.replies.first?.text, "第二层")
    }

    func testAddReplyReturnsNilForUnknownTarget() {
        let root = Comment(id: "r", text: "根")
        XCTAssertNil(root.addingReply(Comment(text: "x"), to: "不存在"))
    }

    func testRemoveReply() {
        let root = Comment(id: "r", text: "根", replies: [
            Comment(id: "a", text: "A"),
            Comment(id: "b", text: "B"),
        ])
        let updated = root.removingReply("a")
        XCTAssertEqual(updated?.replies.count, 1)
        XCTAssertEqual(updated?.replies.first?.id, "b")
    }

    func testAnnotationCommentCount() {
        let annotation = Annotation(anchorText: "文本", comments: [
            Comment(text: "一", replies: [Comment(text: "回复")]),
            Comment(text: "二"),
        ])
        XCTAssertEqual(annotation.commentCount, 3)
    }

    func testFileUpsertReplacesExisting() {
        var file = AnnotationFile()
        file.upsert(Annotation(id: "x", anchorText: "旧"))
        file.upsert(Annotation(id: "x", anchorText: "新"))
        XCTAssertEqual(file.annotations.count, 1)
        XCTAssertEqual(file.annotations.first?.anchorText, "新")
    }

    func testFileRemove() {
        var file = AnnotationFile()
        file.upsert(Annotation(id: "x", anchorText: "甲"))
        file.remove(id: "x")
        XCTAssertTrue(file.annotations.isEmpty)
    }

    func testCodableRoundTrip() throws {
        var file = AnnotationFile()
        file.upsert(Annotation(
            id: "a1",
            anchorText: "锚点",
            comments: [Comment(id: "c1", text: "评论", replies: [Comment(id: "c2", text: "回复")])],
            createdAt: Date(timeIntervalSince1970: 1000)
        ))
        let data = try JSONEncoder.study.encode(file)
        let decoded = try JSONDecoder.study.decode(AnnotationFile.self, from: data)
        XCTAssertEqual(decoded, file)
        XCTAssertEqual(decoded.annotations.first?.comments.first?.replies.first?.text, "回复")
    }
}

final class StripHighlightTests: XCTestCase {

    func testStripsSingleHighlight() {
        XCTAssertEqual(NoteAnnotations.stripHighlights("这是==重点==内容"), "这是重点内容")
    }

    func testStripsMultipleHighlights() {
        XCTAssertEqual(NoteAnnotations.stripHighlights("==甲==中==乙=="), "甲中乙")
    }

    func testLeavesUnpairedMarker() {
        XCTAssertEqual(NoteAnnotations.stripHighlights("只有 == 一个"), "只有 == 一个")
    }

    func testNoMarkerUnchanged() {
        XCTAssertEqual(NoteAnnotations.stripHighlights("普通文本"), "普通文本")
    }

    func testEmptyInput() {
        XCTAssertEqual(NoteAnnotations.stripHighlights(""), "")
    }

    func testAnchorResolvesAfterStrip() {
        let original = "开头==重点内容==结尾"
        let stripped = NoteAnnotations.stripHighlights(original)
        XCTAssertEqual(stripped, "开头重点内容结尾")
        let range = AnnotationAnchor.locate(anchorText: "重点内容", in: stripped)
        XCTAssertNotNil(range)
        XCTAssertEqual((stripped as NSString).substring(with: range!), "重点内容")
    }

    func testHighlightedAnchorStillResolves() {
        let original = "这是一段==被标注的文字==后面的内容"
        let stripped = NoteAnnotations.stripHighlights(original)
        let anchor = "被标注的文字"
        XCTAssertNotNil(AnnotationAnchor.locate(anchorText: anchor, in: stripped))
    }
}
