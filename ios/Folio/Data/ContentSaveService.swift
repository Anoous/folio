import SwiftData
import UIKit

@MainActor
final class ContentSaveService {

    enum SaveResult {
        case success(message: String, icon: String)
        case duplicate
        case quotaExceeded
        case error(message: String)
    }

    private let context: ModelContext
    private let syncService: SyncService?

    init(context: ModelContext, syncService: SyncService?) {
        self.context = context
        self.syncService = syncService
    }

    // MARK: - Public API

    func saveURL(_ urlString: String) -> SaveResult {
        guard checkQuota() else { return .quotaExceeded }

        let manager = SharedDataManager(context: context)
        do {
            _ = try manager.saveArticleFromText(urlString)
            SharedDataManager.incrementQuota()
            triggerSync()
            return .success(
                message: String(localized: "home.addURL.saved", defaultValue: "Link saved"),
                icon: "checkmark.circle.fill"
            )
        } catch SharedDataError.duplicateURL {
            return .duplicate
        } catch {
            return .error(
                message: String(localized: "home.addURL.error", defaultValue: "Failed to save")
            )
        }
    }

    func saveManualContent(_ content: String) -> SaveResult {
        guard checkQuota() else { return .quotaExceeded }

        let manager = SharedDataManager(context: context)
        do {
            _ = try manager.saveManualContent(content: content)
            SharedDataManager.incrementQuota()
            triggerSync()
            return .success(
                message: String(localized: "home.manualSaved", defaultValue: "Saved"),
                icon: "checkmark.circle.fill"
            )
        } catch {
            return .error(
                message: String(localized: "home.manualSaveError", defaultValue: "Failed to save")
            )
        }
    }

    func saveScreenshot(_ image: UIImage, onOCRComplete: @escaping () -> Void) -> SaveResult {
        guard checkQuota() else { return .quotaExceeded }

        // Compress for storage (max 1920px)
        let storageImage = Self.resizedImage(image, maxDimension: 1920)
        guard let storageData = storageImage.jpegData(compressionQuality: 0.8) else {
            return .error(
                message: String(localized: "home.screenshotError", defaultValue: "Failed to process image")
            )
        }

        // Save image to App Group container Images/ directory
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroupIdentifier) else {
            return .error(
                message: String(localized: "home.screenshotError", defaultValue: "Failed to process image")
            )
        }
        let imagesDir = containerURL.appendingPathComponent("Images", isDirectory: true)
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        let filename = UUID().uuidString + ".jpg"
        let fileURL = imagesDir.appendingPathComponent(filename)
        do {
            try storageData.write(to: fileURL)
        } catch {
            return .error(
                message: String(localized: "home.screenshotError", defaultValue: "Failed to process image")
            )
        }

        let relativePath = "Images/\(filename)"

        // Create article immediately, then run OCR in background
        let article = Article(url: nil, sourceType: .screenshot)
        article.localImagePath = relativePath
        article.status = .clientReady
        context.insert(article)
        do {
            try context.save()
        } catch {
            return .error(
                message: String(localized: "home.screenshotError", defaultValue: "Failed to process image")
            )
        }
        SharedDataManager.incrementQuota()

        // Run OCR in background
        let ocrImage = Self.resizedImage(image, maxDimension: 1280)
        let articleID = article.id
        let ctx = context
        let sync = syncService
        Task {
            let extractor = ImageOCRExtractor()
            if let text = try? await extractor.extract(from: ocrImage), !text.isEmpty {
                await MainActor.run {
                    // Re-fetch the article from context by ID
                    let descriptor = FetchDescriptor<Article>(predicate: #Predicate { $0.id == articleID })
                    guard let article = try? ctx.fetch(descriptor).first else { return }
                    article.markdownContent = text
                    article.title = String(text.prefix(40)).components(separatedBy: .newlines).first ?? String(text.prefix(40))
                    article.wordCount = Article.countWords(text)
                    article.updatedAt = .now
                    try? ctx.save()
                    onOCRComplete()
                }
            }
            await sync?.incrementalSync()
        }

        return .success(
            message: String(localized: "home.screenshotSaved", defaultValue: "Screenshot saved"),
            icon: "checkmark.circle.fill"
        )
    }

    func saveVoiceNote(_ transcribedText: String) -> SaveResult {
        let trimmed = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .error(message: "") }

        guard checkQuota() else { return .quotaExceeded }

        let article = Article(url: nil, sourceType: .voice)
        article.markdownContent = trimmed
        // Title = first sentence, truncated to 40 chars
        let firstSentence = trimmed.components(separatedBy: CharacterSet(charactersIn: ".!?\u{3002}\u{FF01}\u{FF1F}")).first ?? trimmed
        let titleCandidate = String(firstSentence.prefix(40))
        article.title = titleCandidate.count < firstSentence.count ? titleCandidate + "..." : titleCandidate
        article.status = .clientReady
        article.wordCount = Article.countWords(trimmed)
        context.insert(article)
        do {
            try context.save()
            SharedDataManager.incrementQuota()
            triggerSync()
            return .success(
                message: String(localized: "home.voiceSaved", defaultValue: "Voice note saved"),
                icon: "checkmark.circle.fill"
            )
        } catch {
            return .error(
                message: String(localized: "home.voiceSaveError", defaultValue: "Failed to save")
            )
        }
    }

    // MARK: - Private Helpers

    private func checkQuota() -> Bool {
        let isPro = UserDefaults.appGroup.bool(forKey: SharedDataManager.isProUserKey)
        return SharedDataManager.canSave(isPro: isPro)
    }

    private func triggerSync() {
        let sync = syncService
        Task {
            await sync?.incrementalSync()
        }
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
}
