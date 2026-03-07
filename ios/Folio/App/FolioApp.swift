import SwiftUI
import SwiftData
import os

@main
struct FolioApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    let container: ModelContainer
    @AppStorage(AppConstants.onboardingCompletedKey) private var hasCompletedOnboarding = false
    @State private var authViewModel = AuthViewModel()
    @State private var offlineQueueManager: OfflineQueueManager?
    @State private var syncService: SyncService?

    init() {
        do {
            let config: ModelConfiguration
            if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroupIdentifier) != nil {
                config = ModelConfiguration(
                    "Folio",
                    schema: DataManager.schema,
                    groupContainer: .identifier(AppConstants.appGroupIdentifier)
                )
            } else {
                config = ModelConfiguration("Folio", schema: DataManager.schema)
            }
            let c = try ModelContainer(for: DataManager.schema, configurations: [config])
            let storeURL = c.configurations.first?.url.path ?? "unknown"
            FolioLogger.data.info("app-debug: storeURL=\(storeURL)")
            container = c
            DataManager.shared.preloadCategories(in: container.mainContext)
            let ctx = container.mainContext
            _offlineQueueManager = State(initialValue: OfflineQueueManager(context: ctx))
            _syncService = State(initialValue: SyncService(context: ctx))
            FolioLogger.data.info("app started, ModelContainer initialized")
        } catch {
            FolioLogger.data.fault("ModelContainer creation failed: \(error)")
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    NavigationStack {
                        HomeView()
                    }
                } else {
                    OnboardingView {
                        hasCompletedOnboarding = true
                    }
                }
            }
            .environment(authViewModel)
            .environment(offlineQueueManager)
            .environment(syncService)
            .task {
                await authViewModel.checkExistingAuth()
            }
            .onChange(of: authViewModel.authState) { _, newValue in
                if newValue == .signedIn, let manager = offlineQueueManager, let sync = syncService {
                    // 将服务端配额同步到 UserDefaults，Share Extension 依赖此值
                    if let user = authViewModel.currentUser {
                        let isPro = user.subscription != "free"
                        SharedDataManager.syncQuotaFromServer(
                            monthlyQuota: user.monthlyQuota,
                            currentMonthCount: user.currentMonthCount,
                            isPro: isPro
                        )
                    }
                    manager.onProcessPending = { articles in
                        await sync.submitPendingArticles(articles)
                    }
                    manager.onSyncDeletionsAndUpdates = {
                        await sync.syncDeletions()
                    }
                    Task {
                        await sync.performFullSync()
                        await manager.processPendingArticles()
                    }
                } else if newValue == .signedOut {
                    offlineQueueManager?.onProcessPending = nil
                    offlineQueueManager?.onSyncDeletionsAndUpdates = nil
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    if let manager = offlineQueueManager {
                        manager.refreshPendingCount()
                        if manager.pendingCount > 0 {
                            Task {
                                await manager.processPendingArticles()
                            }
                        }
                    }
                    if authViewModel.authState == .signedIn, let sync = syncService {
                        Task { await sync.incrementalSync() }
                    }
                }
            }
        }
        .modelContainer(container)
    }
}
