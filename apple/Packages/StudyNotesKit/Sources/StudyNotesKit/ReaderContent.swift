import CryptoKit
import Foundation

public enum StudyNotesContentError: Error, Equatable, Sendable, LocalizedError {
    case unreadableFile
    case unsupportedFileType(String)
    case invalidPDF
    case invalidImage
    case invalidWebArticle

    public var errorDescription: String? {
        switch self {
        case .unreadableFile:
            "无法读取所选文件。"
        case .unsupportedFileType(let fileExtension):
            "暂不支持导入 \(fileExtension.isEmpty ? "该类型" : ".\(fileExtension)") 文件。"
        case .invalidPDF:
            "所选 PDF 文件无法打开。"
        case .invalidImage:
            "所选图片文件无法打开。"
        case .invalidWebArticle:
            "网页中没有提取到可阅读的正文。"
        }
    }
}

public enum ContentFingerprint {
    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func sha256(_ string: String) -> String {
        sha256(Data(string.utf8))
    }
}

public struct ReaderContent: Equatable, Sendable {
    public let markdown: String
    public let html: String
    public let headings: [ReaderHeading]

    public init(markdown: String, html: String, headings: [ReaderHeading]) {
        self.markdown = markdown
        self.html = html
        self.headings = headings
    }
}

public enum ReaderContentBuilder {
    public static func build(
        markdown: String,
        title: String,
        mediaURLs: [String: URL] = [:]
    ) -> ReaderContent {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let result = MarkdownHTMLRenderer.render(normalized)
        let html = documentShell(
            title: title,
            body: result.html,
            mediaURLs: mediaURLs
        )
        return ReaderContent(markdown: normalized, html: html, headings: result.headings)
    }

    public static func htmlToMarkdown(_ html: String) -> String {
        let body = HTMLTextExtractor.extractReadableHTML(html)
        return HTMLTextExtractor.htmlToMarkdown(body)
    }

    public static func publicationHTML(
        title: String,
        markdown: String,
        annotations: [PublishedAnnotation],
        aiAppendix: String?
    ) -> String {
        var body = MarkdownHTMLRenderer.render(markdown).html
        if !annotations.isEmpty {
            let annotationItems = annotations.map { annotation in
                """
                <aside class="published-annotation" data-annotation-id="\(annotation.id.uuidString)">
                  <blockquote>\(escape(annotation.quote))</blockquote>
                  <p>\(escape(annotation.note))</p>
                </aside>
                """
            }.joined(separator: "\n")
            body += "<section class=\"published-annotations\"><h2>标注</h2>\(annotationItems)</section>"
        }
        if let aiAppendix, !aiAppendix.isEmpty {
            body += """
            <details class="study-appendix">
              <summary>AI 研读附录</summary>
              \(MarkdownHTMLRenderer.render(aiAppendix).html)
            </details>
            """
        }
        let annotationData = annotations.map {
            [
                "id": $0.id.uuidString,
                "quote": $0.quote,
                "note": $0.note
            ]
        }
        let annotationJSON = (try? JSONSerialization.data(
            withJSONObject: annotationData,
            options: [.sortedKeys]
        )).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return """
        <!doctype html>
        <html lang="zh-CN">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(escape(title))</title>
          <style>
            :root { color-scheme: light; }
            body { max-width: 760px; margin: 0 auto; padding: 48px 28px 80px; color: #1f2937;
                   font: 17px/1.85 -apple-system, BlinkMacSystemFont, "PingFang SC", sans-serif; }
            h1, h2, h3 { color: #111827; line-height: 1.35; margin-top: 1.7em; }
            blockquote { margin: 1.2em 0; padding-left: 16px; border-left: 3px solid #3370ff; color: #4b5563; }
            code, pre { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; background: #f3f4f6; }
            pre { padding: 16px; overflow: auto; border-radius: 6px; }
            img { max-width: 100%; height: auto; border-radius: 6px; }
            .published-annotation, .study-appendix { margin: 20px 0; padding: 16px; border: 1px solid #e5e7eb;
                                                     border-radius: 6px; background: #fffdf6; }
            .study-appendix { background: #f8f7ff; }
            mark.published-highlight { background: #fff1a8; color: inherit; border-radius: 2px; }
          </style>
        </head>
        <body>
          <article>
            <h1>\(escape(title))</h1>
            \(body)
          </article>
          <script>
            const publishedAnnotations = \(annotationJSON);
            const article = document.querySelector('article');
            for (const item of publishedAnnotations) {
              if (!item.quote || !article) continue;
              const walker = document.createTreeWalker(article, NodeFilter.SHOW_TEXT);
              let textNode;
              while ((textNode = walker.nextNode())) {
                const index = textNode.nodeValue.indexOf(item.quote);
                if (index < 0) continue;
                const range = document.createRange();
                range.setStart(textNode, index);
                range.setEnd(textNode, index + item.quote.length);
                const mark = document.createElement('mark');
                mark.className = 'published-highlight';
                mark.title = item.note || '';
                range.surroundContents(mark);
                break;
              }
            }
          </script>
        </body>
        </html>
        """
    }

