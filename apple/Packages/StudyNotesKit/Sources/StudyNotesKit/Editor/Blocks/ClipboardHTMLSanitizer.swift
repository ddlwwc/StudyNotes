import Foundation

public enum ClipboardHTMLSanitizationResult: Equatable, Sendable {
    case clean(String)
    case preservedCompatibility(html: String, reasons: [String])
}

public struct ClipboardHTMLSanitizer: Sendable {
    private static let allowedTags: Set<String> = [
        "a", "b", "blockquote", "br", "code", "del", "div", "em",
        "h1", "h2", "h3", "h4", "h5", "h6", "hr", "i", "img",
        "li", "ol", "p", "pre", "s", "span", "strong", "table",
        "tbody", "td", "th", "thead", "tr", "u", "ul"
    ]
    private static let voidTags: Set<String> = ["br", "hr", "img"]
    private static let blockedTags: Set<String> = [
        "applet", "base", "embed", "form", "frame", "frameset",
        "iframe", "link", "meta", "object", "script", "style",
        "svg", "template"
    ]
    private static let allowedAttributes: Set<String> = [
        "alt", "colspan", "height", "href", "rowspan", "src", "style",
        "title", "width"
    ]

    public init() {}

    public func sanitize(_ html: String) -> ClipboardHTMLSanitizationResult {
        var reasons: [String] = []
        let pattern = #"<\s*(/?)\s*([A-Za-z][A-Za-z0-9:-]*)([^>]*)>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return .preservedCompatibility(
                html: html,
                reasons: ["无法初始化 HTML 安全扫描器。"]
            )
        }
        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, range: range)
        var output = ""
        var cursor = html.startIndex

        for match in matches {
            guard let wholeRange = Range(match.range, in: html),
                  let closingRange = Range(match.range(at: 1), in: html),
                  let tagRange = Range(match.range(at: 2), in: html),
                  let attributesRange = Range(match.range(at: 3), in: html)
            else {
                continue
            }
            output += String(html[cursor..<wholeRange.lowerBound])
            let tag = String(html[tagRange]).lowercased()
            let isClosing = !html[closingRange].isEmpty
            if Self.blockedTags.contains(tag) {
                reasons.append("移除了不允许的 <\(tag)>；原始 HTML 保留为兼容块。")
                cursor = wholeRange.upperBound
                continue
            }
            guard Self.allowedTags.contains(tag) else {
                reasons.append("未知标签 <\(tag)> 保留为兼容块。")
                cursor = wholeRange.upperBound
                continue
            }
            if isClosing {
                if !Self.voidTags.contains(tag) {
                    output += "</\(tag)>"
                }
            } else {
                let attributes = sanitizeAttributes(
                    String(html[attributesRange]),
                    tag: tag,
                    reasons: &reasons
                )
                output += "<\(tag)\(attributes)>"
            }
            cursor = wholeRange.upperBound
        }
        output += String(html[cursor...])

        if let extra = unsafeMarkupReason(in: output) {
            reasons.append(extra)
        }
        if reasons.isEmpty {
            return .clean(output)
        }
        return .preservedCompatibility(
            html: html,
            reasons: Array(Set(reasons)).sorted()
        )
    }

    private func sanitizeAttributes(
        _ source: String,
        tag: String,
        reasons: inout [String]
    ) -> String {
        let pattern = #"([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*("([^"]*)"|'([^']*)'|([^\s"'=<>`]+))"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return ""
        }
        let range = NSRange(source.startIndex..., in: source)
        var attributes: [String: String] = [:]

        for match in regex.matches(in: source, range: range) {
            guard let nameRange = Range(match.range(at: 1), in: source)
            else {
                continue
            }
            let name = String(source[nameRange]).lowercased()
            guard !name.hasPrefix("on"),
                  Self.allowedAttributes.contains(name)
            else {
                reasons.append("移除了不允许的属性 \(name)。")
                continue
            }
            let value = firstCapturedValue(
                match: match,
                source: source,
                ranges: [3, 4, 5]
            )
            switch name {
            case "href", "src":
                let lower = value.lowercased()
                guard lower.hasPrefix("https://")
                        || lower.hasPrefix("http://")
                        || lower.hasPrefix("mailto:")
                        || lower.hasPrefix("media://qiniu/")
                        || lower.hasPrefix("data:image/")
                else {
                    reasons.append("移除了不安全 URL。")
                    continue
                }
                attributes[name] = value
            case "style":
                attributes[name] = sanitizedStyle(value, reasons: &reasons)
            case "colspan", "rowspan", "width", "height":
                if Int(value) != nil {
                    attributes[name] = value
                } else {
                    reasons.append("移除了非数值属性 \(name)。")
                }
            default:
                attributes[name] = value
            }
        }

        if tag == "a", attributes["href"] != nil {
            attributes["rel"] = "noopener noreferrer"
            attributes["target"] = "_blank"
        }
        return attributes.keys.sorted().map { key in
            " \(key)=\"\(escape(attributes[key] ?? ""))\""
        }.joined()
    }

    private func sanitizedStyle(
        _ source: String,
        reasons: inout [String]
    ) -> String {
        let allowed: Set<String> = [
            "background-color", "color", "font-size", "line-height",
            "text-align"
        ]
        var result: [String] = []
        for declaration in source.split(separator: ";") {
            let parts = declaration.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else {
                continue
            }
            let name = parts[0].trimmingCharacters(
                in: .whitespacesAndNewlines
            ).lowercased()
            let value = parts[1].trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard allowed.contains(name),
                  !value.lowercased().contains("url("),
                  !value.lowercased().contains("expression("),
                  !value.lowercased().contains("javascript:")
            else {
                reasons.append("移除了不允许的样式 \(name)。")
                continue
            }
            result.append("\(name): \(value)")
        }
        return result.joined(separator: "; ")
    }

    private func firstCapturedValue(
        match: NSTextCheckingResult,
        source: String,
        ranges: [Int]
    ) -> String {
        for index in ranges {
            guard match.range(at: index).location != NSNotFound,
                  let range = Range(match.range(at: index), in: source)
            else {
                continue
            }
            return String(source[range])
        }
        return ""
    }

    private func unsafeMarkupReason(in html: String) -> String? {
        let lower = html.lowercased()
        if lower.contains("javascript:") {
            return "检测到 javascript: URL。"
        }
        if lower.range(
            of: #"\son[a-z]+\s*="#,
            options: .regularExpression
        ) != nil {
            return "检测到内联事件处理器。"
        }
        return nil
    }

    private func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
