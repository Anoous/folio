import Foundation
import os
import SwiftData

enum SharedDataError: Error, Equatable {
    case duplicateURL
    case quotaExceeded
    case containerUnavailable
    case invalidInput
}

final class SharedDataManager {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// Save article from URL, checking for duplicates
    @MainActor
    func saveArticle(url: String) throws -> Article {
        // Check duplicate
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate { $0.url == url }
        )
        if try context.fetchCount(descriptor) > 0 {
            FolioLogger.data.debug("duplicate URL rejected: \(url)")
            throw SharedDataError.duplicateURL
        }

        let sourceType = SourceType.detect(from: url)
        let article = Article(url: url, sourceType: sourceType)
        context.insert(article)
        try context.save()
        FolioLogger.data.info("article saved: \(url)")
        return article
    }

    /// Save article from plain text (extract URL)
    @MainActor
    func saveArticleFromText(_ text: String) throws -> Article {
        // First try to extract a URL from the text
        if let url = extractURL(from: text) {
            return try saveArticle(url: url)
        }

        // If the raw text itself looks like a valid HTTP(S) URL, use it directly
        if let parsed = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
           let scheme = parsed.scheme?.lowercased(),
           scheme == "http" || scheme == "https",
           parsed.host() != nil {
            return try saveArticle(url: parsed.absoluteString)
        }

        // Not a valid URL — reject instead of storing arbitrary text as a URL
        FolioLogger.data.debug("saveArticleFromText: rejected non-URL text — \(text.prefix(80))")
        throw SharedDataError.invalidInput
    }

    /// Save manual content (no URL required)
    @MainActor
    func saveManualContent(content: String) throws -> Article {
        let article = Article(content: content)
        context.insert(article)
        try context.save()
        FolioLogger.data.info("manual content saved: \(content.prefix(40))")
        return article
    }

    /// Check if URL already exists
    @MainActor
    func existsByURL(_ url: String) throws -> Bool {
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate { $0.url == url }
        )
        return try context.fetchCount(descriptor) > 0
    }

    private func extractURL(from text: String) -> String? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        if let match = detector?.firstMatch(in: text, options: [], range: range),
           let url = match.url, url.scheme?.hasPrefix("http") == true {
            return url.absoluteString
        }
        return nil
    }

    // MARK: - Extraction

    @MainActor
    func updateWithExtraction(_ result: ExtractionResult, for article: Article) throws {
        article.markdownContent = result.markdownContent
        article.wordCount = result.wordCount
        article.status = .clientReady
        article.extractionSource = .client
        article.clientExtractedAt = result.extractedAt

        if let title = result.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            article.title = title
        }
        if let author = result.author?.trimmingCharacters(in: .whitespacesAndNewlines), !author.isEmpty {
            article.author = author
        }
        if let siteName = result.siteName?.trimmingCharacters(in: .whitespacesAndNewlines), !siteName.isEmpty {
            article.siteName = siteName
        }
        if let excerpt = result.excerpt?.trimmingCharacters(in: .whitespacesAndNewlines), !excerpt.isEmpty {
            article.summary = excerpt
        }

        article.updatedAt = .now
        try context.save()
        FolioLogger.data.info("extraction updated: wordCount=\(result.wordCount), title=\(result.title ?? "nil")")
    }

    // MARK: - Quota

    static let isProUserKey = "is_pro_user"
    static let monthlyQuotaKey = "folio.monthlyQuota"
    static let freeMonthlyQuota = 30

    private static let quotaFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f
    }()

    static func quotaKey(for date: Date = .now) -> String {
        "quota_\(quotaFormatter.string(from: date))"
    }

    static func currentMonthCount(userDefaults: UserDefaults = .appGroup) -> Int {
        userDefaults.integer(forKey: quotaKey())
    }

    static func incrementQuota(userDefaults: UserDefaults = .appGroup) {
        let key = quotaKey()
        let current = userDefaults.integer(forKey: key)
        userDefaults.set(current + 1, forKey: key)
    }

    static func canSave(isPro: Bool, userDefaults: UserDefaults = .appGroup) -> Bool {
        if isPro { return true }
        let quota = userDefaults.integer(forKey: monthlyQuotaKey)
        let effectiveQuota = quota > 0 ? quota : freeMonthlyQuota
        return currentMonthCount(userDefaults: userDefaults) < effectiveQuota
    }

    /// 将服务端配额写入 UserDefaults，供 Share Extension 读取。
    /// 只在服务端计数 > 本地计数时覆盖，避免本地乐观计数被回退。
    static func syncQuotaFromServer(
        monthlyQuota: Int,
        currentMonthCount: Int,
        isPro: Bool,
        userDefaults: UserDefaults = .appGroup
    ) {
        let key = quotaKey()
        let localCount = userDefaults.integer(forKey: key)
        if currentMonthCount > localCount {
            userDefaults.set(currentMonthCount, forKey: key)
        }
        userDefaults.set(monthlyQuota, forKey: monthlyQuotaKey)
        userDefaults.set(isPro, forKey: isProUserKey)
    }
}

extension UserDefaults {
    static var appGroup: UserDefaults {
        UserDefaults(suiteName: AppConstants.appGroupIdentifier) ?? .standard
    }
}
