import Foundation
import StudyNotesKit

public enum MarkdownHTMLRenderer {
    public static func render(
        source: String,
        title: String,
        kind: MaterialContentKind,
        preferences: IOSReadingPreferences = .init(),
        mediaURLs: [String: URL] = [:]
    ) -> String {
        let body: String
        switch kind {
        case .html, .webArticle:
            body = sanitizedHTML(source)
        default:
            body = markdownBody(source)
        }
        return htmlDocument(
            title: title,
            body: body,
            preferences: preferences,
            mediaURLs: mediaURLs
        )
    }

    public static func plainText(from source: String) -> String {
        source
            .replacingOccurrences(
                of: "```[\\s\\S]*?```",
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: "<[^>]+>",
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: "[#>*_`\\[\\]()]",
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: "\\s+",
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func markdownBody(_ source: String) -> String {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).map(String.init)
        var output: [String] = []
        var blockIndex = 0
        var index = 0

        func appendBlock(_ tag: String, _ content: String, cssClass: String? = nil) {
            let classAttribute = cssClass.map { " class=\"\($0)\"" } ?? ""
            output.append(
                "<\(tag) data-block-id=\"block-\(blockIndex)\"\(classAttribute)>\(inline(content))</\(tag)>"
            )
            blockIndex += 1
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                index += 1
                continue
            }
            if trimmed.hasPrefix("```") {
                index += 1
                var code: [String] = []
                while index < lines.count,
                      !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[index])
                    index += 1
                }
                if index < lines.count {
                    index += 1
                }
                appendBlock("pre", escape(code.joined(separator: "\n")), cssClass: "code")
                continue
            }
            if let heading = heading(trimmed) {
                appendBlock("h\(heading.level)", heading.text)
                index += 1
                continue
            }
            if trimmed.hasPrefix("> ") {
                appendBlock("blockquote", String(trimmed.dropFirst(2)))
                index += 1
                continue
            }
            if trimmed.hasPrefix("- ")
                || trimmed.hasPrefix("* ")
                || trimmed.hasPrefix("+ ") {
                appendBlock("li", String(trimmed.dropFirst(2)), cssClass: "bullet")
                index += 1
                continue
            }
            if trimmed == "---" || trimmed == "***" {
                output.append("<hr>")
                index += 1
                continue
            }
            var paragraph = [trimmed]
            index += 1
            while index < lines.count {
                let next = lines[index].trimmingCharacters(in: .whitespaces)
                if next.isEmpty || startsBlock(next) {
                    break
                }
                paragraph.append(next)
                index += 1
            }
            appendBlock("p", paragraph.joined(separator: " "))
        }
        return output.joined(separator: "\n")
    }

    private static func heading(_ line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count),
              line.dropFirst(hashes.count).first == " " else {
            return nil
        }
        return (
            hashes.count,
            String(line.dropFirst(hashes.count + 1))
        )
    }

    private static func startsBlock(_ line: String) -> Bool {
        line.hasPrefix("#")
            || line.hasPrefix("> ")
            || line.hasPrefix("```")
            || line.hasPrefix("- ")
            || line.hasPrefix("* ")
            || line.hasPrefix("+ ")
            || line == "---"
            || line == "***"
    }

    private static func inline(_ raw: String) -> String {
        var value = escape(raw)
        let replacements: [(String, String)] = [
            (#"!\[([^\]]*)\]\(([^)]+)\)"#, #"<img alt="$1" src="$2">"#),
            (
                #"<img alt="([^"]*)" src="media://([^"]+)">"#,
                #"<img alt="$1" data-media-key="$2" src="">"#
            ),
            (
                #"<a href="media://([^"]+)">([^<]+)</a>"#,
                #"<a data-media-key="$1" href="" download="$2">$2</a>"#
            ),
            ("\\*\\*(.+?)\\*\\*", "<strong>$1</strong>"),
            ("`(.+?)`", "<code>$1</code>"),
            ("\\*(.+?)\\*", "<em>$1</em>"),
            ("\\[([^\\]]+)\\]\\((https?://[^\\)]+)\\)", "<a href=\"$2\">$1</a>")
        ]
        for (pattern, replacement) in replacements {
            value = value.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }
        return value
    }

    private static func sanitizedHTML(_ source: String) -> String {
        let sanitized = source
            .replacingOccurrences(
                of: "<script[\\s\\S]*?</script>",
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(
                of: "\\son[a-z]+\\s*=\\s*(['\"]).*?\\1",
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        return "<div data-block-id=\"block-0\">\(sanitized)</div>"
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func htmlDocument(
        title: String,
        body: String,
        preferences: IOSReadingPreferences,
        mediaURLs: [String: URL]
    ) -> String {
        let mediaMap = mediaURLs.mapValues(\.absoluteString)
        let mediaJSON = (try? JSONSerialization.data(
            withJSONObject: mediaMap,
            options: [.sortedKeys]
        )).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return """
        <!doctype html>
        <html lang="zh-CN">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
          <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src file: data:; style-src 'unsafe-inline'; script-src 'unsafe-inline'; font-src data:">
          <style>
            :root {
              color-scheme: \(colorScheme(preferences.theme));
              --sn-font-size: \(preferences.fontSize)px;
              --sn-line-height: \(preferences.lineHeight);
              --sn-line-width: \(preferences.lineWidth)px;
              --sn-page: #ffffff;
              --sn-ink: #1f2329;
              --sn-text: #4e5969;
              --sn-soft: #f7f8fa;
              --sn-border: #e5e6eb;
              --sn-primary: #3370ff;
            }
            * { box-sizing: border-box; }
            body {
              margin: 0 auto;
              padding: 24px 20px 120px;
              max-width: var(--sn-line-width);
              color: var(--sn-ink);
              background: var(--sn-page);
              font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", sans-serif;
              font-size: var(--sn-font-size);
              line-height: var(--sn-line-height);
              -webkit-text-size-adjust: 100%;
            }
            h1 { font-size: calc(var(--sn-font-size) * 1.75); line-height: 1.35; margin: 0 0 20px; }
            h2 { font-size: calc(var(--sn-font-size) * 1.38); line-height: 1.45; margin: 30px 0 12px; }
            h3, h4, h5, h6 { font-size: calc(var(--sn-font-size) * 1.12); margin: 24px 0 10px; }
            p { margin: 0 0 18px; }
            blockquote {
              margin: 20px 0; padding: 8px 0 8px 16px;
              border-left: 3px solid var(--sn-primary); color: var(--sn-text);
            }
            li.bullet { margin: 3px 0 10px 22px; }
            pre.code {
              overflow-x: auto; padding: 14px; border-radius: 8px;
              background: var(--sn-soft); font-size: calc(var(--sn-font-size) * 0.82); line-height: 1.55;
            }
            code { font-family: "\(escapeAttribute(preferences.codeFont))", ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 0.88em; }
            a { color: var(--sn-primary); }
            img {
              display: block; max-width: 100%; height: auto;
              margin: 20px auto; border-radius: 7px;
            }
            hr { border: 0; border-top: 1px solid var(--sn-border); margin: 28px 0; }
            \(darkModeStyle(preferences.theme))
            ::highlight(studynotes-annotation) {
              background-color: rgba(246, 196, 83, 0.48);
              text-decoration: underline 1px rgba(139, 107, 20, 0.7);
            }
            mark.sn-annotation {
              background: rgba(246, 196, 83, 0.48);
              border-bottom: 1px solid rgba(139, 107, 20, 0.7);
              color: inherit;
            }
            .sn-empty { color: #86909c; }
          </style>
        </head>
        <body data-title="\(escape(title))">
        \(body.isEmpty ? "<p class=\"sn-empty\" data-block-id=\"block-0\">这篇材料还没有可显示的正文。</p>" : body)
        <script>
        const studyNotesMediaURLs = \(mediaJSON);
        document.querySelectorAll("[data-media-key]").forEach((element) => {
          const mapped = studyNotesMediaURLs[element.dataset.mediaKey];
          if (!mapped) return;
          if (element.tagName === "IMG") element.src = mapped;
          else if (element.tagName === "A") {
            element.href = mapped;
            element.download = element.textContent || "附件";
          }
        });
        </script>
        \(selectionScript)
        </body>
        </html>
        """
    }

    private static func colorScheme(_ theme: IOSReadingTheme) -> String {
        switch theme {
        case .system:
            "light dark"
        case .light:
            "light"
        case .dark:
            "dark"
        }
    }

    private static func darkModeStyle(_ theme: IOSReadingTheme) -> String {
        let declarations = """
        :root {
          --sn-page: #17181c;
          --sn-ink: #e8eaed;
          --sn-text: #b8bcc4;
          --sn-soft: #24262c;
          --sn-border: #343740;
          --sn-primary: #77a0ff;
        }
        """
        switch theme {
        case .system:
            return "@media (prefers-color-scheme: dark) {\n\(declarations)\n}"
        case .dark:
            return declarations
        case .light:
            return ""
        }
    }

    private static func escapeAttribute(_ value: String) -> String {
        escape(value).replacingOccurrences(of: "\n", with: " ")
    }

    private static let selectionScript = """
    <script>
    (() => {
      let timer = null;
      const annotations = [];

      function textOffset(root, node, offset) {
        const range = document.createRange();
        range.selectNodeContents(root);
        range.setEnd(node, offset);
        return range.toString().length;
      }

      function closestBlock(node) {
        const element = node.nodeType === Node.ELEMENT_NODE ? node : node.parentElement;
        return element ? element.closest("[data-block-id]") : null;
      }

      function postSelection() {
        const selection = window.getSelection();
        if (!selection || selection.isCollapsed || selection.rangeCount === 0) return;
        const range = selection.getRangeAt(0);
        const block = closestBlock(range.startContainer);
        if (!block) return;
        const quote = selection.toString();
        if (!quote.trim()) return;
        const blockText = block.textContent || "";
        const startOffset = textOffset(block, range.startContainer, range.startOffset);
        const endOffset = Math.max(startOffset + quote.length, textOffset(block, range.endContainer, range.endOffset));
        window.webkit.messageHandlers.selection.postMessage({
          quote,
          prefix: blockText.slice(Math.max(0, startOffset - 42), startOffset),
          suffix: blockText.slice(endOffset, Math.min(blockText.length, endOffset + 42)),
          startOffset,
          endOffset,
          blockPath: block.dataset.blockId
        });
      }

      function rangeForText(root, start, end) {
        const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
        let position = 0;
        let startNode = null;
        let startOffset = 0;
        let endNode = null;
        let endOffset = 0;
        while (walker.nextNode()) {
          const node = walker.currentNode;
          const next = position + node.nodeValue.length;
          if (!startNode && start >= position && start <= next) {
            startNode = node;
            startOffset = start - position;
          }
          if (!endNode && end >= position && end <= next) {
            endNode = node;
            endOffset = end - position;
            break;
          }
          position = next;
        }
        if (!startNode || !endNode) return null;
        const range = document.createRange();
        range.setStart(startNode, startOffset);
        range.setEnd(endNode, endOffset);
        return range;
      }

      function rebuildHighlights() {
        if (window.CSS && CSS.highlights) {
          CSS.highlights.delete("studynotes-annotation");
          const highlight = new Highlight();
          annotations.forEach(item => {
            const block = document.querySelector(`[data-block-id="${item.blockPath}"]`);
            if (!block) return;
            const range = rangeForText(block, item.startOffset, item.endOffset);
            if (range) highlight.add(range);
          });
          CSS.highlights.set("studynotes-annotation", highlight);
        }
      }

      window.highlightAnnotations = function(items) {
        annotations.length = 0;
        annotations.push(...items);
        rebuildHighlights();
      };

      window.scrollToAnnotation = function(blockPath) {
        const block = document.querySelector(`[data-block-id="${blockPath}"]`);
        if (block) block.scrollIntoView({ behavior: "smooth", block: "center" });
      };

      document.addEventListener("selectionchange", () => {
        clearTimeout(timer);
        timer = setTimeout(postSelection, 260);
      });
    })();
    </script>
    """
}
