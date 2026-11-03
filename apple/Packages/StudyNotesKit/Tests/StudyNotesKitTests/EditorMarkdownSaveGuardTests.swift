import Testing
@testable import StudyNotesKit

@Suite("Markdown save guard")
struct MarkdownSaveGuardTests {
    @Test("allows only matching fingerprints")
    func matchingFingerprint() {
        let guardrail = MarkdownSaveGuard()

        #expect(
            guardrail.decision(
                expectedFingerprint: "sha256:before",
                currentFingerprint: "sha256:before"
            ) == .save
        )
    }

    @Test("reports a conflict with both fingerprints")
    func conflictingFingerprint() {
        let guardrail = MarkdownSaveGuard()

        #expect(
            guardrail.decision(
                expectedFingerprint: "sha256:before",
                currentFingerprint: "sha256:external"
            ) == .conflict(
                expectedFingerprint: "sha256:before",
                currentFingerprint: "sha256:external"
            )
        )
    }
}