    private static func documentShell(
        title: String,
        body: String,
        mediaURLs: [String: URL]
    ) -> String {
        let mediaMap = mediaURLs.mapValues(\.absoluteString)
        let mediaJSON = (try? JSONSerialization.data(withJSONObject: mediaMap, options: [.sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return """
        <!doctype html>
        <html lang="zh-CN">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(escape(title))</title>
          <style>
            :root { color-scheme: light; }
            * { box-sizing: border-box; }
            html, body { margin: 0; min-height: 100%; background: #ffffff; }
            body { color: #374151; font: 16px/1.82 "New York", "Songti SC", serif;
                   padding: 0 36px 64px; }
            article { max-width: 648px; margin: 0 auto; }
            h1, h2, h3, h4, h5, h6 { color: #111827; font-family: -apple-system, BlinkMacSystemFont,
              "PingFang SC", sans-serif; line-height: 1.35; scroll-margin-top: 24px; }
            h1 { font-size: 36px; margin: 0 0 18px; }
            h2 { font-size: 25px; margin: 34px 0 12px; }
            h3 { font-size: 20px; margin: 28px 0 10px; }
            p { margin: 0 0 18px; }
            blockquote { margin: 22px 0; padding: 2px 0 2px 15px; border-left: 3px solid #3370ff;
                         color: #4b5563; }
            ul, ol { padding-left: 24px; margin: 0 0 18px; }
            li { margin: 5px 0; }
            pre { padding: 14px; overflow: auto; border: 1px solid #e5e7eb; border-radius: 6px;
                  background: #f7f8fa; color: #111827; font: 12px/1.6 ui-monospace, SFMono-Regular, Menlo, monospace; }
            code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
            img { display: block; max-width: 100%; height: auto; margin: 24px auto; border-radius: 6px; }
            mark.study-annotation { background: #fff1a8; color: inherit; border-radius: 2px; cursor: pointer; }
            mark.study-annotation.unresolved { background: #fee2b3; outline: 1px dashed #b45309; }
            ::selection { background: #bcd2ff; }
          </style>
        </head>
        <body>
          <article data-study-title="\(escape(title))">
            \(body)
          </article>
          <script>
            window.studyNotesMediaURLs = \(mediaJSON);
            document.querySelectorAll('[data-media-key]').forEach((element) => {
              const mapped = window.studyNotesMediaURLs[element.dataset.mediaKey];
              if (!mapped) return;
              if (element.tagName === 'IMG') element.src = mapped;
              else if (element.tagName === 'A') {
                element.href = mapped;
                element.download = element.textContent || '附件';
              }
            });
            window.studyNotesCurrentSelection = function() {
              const selection = window.getSelection();
              if (!selection || selection.rangeCount === 0 || selection.isCollapsed) return null;
              const range = selection.getRangeAt(0);
              const article = document.querySelector('article');
              if (!article || !article.contains(range.commonAncestorContainer)) return null;
              const quote = selection.toString().trim();
              if (!quote) return null;
              const preRange = document.createRange();
              preRange.selectNodeContents(article);
              preRange.setEnd(range.startContainer, range.startOffset);
              const offset = preRange.toString().length;
              const full = article.innerText || article.textContent || '';
              const startElement = range.startContainer.nodeType === Node.ELEMENT_NODE
                ? range.startContainer
                : range.startContainer.parentElement;
              const block = startElement.closest('article > *');
              const blockPath = block ? [Array.from(article.children).indexOf(block)] : [];
              return {
                quote: quote,
                prefix: full.slice(Math.max(0, offset - 48), offset),
                suffix: full.slice(offset + quote.length, offset + quote.length + 48),
                offset: offset,
                blockPath: blockPath
              };
            };
            window.studyNotesScrollToHeading = function(id) {
              const element = document.getElementById(id);
              if (element) element.scrollIntoView({ block: 'start', behavior: 'smooth' });
            };
            window.studyNotesScrollToText = function(quote) {
              if (!quote) return false;
              const walker = document.createTreeWalker(document.querySelector('article'), NodeFilter.SHOW_TEXT);
              let node;
              while ((node = walker.nextNode())) {
                const index = node.nodeValue.indexOf(quote);
                if (index >= 0) {
                  const range = document.createRange();
                  range.setStart(node, index);
                  range.setEnd(node, index + quote.length);
                  const rect = range.getBoundingClientRect();
                  window.scrollTo({ top: window.scrollY + rect.top - 80, behavior: 'smooth' });
                  return true;
                }
              }
              return false;
            };
            window.studyNotesApplyAnnotations = function(items) {
              const article = document.querySelector('article');
              if (!article || !Array.isArray(items)) return;
              for (const item of items.slice().sort((a, b) => b.quote.length - a.quote.length)) {
                if (!item.quote) continue;
                const walker = document.createTreeWalker(article, NodeFilter.SHOW_TEXT);
                let node;
                while ((node = walker.nextNode())) {
                  if (node.parentElement.closest('mark.study-annotation')) continue;
                  const index = node.nodeValue.indexOf(item.quote);
                  if (index < 0) continue;
                  const range = document.createRange();
                  range.setStart(node, index);
                  range.setEnd(node, index + item.quote.length);
                  const mark = document.createElement('mark');
                  mark.className = 'study-annotation' + (item.unresolved ? ' unresolved' : '');
                  mark.dataset.annotationId = item.id;
                  mark.title = item.note || item.quote;
                  mark.addEventListener('click', () => {
                    window.webkit.messageHandlers.annotationClick.postMessage(item.id);
                  });
                  range.surroundContents(mark);
                  break;
                }
              }
            };
            window.studyNotesFind = function(query, backwards) {
              if (!query) return false;
              return window.find(query, false, backwards, true, false, false, false);
            };
            const publishSelection = () => {
              const selection = window.studyNotesCurrentSelection();
              if (selection) {
                window.webkit.messageHandlers.selectionChanged.postMessage(selection);
              }
            };
            document.addEventListener('mouseup', () => setTimeout(publishSelection, 0));
            document.addEventListener('keyup', () => setTimeout(publishSelection, 0));
          </script>
        </body>
        </html>
        """
    }

    static func escape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

public enum TextAnchorResolver {
    public static func range(for anchor: AnnotationAnchor, in text: String) -> NSRange? {
        let blocks = text.components(separatedBy: "\n\n")
        return range(for: anchor, in: text, blocks: blocks)
    }

    public static func range(
        for anchor: AnnotationAnchor,
        in text: String,
        blocks: [String]
    ) -> NSRange? {
        guard !anchor.excerpt.isEmpty else {
            guard let offset = anchor.offset, offset <= text.utf16.count else {
                return nil
            }
            return NSRange(location: offset, length: 0)
        }

        let source = text as NSString
        let excerptLength = (anchor.excerpt as NSString).length
        guard excerptLength > 0, source.length >= excerptLength else {
            return nil
        }

        if let blockIndex = anchor.blockPath.first,
           blocks.indices.contains(blockIndex) {
            let block = blocks[blockIndex] as NSString
            let localRange = block.range(of: anchor.excerpt)
            let blockRange = source.range(of: blocks[blockIndex])
            if localRange.location != NSNotFound,
               blockRange.location != NSNotFound {
                return NSRange(
                    location: blockRange.location + localRange.location,
                    length: localRange.length
                )
            }
        }

        var candidates: [NSRange] = []
        var searchRange = NSRange(location: 0, length: source.length)
        while searchRange.length > 0 {
            let range = source.range(of: anchor.excerpt, options: [], range: searchRange)
            if range.location == NSNotFound {
                break
            }
            candidates.append(range)
            let nextLocation = range.location + max(range.length, 1)
            guard nextLocation < source.length else {
                break
            }
            searchRange = NSRange(location: nextLocation, length: source.length - nextLocation)
        }

        guard !candidates.isEmpty else {
            return nil
        }
        if candidates.count == 1 {
            return candidates[0]
        }

        return candidates.max { left, right in
            score(candidate: left, anchor: anchor, source: source)
                < score(candidate: right, anchor: anchor, source: source)
        }
    }

    private static func score(
        candidate: NSRange,
        anchor: AnnotationAnchor,
        source: NSString
    ) -> Int {
        var score = 0
        if !anchor.prefix.isEmpty {
            let start = max(0, candidate.location - (anchor.prefix as NSString).length)
            let prefixRange = NSRange(
                location: start,
                length: candidate.location - start
            )
            if source.substring(with: prefixRange).hasSuffix(anchor.prefix) {
                score += 4
            }
        }
        if !anchor.suffix.isEmpty {
            let end = candidate.location + candidate.length
            let length = min((anchor.suffix as NSString).length, source.length - end)
            let suffixRange = NSRange(location: end, length: length)
            if source.substring(with: suffixRange).hasPrefix(anchor.suffix) {
                score += 4
            }
        }
        if let offset = anchor.offset {
            score -= abs(offset - candidate.location) / 20
        }
        return score
    }
}

private enum MarkdownHTMLRenderer {
    struct Result {
        let html: String
        let headings: [ReaderHeading]
    }

    static func render(_ markdown: String) -> Result {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var html: [String] = []
        var headings: [ReaderHeading] = []
        var index = 0
        var headingIndex = 0
        var listKind: String?

        func closeList() {
            if let listKind {
                html.append("</\(listKind)>")
            }
            listKind = nil
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                closeList()
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                closeList()
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                index += 1
                var codeLines: [String] = []
                while index < lines.count,
                      !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[index])
                    index += 1
                }
                if index < lines.count {
                    index += 1
                }
                let languageAttribute = language.isEmpty ? "" : " class=\"language-\(ReaderContentBuilder.escape(language))\""
                html.append("<pre><code\(languageAttribute)>\(ReaderContentBuilder.escape(codeLines.joined(separator: "\n")))</code></pre>")
                continue
            }

            if let heading = heading(from: trimmed) {
                closeList()
                let id = "heading-\(headingIndex)"
                headingIndex += 1
                headings.append(ReaderHeading(id: id, level: heading.level, title: heading.text))
                html.append("<h\(heading.level) id=\"\(id)\">\(inline(heading.text))</h\(heading.level)>")
                index += 1
                continue
            }

            if trimmed == "---" || trimmed == "***" {
                closeList()
                html.append("<hr>")
                index += 1
                continue
            }

            if trimmed.hasPrefix("> ") {
                closeList()
                var quoteLines: [String] = []
                while index < lines.count,
                      lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("> ") {
                    quoteLines.append(String(lines[index].trimmingCharacters(in: .whitespaces).dropFirst(2)))
                    index += 1
                }
                html.append("<blockquote><p>\(inline(quoteLines.joined(separator: " ")))</p></blockquote>")
                continue
            }

            if let item = unorderedItem(from: trimmed) {
                if listKind != "ul" {
                    closeList()
                    html.append("<ul>")
                    listKind = "ul"
                }
                html.append("<li>\(inline(item))</li>")
                index += 1
                continue
            }

            if let item = orderedItem(from: trimmed) {
                if listKind != "ol" {
                    closeList()
                    html.append("<ol>")
                    listKind = "ol"
                }
                html.append("<li>\(inline(item))</li>")
                index += 1
                continue
            }

            closeList()
            var paragraphLines = [trimmed]
            index += 1
            while index < lines.count {
                let next = lines[index].trimmingCharacters(in: .whitespaces)
                if next.isEmpty || startsBlock(next) {
                    break
                }
                paragraphLines.append(next)
                index += 1
            }
            html.append("<p>\(inline(paragraphLines.joined(separator: " ")))</p>")
        }

        closeList()
        return Result(html: html.joined(separator: "\n"), headings: headings)
    }

    private static func heading(from line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count),
              line.dropFirst(hashes.count).first == " " else {
            return nil
        }
        return (hashes.count, String(line.dropFirst(hashes.count + 1)))
    }

