import Foundation

extension Date {
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    func relativeFormatted(locale: Locale = .current) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(self)
        let calendar = Calendar.current

        // Very recent — show "Just now" / "刚刚"
        if interval < 60 {
            let isChinese = locale.language.languageCode?.identifier == "zh"
            return isChinese ? "刚刚" : "Just now"
        }

        // Yesterday — explicit check before using system formatter
        if calendar.isDateInYesterday(self) {
            let isChinese = locale.language.languageCode?.identifier == "zh"
            return isChinese ? "昨天" : "Yesterday"
        }

        // Within the last 7 days — use RelativeDateTimeFormatter
        if interval < 7 * 24 * 3600 {
            let formatter = Self.relativeFormatter
            formatter.locale = locale
            return formatter.localizedString(for: self, relativeTo: now)
        }

        // Older — show absolute date
        let formatter = DateFormatter()
        let isChinese = locale.language.languageCode?.identifier == "zh"
        if calendar.component(.year, from: self) == calendar.component(.year, from: now) {
            formatter.dateFormat = isChinese ? "M月d日" : "MMM d"
        } else {
            formatter.dateFormat = isChinese ? "yyyy年M月d日" : "MMM d, yyyy"
        }
        formatter.locale = locale
        return formatter.string(from: self)
    }
}
