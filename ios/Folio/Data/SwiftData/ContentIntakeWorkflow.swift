import Foundation
import SwiftData
import UIKit

struct ContentIntakeReceipt {
    let article: Article
    let displayName: String
}

enum ContentIntakeResult {
    case saved(ContentIntakeReceipt)
    case duplicate(ContentIntakeReceipt)
    case quotaExceeded
    case error(SharedDataError)
}

@MainActor
final class ContentIntakeWorkflow {
    private let context: ModelContext
    private let userDefaults: UserDefaults
    private let imageStorageURLProvider: () -> URL?
    private let imageOCRExtractor: (UIImage) async throws -> String?
    private let onArticleIndexed: (Article) -> Void
    private let onArticleUpdated: (Article) -> Void
    private let onSaveCompleted: () -> Void
    private let onSyncRequested: () -> Void

    init(
        context: ModelContext,
        userDefaults: UserDefaults = .appGroup,
        imageStorageURLProvider: @escaping () -> URL? = {
            FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: AppConstants.appGroupIdentifier
            )
        },
        imageOCRExtractor: @escaping (UIImage) async throws -> String? = { image in
            try await ImageOCRExtractor().extract(from: image)
        },
        onArticleIndexed: @escaping (Article) -> Void = { _ in },
        onArticleUpdated: @escaping (Article) -> Void = { _ in },
        onSaveCompleted: @escaping () -> Void = {},
        onSyncRequested: @escaping () -> Void = {}
    ) {
        self.context = context
        self.userDefaults = userDefaults
        self.imageStorageURLProvider = imageStorageURLProvider
        self.imageOCRExtractor = imageOCRExtractor
        self.onArticleIndexed = onArticleIndexed
        self.onArticleUpdated = onArticleUpdated
        self.onSaveCompleted = onSaveCompleted
        self.onSyncRequested = onSyncRequested
    }

    func saveURL(_ text: String) -> ContentIntakeResult {
        guard canSave() else { return .quotaExceeded }

        do {
            let article = try SharedDataManager(context: context).saveArticleFromText(text)
            return completeSave(article, displayName: Self.displayName(for: article.url ?? text), requestSync: true)
        } catch SharedDataError.duplicateURL {
            guard let article = existingArticle(for: text) else {
                return .error(.duplicateURL)
            }
            return .duplicate(ContentIntakeReceipt(
                article: article,
                displayName: Self.displayName(for: article.url ?? text)
            ))
        } catch let error as SharedDataError {
            return .error(error)
        } catch {
            return .error(.invalidInput)
        }
    }

    func saveManualContent(_ content: String) -> ContentIntakeResult {
        guard canSave() else { return .quotaExceeded }

        do {
            let article = try SharedDataManager(context: context).saveManualContent(content: content)
            return completeSave(
                article,
                displayName: String(localized: "source.thought", defaultValue: "My Thought"),
                requestSync: true
            )
        } catch let error as SharedDataError {
            return .error(error)
        } catch {
            return .error(.invalidInput)
        }
    }

    func saveScreenshotWithBackgroundOCR(
        _ image: UIImage,
        onOCRComplete: @escaping () -> Void
    ) -> ContentIntakeResult {
        guard canSave() else { return .quotaExceeded }

        let imagePath: String
        do {
            imagePath = try storeImage(image)
        } catch let error as SharedDataError {
            return .error(error)
        } catch {
            return .error(.invalidInput)
        }

        let article = Article(url: nil, sourceType: .screenshot)
        article.localImagePath = imagePath
        article.title = String(localized: "home.screenshotTitle", defaultValue: "Screenshot")
        article.status = .clientReady
        context.insert(article)

        do {
            try context.save()
        } catch {
            return .error(.invalidInput)
        }

        onArticleIndexed(article)
        finishQuotaAndCompletion()

        let ocrImage = Self.resizedImage(image, maxDimension: 1280)
        let articleID = article.id
        let context = self.context
        let imageOCRExtractor = self.imageOCRExtractor
        let onArticleUpdated = self.onArticleUpdated
        let onSyncRequested = self.onSyncRequested

        Task {
            do {
                let text = try await imageOCRExtractor(ocrImage)
                await MainActor.run {
                    if let text, !text.isEmpty {
                        let descriptor = FetchDescriptor<Article>(
                            predicate: #Predicate { $0.id == articleID }
                        )
                        if let article = try? context.fetch(descriptor).first {
                            Self.applyOCRText(text, to: article)
                            ModelContext.safeSave(context)
                            onArticleUpdated(article)
                        }
                    }
                    onOCRComplete()
                }
            } catch {
                FolioLogger.data.error("OCR extraction failed for screenshot \(articleID): \(error.localizedDescription)")
                await MainActor.run { onOCRComplete() }
            }
            await MainActor.run {
                onSyncRequested()
            }
        }

        return .saved(ContentIntakeReceipt(
            article: article,
            displayName: String(localized: "share.screenshot", defaultValue: "截图")
        ))
    }

    func saveScreenshotAfterOCR(_ image: UIImage) async -> ContentIntakeResult {
        guard canSave() else { return .quotaExceeded }

        let imagePath: String
        do {
            imagePath = try storeImage(image)
        } catch let error as SharedDataError {
            return .error(error)
        } catch {
            return .error(.invalidInput)
        }

        let ocrImage = Self.resizedImage(image, maxDimension: 1280)
        let ocrText = try? await imageOCRExtractor(ocrImage)
        let article = Article(
            url: nil,
            title: Self.screenshotTitle(from: ocrText),
            sourceType: .screenshot
        )
        article.localImagePath = imagePath
        if let ocrText, !ocrText.isEmpty {
            article.markdownContent = ocrText
            article.wordCount = Article.countWords(ocrText)
        }
        article.status = .clientReady
        article.extractionSource = .client
        article.clientExtractedAt = .now

        context.insert(article)
        do {
            try context.save()
        } catch {
            return .error(.invalidInput)
        }

        return completeSave(
            article,
            displayName: String(localized: "share.screenshot", defaultValue: "截图"),
            requestSync: false
        )
    }

    private func canSave() -> Bool {
        let isPro = userDefaults.bool(forKey: SharedDataManager.isProUserKey)
        return SharedDataManager.canSave(isPro: isPro, userDefaults: userDefaults)
    }

    private func completeSave(
        _ article: Article,
        displayName: String,
        requestSync: Bool
    ) -> ContentIntakeResult {
        onArticleIndexed(article)
        finishQuotaAndCompletion()
        if requestSync {
            onSyncRequested()
        }
        return .saved(ContentIntakeReceipt(article: article, displayName: displayName))
    }

    private func finishQuotaAndCompletion() {
        SharedDataManager.incrementQuota(userDefaults: userDefaults)
        onSaveCompleted()
    }

    private func existingArticle(for text: String) -> Article? {
        guard let url = Self.resolvedURL(from: text) else { return nil }
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate { $0.url == url }
        )
        return try? context.fetch(descriptor).first
    }

    private func storeImage(_ image: UIImage) throws -> String {
        let storageImage = Self.resizedImage(image, maxDimension: 1920)
        guard let storageData = storageImage.jpegData(compressionQuality: 0.8) else {
            throw SharedDataError.invalidInput
        }

        guard let containerURL = imageStorageURLProvider() else {
            throw SharedDataError.containerUnavailable
        }

        let imagesDir = containerURL.appendingPathComponent("Images", isDirectory: true)
        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        let filename = UUID().uuidString + ".jpg"
        let fileURL = imagesDir.appendingPathComponent(filename)
        try storageData.write(to: fileURL)
        return "Images/\(filename)"
    }

    static func resizedImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        guard max(size.width, size.height) > maxDimension else { return image }
        let scale = maxDimension / max(size.width, size.height)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private static func applyOCRText(_ text: String, to article: Article) {
        article.markdownContent = text
        article.title = screenshotTitle(from: text)
        article.wordCount = Article.countWords(text)
        article.extractionSource = .client
        article.clientExtractedAt = .now
        article.updatedAt = .now
    }

    private static func screenshotTitle(from text: String?) -> String {
        if let firstLine = text?
            .components(separatedBy: .newlines)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            return String(firstLine.prefix(40))
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return "截图 · \(formatter.string(from: .now))"
    }

    private static func displayName(for text: String) -> String {
        URL(string: text)
            .flatMap { $0.host()?.replacingOccurrences(of: "www.", with: "") }
            ?? text
    }

    private static func resolvedURL(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        if let match = detector?.firstMatch(in: trimmed, options: [], range: range),
           let url = match.url,
           url.scheme?.hasPrefix("http") == true {
            return url.absoluteString
        }

        if let parsed = URL(string: trimmed),
           let scheme = parsed.scheme?.lowercased(),
           scheme == "http" || scheme == "https",
           parsed.host() != nil {
            return parsed.absoluteString
        }

        return nil
    }
}
