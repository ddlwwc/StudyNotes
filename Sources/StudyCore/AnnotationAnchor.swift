import Foundation

public enum AnnotationAnchor {
    public static func make(from source: String, range: NSRange, existing: [Annotation]) -> Annotation? {
        let ns = source as NSString
        guard range.length > 0,
              range.location >= 0,
              range.location + range.length <= ns.length else { return nil }

        let picked = ns.substring(with: range)
        let anchor = picked.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !anchor.isEmpty else { return nil }

        return Annotation(anchorText: anchor)
    }

    public static func locate(
        anchorText: String,
        in source: String,
        claimed: Set<NSRange> = []
    ) -> NSRange? {
        guard !anchorText.isEmpty else { return nil }
        let ns = source as NSString
        var searchStart = 0

        while searchStart <= ns.length {
            let remaining = NSRange(location: searchStart, length: ns.length - searchStart)
            let found = ns.range(of: anchorText, options: [], range: remaining)
            guard found.location != NSNotFound else { return nil }
            if claimed.contains(found) {
                searchStart = found.location + max(found.length, 1)
                continue
            }
            return found
        }

        return nil
    }

    public static func resolve(
        _ file: AnnotationFile,
        in source: String
    ) -> [(annotation: Annotation, range: NSRange)] {
        var claimed = Set<NSRange>()
        var result: [(Annotation, NSRange)] = []
        let sorted = file.annotations.sorted { $0.createdAt < $1.createdAt }

        for annotation in sorted {
            guard let range = locate(
                anchorText: annotation.anchorText,
                in: source,
                claimed: claimed
            ) else { continue }
            claimed.insert(range)
            result.append((annotation, range))
        }

        return result
    }
}
