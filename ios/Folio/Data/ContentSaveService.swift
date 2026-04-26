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
    private let searchIndexCoordinator: SearchIndexCoordinator
    private let imageStorageURLProvider: () -> URL?
    private let imageOCRExtractor: (UIImage) async throws -> String?

    init(
        context: ModelContext,
        syncService: SyncService?,
        searchIndexCoordinator: SearchIndexCoordinator? = nil,
        imageStorageURLProvider: @escaping () -> URL? = {
            FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: AppConstants.appGroupIdentifier
            )
        },
        imageOCRExtractor: @escaping (UIImage) async throws -> String? = { image in
            try await ImageOCRExtractor().extract(from: image)
        }
    ) {
        self.context = context
        self.syncService = syncService
        self.searchIndexCoordinator = searchIndexCoordinator ?? .shared
        self.imageStorageURLProvider = imageStorageURLProvider
        self.imageOCRExtractor = imageOCRExtractor
    }

    // MARK: - Public API

    func saveURL(_ urlString: String) -> SaveResult {
        guard checkQuota() else { return .quotaExceeded }

        let manager = SharedDataManager(
            context: context,
            onArticleIndexed: { [searchIndexCoordinator] article in
                searchIndexCoordinator.sync(article)
            },
            onArticleUpdated: { [searchIndexCoordinator] article in
                searchIndexCoordinator.sync(article)
            }
        )
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

        let manager = SharedDataManager(
            context: context,
            onArticleIndexed: { [searchIndexCoordinator] article in
                searchIndexCoordinator.sync(article)
            },
            onArticleUpdated: { [searchIndexCoordinator] article in
                searchIndexCoordinator.sync(article)
            }
        )
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
        guard let containerURL = imageStorageURLProvider() else {
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
        article.title = String(localized: "home.screenshotTitle", defaultValue: "Screenshot")
        article.status = .clientReady
        context.insert(article)
        do {
            try context.save()
        } catch {
            return .error(
                message: String(localized: "home.screenshotError", defaultValue: "Failed to process image")
            )
        }
        searchIndexCoordinator.sync(article)
        SharedDataManager.incrementQuota()

        // Run OCR in background — sync AFTER OCR completes to avoid uploading empty content
        let ocrImage = Self.resizedImage(image, maxDimension: 1280)
        let articleID = article.id
        let ctx = context
        let sync = syncService
        let searchIndexCoordinator = self.searchIndexCoordinator
        let imageOCRExtractor = self.imageOCRExtractor
        Task {
            do {
                let text = try await imageOCRExtractor(ocrImage)
                await MainActor.run {
                    if let text, !text.isEmpty {
                        let descriptor = FetchDescriptor<Article>(predicate: #Predicate { $0.id == articleID })
                        guard let article = try? ctx.fetch(descriptor).first else { return }
                        article.markdownContent = text
                        article.title = String(text.prefix(40)).components(separatedBy: .newlines).first ?? String(text.prefix(40))
                        article.wordCount = Article.countWords(text)
                        article.updatedAt = .now
                        try? ctx.save()
                        searchIndexCoordinator.sync(article)
                    }
                    onOCRComplete()
                }
            } catch {
                FolioLogger.data.error("OCR extraction failed for screenshot \(articleID): \(error.localizedDescription)")
                await MainActor.run { onOCRComplete() }
            }
            await sync?.incrementalSync()
        }

        return .success(
            message: String(localized: "home.screenshotSaved", defaultValue: "Screenshot saved"),
            icon: "checkmark.circle.fill"
        )
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
