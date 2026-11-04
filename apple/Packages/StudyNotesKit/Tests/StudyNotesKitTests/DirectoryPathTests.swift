import XCTest
@testable import StudyNotesKit

final class DirectoryPathTests: XCTestCase {
    func testExpandedAncestorsIncludeRootAndEachPrefix() {
        XCTAssertEqual(
            DirectoryPath.expandedAncestors(of: "Alpha/Beta"),
            ["", "Alpha", "Alpha/Beta"]
        )
    }

    func testRebaseUpdatesMatchingPathAndDescendants() {
        let paths: Set<String> = [
            "",
            "Alpha",
            "Alpha/Beta",
            "Archive"
        ]

        XCTAssertEqual(
            DirectoryPath.rebase(
                paths,
                from: "Alpha",
                to: "Archive/Alpha"
            ),
            ["", "Archive", "Archive/Alpha", "Archive/Alpha/Beta"]
        )
    }
}
