import Foundation
import SwiftData

enum SharedDataError: Error {
    case duplicateURL
    case quotaExceeded
    case containerUnavailable
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
            throw SharedDataError.duplicateURL
        }

        let sourceType = SourceType.detect(from: url)
        let article = Article(url: url, sourceType: sourceType)
        context.insert(article)
        try context.save()
        return article
    }

    /// Save article from plain text (extract URL)
    @MainActor
    func saveArticleFromText(_ text: String) throws -> Article {
        guard let url = extractURL(from: text) else {
            let article = Article(url: text, sourceType: .web)
            context.insert(article)
            try context.save()
            return article
        }
        return try saveArticle(url: url)
    }

    /// Check if URL already exists
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

        if let title = result.title, !title.isEmpty {
            article.title = title
        }
        if let author = result.author, !author.isEmpty {
            article.author = author
        }
        if let siteName = result.siteName, !siteName.isEmpty {
            article.siteName = siteName
        }
        if let excerpt = result.excerpt, !excerpt.isEmpty {
            article.summary = excerpt
        }

        article.updatedAt = Date()
        try context.save()
    }

    // MARK: - Quota

    static let freeMonthlyQuota = 30

    static func quotaKey(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return "quota_\(formatter.string(from: date))"
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
        return currentMonthCount(userDefaults: userDefaults) < freeMonthlyQuota
    }
}

extension UserDefaults {
    static var appGroup: UserDefaults {
        UserDefaults(suiteName: "group.com.folio.app") ?? .standard
    }
}
