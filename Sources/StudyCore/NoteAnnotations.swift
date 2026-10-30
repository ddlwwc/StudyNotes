import Foundation

public struct Highlight: Identifiable, Equatable, Sendable {
    public var id: String
    public var range: NSRange
    public var note: String

    public init(id: String = UUID().uuidString, range: NSRange, note: String = "") {
        self.id = id
        self.range = range
        self.note = note
    }
}

public enum NoteAnnotations {
    public static let marker = "=="

    public static func stripHighlights(_ source: String) -> String {
        let ns = source as NSString
        var result: [String] = []
        var index = 0

        while index < ns.length {
            let remaining = NSRange(location: index, length: ns.length - index)
            let open = ns.range(of: marker, options: [], range: remaining)
            guard open.location != NSNotFound else {
                result.append(ns.substring(from: index))
                break
            }

            if open.location > index {
                result.append(ns.substring(with: NSRange(
                    location: index,
                    length: open.location - index
                )))
            }

            let innerStart = open.location + marker.count
            guard innerStart <= ns.length else { break }
            let closeSearch = NSRange(location: innerStart, length: ns.length - innerStart)
            let close = ns.range(of: marker, options: [], range: closeSearch)

            guard close.location != NSNotFound else {
                result.append(ns.substring(from: open.location))
                break
            }

            let innerLength = close.location - innerStart
            if innerLength > 0 {
                result.append(ns.substring(with: NSRange(location: innerStart, length: innerLength)))
            }
            index = close.location + marker.count
        }

        return result.joined()
    }

    public static func apply(highlightTo source: String, range: NSRange) -> String? {
        let ns = source as NSString
        guard range.length > 0,
              range.location >= 0,
              range.location + range.length <= ns.length else { return nil }

        let selected = ns.substring(with: range)
        let trimmed = selected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard !selected.contains(marker) else { return nil }

        return ns.replacingCharacters(in: range, with: "\(marker)\(selected)\(marker)")
    }

    public static func removeHighlight(from source: String, range: NSRange) -> String? {
        let ns = source as NSString
        guard range.location >= marker.count,
              range.location + range.length <= ns.length else { return nil }

        let outerStart = range.location - marker.count
        let beforeRange = NSRange(location: outerStart, length: marker.count)
        guard ns.substring(with: beforeRange) == marker else { return nil }

        let afterStart = range.location + range.length
        guard afterStart + marker.count <= ns.length else { return nil }
        let afterRange = NSRange(location: afterStart, length: marker.count)
        guard ns.substring(with: afterRange) == marker else { return nil }

        let inner = ns.substring(with: range)
        let total = NSRange(location: outerStart, length: marker.count * 2 + range.length)
        return ns.replacingCharacters(in: total, with: inner)
    }

    public static func highlights(in source: String) -> [Highlight] {
        let ns = source as NSString
        var found: [Highlight] = []
        var searchStart = 0

        while searchStart < ns.length {
            let openRange = ns.range(
                of: "==",
                options: [],
                range: NSRange(location: searchStart, length: ns.length - searchStart)
            )
            guard openRange.location != NSNotFound else { break }
            let innerStart = openRange.location + 2
            guard innerStart <= ns.length else { break }

            let closeRange = ns.range(
                of: "==",
                options: [],
                range: NSRange(location: innerStart, length: ns.length - innerStart)
            )
            guard closeRange.location != NSNotFound else { break }

            let length = closeRange.location - innerStart
            if length > 0 {
                found.append(Highlight(
                    id: "\(innerStart)-\(length)",
                    range: NSRange(location: innerStart, length: length)
                ))
            }
            searchStart = closeRange.location + 2
        }

        return found
    }
}
