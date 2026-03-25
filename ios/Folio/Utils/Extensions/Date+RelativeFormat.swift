import Foundation

extension Date {
    // Cached formatters for relative date display (app supports en + zh-Hans only)
    private static let zhShortDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日"
        return f
    }()

    private static let zhFullDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日"
        return f
    }()

    private static let enShortDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM d"
        return f
    }()

    private static let enFullDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

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
        let isChinese = locale.language.languageCode?.identifier == "zh"
        let sameYear = calendar.component(.year, from: self) == calendar.component(.year, from: now)
        let formatter: DateFormatter
        switch (isChinese, sameYear) {
        case (true, true):   formatter = Self.zhShortDate
        case (true, false):  formatter = Self.zhFullDate
        case (false, true):  formatter = Self.enShortDate
        case (false, false): formatter = Self.enFullDate
        }
        return formatter.string(from: self)
    }
}
