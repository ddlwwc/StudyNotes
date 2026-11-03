import Foundation

enum WorkspaceFormatting {
    static let recycleRetentionDays = 30

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

    static func recycleRemainingDays(deletedAt: Date, now: Date = Date()) -> Int {
        let retentionInterval = TimeInterval(recycleRetentionDays * 24 * 60 * 60)
        let remaining = retentionInterval - now.timeIntervalSince(deletedAt)
        return max(0, Int(ceil(remaining / (24 * 60 * 60))))
    }

    static func recycleExpiryLabel(deletedAt: Date, now: Date = Date()) -> String {
        let retentionInterval = TimeInterval(recycleRetentionDays * 24 * 60 * 60)
        guard now.timeIntervalSince(deletedAt) <= retentionInterval else {
            return "已超过 30 天"
        }
        let remainingDays = recycleRemainingDays(deletedAt: deletedAt, now: now)
        return remainingDays == 0 ? "今天到期" : "剩余 \(remainingDays) 天"
    }

    static func folderPathDisplay(_ path: String) -> String {
        path.split(separator: "/").joined(separator: " / ")
    }
}