    private static func unorderedItem(from line: String) -> String? {
        for prefix in ["- ", "* ", "+ "] where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count))
        }
        return nil
    }

    private static func orderedItem(from line: String) -> String? {
        guard let dot = line.firstIndex(of: "."),
              Int(line[..<dot]) != nil,
              line.index(after: dot) < line.endIndex,
              line[line.index(after: dot)] == " " else {
            return nil
        }
        let textStart = line.index(dot, offsetBy: 2)
        return String(line[textStart...])
    }

    private static func startsBlock(_ line: String) -> Bool {
        line.hasPrefix("#")
            || line.hasPrefix("> ")
            || line.hasPrefix("```")
            || line.hasPrefix("- ")
            || line.hasPrefix("* ")
            || line.hasPrefix("+ ")
            || orderedItem(from: line) != nil
            || line == "---"
            || line == "***"
    }

    private static func inline(_ text: String) -> String {
        var escaped = ReaderContentBuilder.escape(text)
        escaped = escaped.replacingOccurrences(
            of: #"!\[([^\]]*)\]\(([^)]+)\)"#,
            with: #"<img alt="$1" src="$2">"#,
            options: .regularExpression
        )
        escaped = escaped.replacingOccurrences(
            of: #"<img alt="([^"]*)" src="media://([^"]+)">"#,
            with: #"<img alt="$1" data-media-key="$2" src="">"#,
            options: .regularExpression
        )
        escaped = escaped.replacingOccurrences(
            of: #"<a href="media://([^"]+)">([^<]+)</a>"#,
            with: #"<a data-media-key="$1" href="" download="$2">$2</a>"#,
            options: .regularExpression
        )
        escaped = escaped.replacingOccurrences(
            of: #"\[([^\]]+)\]\(([^)]+)\)"#,
            with: #"<a href="$2">$1</a>"#,
            options: .regularExpression
        )
        escaped = escaped.replacingOccurrences(
            of: #"\*\*([^*]+)\*\*"#,
            with: #"<strong>$1</strong>"#,
            options: .regularExpression
        )
        escaped = escaped.replacingOccurrences(
            of: #"`([^`]+)`"#,
            with: #"<code>$1</code>"#,
            options: .regularExpression
        )
        return escaped
    }
}

