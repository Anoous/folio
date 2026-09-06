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
        let result = makeWorkflow().saveURL(urlString)
        switch result {
        case .saved:
            return .success(
                message: String(localized: "home.addURL.saved", defaultValue: "Link saved"),
                icon: "checkmark.circle.fill"
            )
        case .duplicate:
            return .duplicate
        case .quotaExceeded:
            return .quotaExceeded
        case .error:
            return .error(
                message: String(localized: "home.addURL.error", defaultValue: "Failed to save")
            )
        }
    }

    func saveManualContent(_ content: String) -> SaveResult {
        let result = makeWorkflow().saveManualContent(content)
        switch result {
        case .saved:
            return .success(
                message: String(localized: "home.manualSaved", defaultValue: "Saved"),
                icon: "checkmark.circle.fill"
            )
        case .duplicate:
            return .duplicate
        case .quotaExceeded:
            return .quotaExceeded
        case .error:
            return .error(
                message: String(localized: "home.manualSaveError", defaultValue: "Failed to save")
            )
        }
    }

    func saveScreenshot(_ image: UIImage, onOCRComplete: @escaping () -> Void) -> SaveResult {
        let result = makeWorkflow().saveScreenshotWithBackgroundOCR(
            image,
            onOCRComplete: onOCRComplete
        )
        switch result {
        case .saved:
            break
        case .quotaExceeded:
            return .quotaExceeded
        case .duplicate:
            return .duplicate
        case .error:
            return .error(
                message: String(localized: "home.screenshotError", defaultValue: "Failed to process image")
            )
        }
        return .success(
            message: String(localized: "home.screenshotSaved", defaultValue: "Screenshot saved"),
            icon: "checkmark.circle.fill"
        )
    }

    // MARK: - Private Helpers

    private func makeWorkflow() -> ContentIntakeWorkflow {
        ContentIntakeWorkflow(
            context: context,
            imageStorageURLProvider: imageStorageURLProvider,
            imageOCRExtractor: imageOCRExtractor,
            onArticleIndexed: { [searchIndexCoordinator] article in
                searchIndexCoordinator.sync(article)
            },
            onArticleUpdated: { [searchIndexCoordinator] article in
                searchIndexCoordinator.sync(article)
            },
            onSyncRequested: { [weak self] in
                self?.triggerSync()
            }
        )
    }

    private func triggerSync() {
        let sync = syncService
        Task {
            await sync?.incrementalSync()
        }
    }
}
