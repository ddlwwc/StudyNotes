import XCTest
@testable import StudyCore

final class NoteImportTests: XCTestCase {

    func testImportsNewFile() {
        let decision = NoteImport.decide(
            sourceName: "Java 并发.md",
            content: "# 标题\n正文",
            existingNames: []
        )
        XCTAssertEqual(decision, .write(targetName: "Java 并发.md"))
    }

    func testSkipsExistingName() {
        let decision = NoteImport.decide(
            sourceName: "已存在.md",
            content: "正文",
            existingNames: ["已存在.md"]
        )
        XCTAssertEqual(decision, .skip(reason: "已存在同名笔记"))
    }

    func testSkipsEmptyContent() {
        let decision = NoteImport.decide(
            sourceName: "空.md",
            content: "   \n\n  ",
            existingNames: []
        )
        XCTAssertEqual(decision, .skip(reason: "文件是空的"))
    }

    func testSkipsEmptyName() {
        let decision = NoteImport.decide(
            sourceName: ".md",
            content: "正文",
            existingNames: []
        )
        XCTAssertEqual(decision, .skip(reason: "文件名是空的"))
    }

    func testNormalizesExtensionToMarkdown() {
        let decision = NoteImport.decide(
            sourceName: "笔记.txt",
            content: "正文",
            existingNames: []
        )
        XCTAssertEqual(decision, .write(targetName: "笔记.md"))
    }

    func testPreservesChineseName() {
        let decision = NoteImport.decide(
            sourceName: "并发编程基础.md",
            content: "内容",
            existingNames: []
        )
        if case let .write(name) = decision {
            XCTAssertEqual(name, "并发编程基础.md")
        } else {
            XCTFail("应当写入")
        }
    }

    func testSanitizeRemovesIllegalCharacters() {
        XCTAssertEqual(NoteImport.sanitizedName("a/b:c"), "a-b-c")
    }

    func testSanitizeKeepsNormalName() {
        XCTAssertEqual(NoteImport.sanitizedName("正常名称"), "正常名称")
    }

    func testSanitizeFallsBackForEmpty() {
        XCTAssertEqual(NoteImport.sanitizedName("   "), "未命名")
    }
}