public enum HTMLTextExtractor {
    public static func extractReadableHTML(_ html: String) -> String {
        let withoutHidden = replacing(
            html,
            pattern: #"(?is)<(script|style|noscript|svg|canvas)[^>]*>.*?</\1>"#,
            with: ""
        )
        for pattern in [
            #"(?is)<article\b[^>]*>(.*?)</article>"#,
            #"(?is)<main\b[^>]*>(.*?)</main>"#,
            #"(?is)<body\b[^>]*>(.*?)</body>"#
        ] {
            if let match = firstCapture(pattern: pattern, in: withoutHidden) {
                return match
            }
        }
        return withoutHidden
    }

    public static func htmlToMarkdown(_ html: String) -> String {
        var text = replacing(
            html,
            pattern: #"(?is)<(nav|header|footer|aside|form|button|script|style)[^>]*>.*?</\1>"#,
            with: "\n"
        )
        text = markdownImages(in: text)
        text = replacing(text, pattern: #"(?is)<br\s*/?>"#, with: "\n")
        text = replacing(text, pattern: #"(?is)</(p|div|section|article|li|blockquote|pre)>"#, with: "\n\n")
        text = replacing(text, pattern: #"(?is)<h1\b[^>]*>"#, with: "\n# ")
        text = replacing(text, pattern: #"(?is)</h1>"#, with: "\n\n")
        text = replacing(text, pattern: #"(?is)<h2\b[^>]*>"#, with: "\n## ")
        text = replacing(text, pattern: #"(?is)</h2>"#, with: "\n\n")
        text = replacing(text, pattern: #"(?is)<h3\b[^>]*>"#, with: "\n### ")
        text = replacing(text, pattern: #"(?is)</h3>"#, with: "\n\n")
        text = replacing(text, pattern: #"(?is)<h[4-6]\b[^>]*>"#, with: "\n#### ")
        text = replacing(text, pattern: #"(?is)</h[4-6]>"#, with: "\n\n")
        text = replacing(text, pattern: #"(?is)<li\b[^>]*>"#, with: "- ")
        text = replacing(text, pattern: #"(?is)<blockquote\b[^>]*>"#, with: "> ")
        text = replacing(text, pattern: #"(?is)<[^>]+>"#, with: "")
        text = decodeEntities(text)
        let lines = text
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var compacted: [String] = []
        for line in lines {
            if line.isEmpty {
                if compacted.last?.isEmpty == false {
                    compacted.append("")
                }
            } else {
                compacted.append(line)
            }
        }
        return compacted.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func title(from html: String) -> String? {
        let patterns = [
            #"(?is)<meta\s+property=["']og:title["']\s+content=["']([^"']+)["']"#,
            #"(?is)<title\b[^>]*>(.*?)</title>"#,
            #"(?is)<h1\b[^>]*>(.*?)</h1>"#
        ]
        for pattern in patterns {
            if let raw = firstCapture(pattern: pattern, in: html) {
                let title = htmlToMarkdown(raw)
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty {
                    return title
                }
            }
        }
        return nil
    }

    public static func imageSources(from html: String, baseURL: URL) -> [URL] {
        let pattern = #"(?is)<img\b[^>]*\bsrc=["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let source = html as NSString
        var seen = Set<String>()
        return regex.matches(in: html, range: NSRange(location: 0, length: source.length))
            .compactMap { match -> URL? in
                guard match.numberOfRanges > 1 else {
                    return nil
                }
                let raw = source.substring(with: match.range(at: 1))
                guard let url = URL(string: raw, relativeTo: baseURL)?.absoluteURL,
                      ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                      seen.insert(url.absoluteString).inserted else {
                    return nil
                }
                return url
            }
    }

    private static func firstCapture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let source = text as NSString
        guard let match = regex.firstMatch(
            in: text,
            range: NSRange(location: 0, length: source.length)
        ), match.numberOfRanges > 1,
        match.range(at: 1).location != NSNotFound else {
            return nil
        }
        return source.substring(with: match.range(at: 1))
    }

    private static func markdownImages(in text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?is)<img\b([^>]*)>"#
        ) else {
            return text
        }
        let source = text as NSString
        let matches = regex.matches(
            in: text,
            range: NSRange(location: 0, length: source.length)
        )
        var result = text
        for match in matches.reversed() {
            let attributes = source.substring(with: match.range(at: 1))
            let src = attribute("src", in: attributes) ?? ""
            guard !src.isEmpty else {
                continue
            }
            let alt = attribute("alt", in: attributes) ?? ""
            result = (result as NSString).replacingCharacters(
                in: match.range,
                with: "![\(alt)](\(src))"
            )
        }
        return result
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = #"(?is)\b\#(name)\s*=\s*["']([^"']*)["']"#
        return firstCapture(pattern: pattern, in: tag)
    }

    private static func replacing(_ text: String, pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: replacement
        )
    }

    private static func decodeEntities(_ text: String) -> String {
        var decoded = text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
        guard let regex = try? NSRegularExpression(pattern: #"&#(x?[0-9A-Fa-f]+);"#) else {
            return decoded
        }
        let matches = regex.matches(
            in: decoded,
            range: NSRange(location: 0, length: (decoded as NSString).length)
        )
        for match in matches.reversed() {
            let source = decoded as NSString
            let body = source.substring(with: match.range(at: 1))
            let value: UInt32?
            if body.lowercased().hasPrefix("x") {
                value = UInt32(String(body.dropFirst()), radix: 16)
            } else {
                value = UInt32(body, radix: 10)
            }
            if let value, let scalar = UnicodeScalar(value) {
                decoded = (decoded as NSString).replacingCharacters(
                    in: match.range,
                    with: String(Character(scalar))
                )
            }
        }
        return decoded
    }
}
