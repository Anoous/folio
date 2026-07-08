import Foundation
import Network
import Observation
import SwiftData
import BackgroundTasks
import Combine

@MainActor
@Observable
final class OfflineQueueManager {
    static let backgroundTaskIdentifier = "com.folio.article-processing"
    static var backgroundTaskSubmitter: (BGProcessingTaskRequest) throws -> Void = { request in
        try BGTaskScheduler.shared.submit(request)
    }
    static var backgroundSyncAction: @Sendable () async -> Bool = {
        await BackgroundSyncCoordinator.runPendingSyncIfNeeded()
    }

    var pendingCount: Int = 0
    var isNetworkAvailable: Bool = true

    private let context: ModelContext
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.folio.network-monitor")

    /// Callback invoked when network becomes available — triggers a full incremental sync.
    var onNetworkRestored: (() async -> Void)?

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
                    await self.onNetworkRestored?()
                    self.refreshPendingCount()
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

    // MARK: - Background Tasks

    static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundTaskIdentifier,
            using: nil
        ) { task in
            guard let bgTask = task as? BGProcessingTask else { return }
            let workerTask = Task {
                await handleBackgroundTask(bgTask)
            }
            bgTask.expirationHandler = {
                workerTask.cancel()
            }
        }
    }

    private static func handleBackgroundTask(_ task: BGProcessingTask) async {
        scheduleBackgroundProcessing()
        let success = await backgroundSyncAction()
        task.setTaskCompleted(success: success)
    }

    static func scheduleBackgroundProcessing() {
        let request = BGProcessingTaskRequest(identifier: backgroundTaskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        do {
            try backgroundTaskSubmitter(request)
        } catch {
            FolioLogger.network.debug("background task scheduling skipped: \(error)")
        }
    }
}
