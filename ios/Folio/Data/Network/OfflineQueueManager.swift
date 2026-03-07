import Foundation
import Network
import os
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
    var onProcessPending: (([Article]) async -> [UUID: Bool])?

    /// Callback invoked when network becomes available to sync pending deletions and updates.
    var onSyncDeletionsAndUpdates: (() async -> Void)?

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
                if wasAvailable != self.isNetworkAvailable {
                    FolioLogger.network.info("network status changed: \(self.isNetworkAvailable ? "available" : "unavailable")")
                }
                if !wasAvailable && self.isNetworkAvailable {
                    await self.onSyncDeletionsAndUpdates?()
                    await self.processPendingArticles()
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    func refreshPendingCount() {
        let pendingRaw = ArticleStatus.pending.rawValue
        let clientReadyRaw = ArticleStatus.clientReady.rawValue
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate { $0.statusRaw == pendingRaw || $0.statusRaw == clientReadyRaw }
        )
        pendingCount = (try? context.fetchCount(descriptor)) ?? 0
    }

    func processPendingArticles() async {
        let pendingRaw = ArticleStatus.pending.rawValue
        let clientReadyRaw = ArticleStatus.clientReady.rawValue
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate { $0.statusRaw == pendingRaw || $0.statusRaw == clientReadyRaw },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        guard let pending = try? context.fetch(descriptor), !pending.isEmpty else {
            FolioLogger.network.debug("no pending articles to process")
            return
        }

        FolioLogger.network.info("processing \(pending.count) pending article(s)")

        if let processor = onProcessPending {
            let results = await processor(pending)
            for article in pending {
                let succeeded = results[article.id] ?? false
                if succeeded {
                    article.status = .processing
                }
                // Don't mark as failed on transient errors — keep status for retry
            }
        }
        // No else — without a processor, articles remain pending for next retry

        try? context.save()

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
