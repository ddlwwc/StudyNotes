import Foundation

enum WorkspaceFormatting {
    static func updatedDate(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "今天 \(date.formatted(date: .omitted, time: .shortened))"
        }
        if Calendar.current.isDateInYesterday(date) {
            return "昨天"
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    static func fullDate(_ date: Date) -> String {
        date.formatted(.dateTime.year().month(.wide).day())
    }

    static func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
