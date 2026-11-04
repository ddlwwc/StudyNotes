import StudyNotesKit
import SwiftUI

struct MarkdownRenderer: View {
    let markdown: String
    var blockSpacing: CGFloat = 18
    var preferences = ReadingPreferences()

    private var blocks: [MarkdownBlock] {
        MarkdownBlock.parse(markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: blockSpacing) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case let .heading(level, text):
            inlineText(text)
                .font(.sn(headingSize(level), weight: level <= 2 ? .semibold : .medium))
                .foregroundStyle(SNColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, level <= 2 ? 8 : 2)
        case let .paragraph(text):
            inlineText(text)
                .font(.snReading(preferences.fontSize))
                .lineSpacing(readingLineSpacing)
                .foregroundStyle(SNColor.text)
                .fixedSize(horizontal: false, vertical: true)
        case let .quote(text):
            inlineText(text)
                .font(.snReading(max(12, preferences.fontSize - 1)))
                .lineSpacing(readingLineSpacing)
                .foregroundStyle(SNColor.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 15)
                .padding(.vertical, 4)
                .overlay(alignment: .leading) {
                Rectangle()
                    .fill(SNColor.blue)
                    .frame(width: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                        .padding(.vertical, 2)
                }
        case let .bullet(text):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Circle()
                    .fill(SNColor.blue)
                    .frame(width: 5, height: 5)
                inlineText(text)
                    .font(.sn(max(12, preferences.fontSize - 2)))
                    .lineSpacing(readingLineSpacing)
                    .foregroundStyle(SNColor.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case let .numbered(number, text):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(number).")
                    .font(.sn(max(12, preferences.fontSize - 2), weight: .medium))
                    .foregroundStyle(SNColor.blue)
                    .frame(width: 20, alignment: .trailing)
                inlineText(text)
                    .font(.sn(max(12, preferences.fontSize - 2)))
                    .lineSpacing(readingLineSpacing)
                    .foregroundStyle(SNColor.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case let .code(text):
            ScrollView(.horizontal) {
                Text(text)
                    .font(
                        .custom(
                            preferences.codeFont,
                            size: max(11, preferences.fontSize - 4)
                        )
                    )
                    .foregroundStyle(SNColor.ink)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .background(SNColor.nav)
            .clipShape(RoundedRectangle(cornerRadius: SNRadius.control))
            .overlay {
                RoundedRectangle(cornerRadius: SNRadius.control)
                    .stroke(SNColor.border, lineWidth: 1)
            }
        case let .table(headers, rows, alignments):
            VStack(spacing: 0) {
                tableRow(headers, alignments: alignments, isHeader: true)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    tableRow(row, alignments: alignments, isHeader: false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: SNRadius.control))
            .overlay {
                RoundedRectangle(cornerRadius: SNRadius.control)
                    .stroke(SNColor.border, lineWidth: 1)
            }
        case .divider:
            Rectangle()
                .fill(SNColor.border)
                .frame(height: 1)
                .padding(.vertical, 2)
        }
    }

    private func inlineText(_ source: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: source,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            return Text(attributed)
        }
        return Text(source)
    }

    private func headingSize(_ level: Int) -> CGFloat {
        let base = preferences.fontSize
        switch level {
        case 1:
            return base + 10
        case 2:
            return base + 5
        case 3:
            return base + 2
        default:
            return base
        }
    }

    private var readingLineSpacing: CGFloat {
        max(
            3,
            preferences.fontSize * (preferences.lineHeight - 1)
        )
    }

    private func tableRow(
        _ cells: [String],
        alignments: [MarkdownTableAlignment],
        isHeader: Bool
    ) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                inlineText(cell)
                    .font(
                        .sn(
                            max(11, preferences.fontSize - 3),
                            weight: isHeader ? .medium : .regular
                        )
                    )
                    .foregroundStyle(isHeader ? SNColor.ink : SNColor.text)
                    .frame(
                        maxWidth: .infinity,
                        alignment: alignments.indices.contains(index)
                            ? alignments[index].frameAlignment
                            : .leading
                    )
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .overlay(alignment: .trailing) {
                        if index < cells.count - 1 {
                            Rectangle()
                                .fill(SNColor.border)
                                .frame(width: 1)
                        }
                    }
            }
        }
        .background(isHeader ? SNColor.nav : Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SNColor.border)
                .frame(height: 1)
        }
    }
}

private enum MarkdownTableAlignment {
    case leading
    case center
    case trailing

    var frameAlignment: Alignment {
        switch self {
        case .leading:
            .leading
        case .center:
            .center
        case .trailing:
            .trailing
        }
    }
}

