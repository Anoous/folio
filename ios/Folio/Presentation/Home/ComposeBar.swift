import Foundation

enum URLDetection {
    /// Returns true if the trimmed text is a single URL with no other meaningful text.
    static func isURLOnly(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        let matches = detector?.matches(in: trimmed, range: range) ?? []
        guard matches.count == 1, let match = matches.first else { return false }
        return match.range.length == range.length
    }

    /// Extracts a URL from text if the text is a single URL.
    static func extractURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isURLOnly(trimmed) else { return nil }
        return URL(string: trimmed)
    }
}
