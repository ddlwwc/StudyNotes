import XCTest
@testable import StudyCore

final class FileIOTests: XCTestCase {

    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("StudyCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testEnsureDirectoriesCreatesLayout() throws {
        try VaultLayout.ensureDirectories(in: tempRoot)

        for name in VaultLayout.allDirectories {
            var isDirectory: ObjCBool = false
            let url = tempRoot.appendingPathComponent(name, isDirectory: true)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory))
            XCTAssertTrue(isDirectory.boolValue, "\(name) 应该是一个目录")
        }
    }

    func testEnsureDirectoriesIsIdempotent() throws {
        try VaultLayout.ensureDirectories(in: tempRoot)
        XCTAssertNoThrow(try VaultLayout.ensureDirectories(in: tempRoot))
    }

    func testEnsureDirectoriesRejectsMissingRoot() {
        let missing = tempRoot.appendingPathComponent("does-not-exist")
        XCTAssertThrowsError(try VaultLayout.ensureDirectories(in: missing)) { error in
            guard case VaultLayoutError.missing = error else {
                return XCTFail("期望 missing 错误，实际为 \(error)")
            }
        }
    }

    func testEnsureDirectoriesRejectsFile() throws {
        let file = tempRoot.appendingPathComponent("not-a-dir")
        try "x".write(to: file, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try VaultLayout.ensureDirectories(in: file)) { error in
            guard case VaultLayoutError.notADirectory = error else {
                return XCTFail("期望 notADirectory 错误，实际为 \(error)")
            }
        }
    }

    func testWriteReadRoundtripPreservesUnicode() throws {
        let file = tempRoot.appendingPathComponent("笔记.md")
        let content = "# 线程池\n\n```card\nq: 什么是重入锁？\na: 同一线程可重复获取。\n```\n"

        try FileIO.write(content, to: file)
        XCTAssertEqual(try FileIO.read(file), content)
    }

    func testWriteIsAtomicAndOverwrites() throws {
        let file = tempRoot.appendingPathComponent("note.md")
        try FileIO.write("第一版", to: file)
        try FileIO.write("第二版", to: file)
        XCTAssertEqual(try FileIO.read(file), "第二版")
    }

    func testListMarkdownFilesFiltersAndSorts() throws {
        try FileIO.write("a", to: tempRoot.appendingPathComponent("b-note.md"))
        try FileIO.write("c", to: tempRoot.appendingPathComponent("a-note.md"))
        try FileIO.write("x", to: tempRoot.appendingPathComponent("ignored.txt"))
        try FileIO.write("y", to: tempRoot.appendingPathComponent("UPPER.MD"))

        let found = try FileIO.listMarkdownFiles(in: tempRoot)
        XCTAssertEqual(found.map(\.lastPathComponent), ["a-note.md", "b-note.md", "UPPER.MD"])
    }

    func testAvailableNoteNameAvoidsCollision() throws {
        let first = FileIO.availableNoteName(in: tempRoot, base: "并发")
        XCTAssertEqual(first.lastPathComponent, "并发.md")

        try FileIO.write("", to: first)
        let second = FileIO.availableNoteName(in: tempRoot, base: "并发")
        XCTAssertEqual(second.lastPathComponent, "并发 2.md")

        try FileIO.write("", to: second)
        let third = FileIO.availableNoteName(in: tempRoot, base: "并发")
        XCTAssertEqual(third.lastPathComponent, "并发 3.md")
    }

    func testICloudStatusOfLocalFileIsLocalOrUnknown() throws {
        let file = tempRoot.appendingPathComponent("local.md")
        try FileIO.write("x", to: file)

        let status = FileIO.status(of: file)
        XCTAssertTrue(status == .local || status == .unknown,
                      "非 iCloud 文件应报 local 或 unknown，实际为 \(status)")
    }
}
