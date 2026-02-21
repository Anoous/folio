import Foundation
import Network
import SwiftData
import BackgroundTasks
import Combine

@MainActor
@Observable
final class OfflineQueueManager {
    static let backgroundTaskIdentifier = "com.folio.article-processing"

    var pendingCount: Int = 0
    var isNetworkAvailable: Bool = true

    private let context: ModelContext
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.folio.network-monitor")

    /// Callback invoked when network becomes available and there are pending articles.
    /// In M7, this will call the backend API.
    var onProcessPending: (([Article]) async -> [UUID: Bool])?

    init(context: ModelContext) {
        self.context = context
        startMonitoring()
        refreshPendingCount()
    }

    deinit {
        monitor.cancel()
    }

    func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let wasAvailable = self.isNetworkAvailable
                self.isNetworkAvailable = path.status == .satisfied
                if !wasAvailable && self.isNetworkAvailable {
                    await self.processPendingArticles()
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    func refreshPendingCount() {
        let pendingRaw = ArticleStatus.pending.rawValue
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate { $0.statusRaw == pendingRaw }
        )
        pendingCount = (try? context.fetchCount(descriptor)) ?? 0
    }

    func processPendingArticles() async {
        let pendingRaw = ArticleStatus.pending.rawValue
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate { $0.statusRaw == pendingRaw },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        guard let pending = try? context.fetch(descriptor), !pending.isEmpty else { return }

        if let processor = onProcessPending {
            // M7: Call backend API
            let results = await processor(pending)
            for article in pending {
                if let success = results[article.id] {
                    article.status = success ? .processing : .failed
                } else {
                    article.status = .failed
                }
            }
        } else {
            // Pre-M7: Mark as processing (placeholder)
            for article in pending {
                article.status = .processing
            }
        }

        article_save: do {
            try context.save()
        } catch {
            // Save error, will retry on next network event
        }

        refreshPendingCount()
    }

    // MARK: - Background Tasks

    static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundTaskIdentifier,
            using: nil
        ) { task in
            guard let bgTask = task as? BGProcessingTask else { return }
            bgTask.setTaskCompleted(success: true)
        }
    }

    static func scheduleBackgroundProcessing() {
        let request = BGProcessingTaskRequest(identifier: backgroundTaskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        try? BGTaskScheduler.shared.submit(request)
    }
}