private enum MarkdownBlock {
    case heading(level: Int, text: String)
    case paragraph(String)
    case quote(String)
    case bullet(String)
    case numbered(number: Int, text: String)
    case code(String)
    case table(
        headers: [String],
        rows: [[String]],
        alignments: [MarkdownTableAlignment]
    )
    case divider

    static func parse(_ markdown: String) -> [MarkdownBlock] {
        let lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        var blocks: [MarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") {
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
                blocks.append(.code(codeLines.joined(separator: "\n")))
                continue
            }

            if index + 1 < lines.count,
               let headers = tableCells(from: trimmed),
               let alignments = tableAlignments(from: lines[index + 1]),
               headers.count == alignments.count {
                index += 2
                var rows: [[String]] = []
                while index < lines.count,
                      let cells = tableCells(from: lines[index]),
                      !cells.isEmpty {
                    rows.append(normalized(cells, count: headers.count))
                    index += 1
                }
                blocks.append(
                    .table(
                        headers: headers,
                        rows: rows,
                        alignments: alignments
                    )
                )
                continue
            }

            if trimmed == "---" || trimmed == "***" {
                blocks.append(.divider)
                index += 1
                continue
            }

            if let heading = heading(from: trimmed) {
                blocks.append(heading)
                index += 1
                continue
            }

            if trimmed.hasPrefix("> ") {
                var quoteLines: [String] = []
                while index < lines.count {
                    let current = lines[index].trimmingCharacters(in: .whitespaces)
                    guard current.hasPrefix("> ") else {
                        break
                    }
                    quoteLines.append(String(current.dropFirst(2)))
                    index += 1
                }
                blocks.append(.quote(quoteLines.joined(separator: " ")))
                continue
            }

            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                blocks.append(.bullet(String(trimmed.dropFirst(2))))
                index += 1
                continue
            }

            if let ordered = orderedItem(from: trimmed) {
                blocks.append(ordered)
                index += 1
                continue
            }

            var paragraphLines = [trimmed]
            index += 1
            while index < lines.count {
                let next = lines[index].trimmingCharacters(in: .whitespaces)
                if next.isEmpty
                    || startsBlock(next)
                    || isTableStart(lines: lines, index: index) {
                    break
                }
                paragraphLines.append(next)
                index += 1
            }
            blocks.append(.paragraph(paragraphLines.joined(separator: " ")))
        }

        return blocks
    }

    private static func heading(from line: String) -> MarkdownBlock? {
        let hashes = line.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count),
              line.dropFirst(hashes.count).first == " " else {
            return nil
        }
        let text = line.dropFirst(hashes.count + 1)
        return .heading(level: hashes.count, text: String(text))
    }

    private static func orderedItem(from line: String) -> MarkdownBlock? {
        guard let dot = line.firstIndex(of: "."),
              let number = Int(line[..<dot]),
              line.index(after: dot) < line.endIndex,
              line[line.index(after: dot)] == " " else {
            return nil
        }
        let textStart = line.index(dot, offsetBy: 2)
        return .numbered(number: number, text: String(line[textStart...]))
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

    private static func isTableStart(lines: [String], index: Int) -> Bool {
        guard index + 1 < lines.count,
              let headers = tableCells(
                  from: lines[index].trimmingCharacters(in: .whitespaces)
              ),
              let alignments = tableAlignments(from: lines[index + 1]) else {
            return false
        }
        return headers.count == alignments.count
    }

    private static func tableCells(from line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else {
            return nil
        }
        var cells = trimmed
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if cells.first == "" {
            cells.removeFirst()
        }
        if cells.last == "" {
            cells.removeLast()
        }
        return cells.isEmpty ? nil : cells
    }

    private static func tableAlignments(
        from line: String
    ) -> [MarkdownTableAlignment]? {
        guard let cells = tableCells(from: line) else {
            return nil
        }
        var result: [MarkdownTableAlignment] = []
        for cell in cells {
            let left = cell.hasPrefix(":")
            let right = cell.hasSuffix(":")
            let dashes = cell.trimmingCharacters(
                in: CharacterSet(charactersIn: ":")
            )
            guard dashes.count >= 3,
                  dashes.allSatisfy({ $0 == "-" }) else {
                return nil
            }
            result.append(
                left && right ? .center : right ? .trailing : .leading
            )
        }
        return result
    }

    private static func normalized(_ cells: [String], count: Int) -> [String] {
        cells.count >= count
            ? Array(cells.prefix(count))
            : cells + Array(repeating: "", count: count - cells.count)
    }
}
