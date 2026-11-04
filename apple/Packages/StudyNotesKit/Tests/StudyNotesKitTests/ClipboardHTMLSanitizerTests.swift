import Testing
@testable import StudyNotesKit

@Suite("Clipboard HTML sanitizer")
struct ClipboardHTMLSanitizerTests {
    @Test("allowed Word and table markup is retained without scripts")
    func safeMarkup() {
        let html = """
        <h2>Plan</h2>
        <p style="color: #b42318">Text</p>
        <table><tr><th colspan="2">Name</th></tr></table>
        """
        let result = ClipboardHTMLSanitizer().sanitize(html)

        guard case let .clean(output) = result else {
            Issue.record("Expected clean output, got \(result)")
            return
        }
        #expect(output.contains("<h2>"))
        #expect(output.contains("color: #b42318"))
        #expect(output.contains("colspan=\"2\""))
    }

    @Test("remote styles force a compatibility block")
    func remoteStyle() {
        let html = #"<p style="background-image: url(https://example.com/x)">Text</p>"#
        let result = ClipboardHTMLSanitizer().sanitize(html)

        guard case let .preservedCompatibility(source, reasons) = result
        else {
            Issue.record("Expected a compatibility block")
            return
        }
        #expect(source == html)
        #expect(reasons.contains { $0.contains("background-image") })
    }

    @Test("script, event handlers and executable URLs preserve the source")
    func unsafeMarkup() {
        let html = """
        <p onclick="steal()">unsafe</p>
        <script>window.secret = 1</script>
        <a href="javascript:alert(1)">link</a>
        """
        let result = ClipboardHTMLSanitizer().sanitize(html)

        guard case let .preservedCompatibility(source, reasons) = result
        else {
            Issue.record("Expected a compatibility block")
            return
        }
        #expect(source == html)
        #expect(!reasons.isEmpty)
    }

    @Test("unknown tags fail closed and keep the original source")
    func unknownMarkup() {
        let html = "<marquee>old</marquee>"
        let result = ClipboardHTMLSanitizer().sanitize(html)
        guard case let .preservedCompatibility(source, reasons) = result
        else {
            Issue.record("Expected a compatibility block")
            return
        }
        #expect(source == html)
        #expect(reasons.contains { $0.contains("marquee") })
    }
}
