import Foundation

extension Date {
    func relativeFormatted(locale: Locale = .current) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(self)
        let calendar = Calendar.current
        let isChinese = locale.language.languageCode?.identifier == "zh"

        if interval < 60 {
            return isChinese ? "刚刚" : "Just now"
        }

        let minutes = Int(interval / 60)
        if minutes < 60 {
            return isChinese ? "\(minutes)分钟前" : "\(minutes)m ago"
        }

        let hours = Int(interval / 3600)
        if hours < 24 {
            return isChinese ? "\(hours)小时前" : "\(hours)h ago"
        }

        if calendar.isDateInYesterday(self) {
            return isChinese ? "昨天" : "Yesterday"
        }

        let days = calendar.dateComponents([.day], from: self, to: now).day ?? 0
        if days < 7 {
            return isChinese ? "\(days)天前" : "\(days)d ago"
        }

        let formatter = DateFormatter()
        if calendar.component(.year, from: self) == calendar.component(.year, from: now) {
            formatter.dateFormat = isChinese ? "M月d日" : "MMM d"
        } else {
            formatter.dateFormat = isChinese ? "yyyy年M月d日" : "MMM d, yyyy"
        }
        formatter.locale = locale
        return formatter.string(from: self)
    }
}
