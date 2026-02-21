import SwiftUI
import SwiftData

@main
struct FolioApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    let container: ModelContainer
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var authViewModel = AuthViewModel()
    @State private var offlineQueueManager: OfflineQueueManager?
    @State private var syncService: SyncService?

    init() {
        do {
            let config: ModelConfiguration
            if let _ = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.folio.app") {
                config = ModelConfiguration(
                    "Folio",
                    schema: DataManager.schema,
                    groupContainer: .identifier("group.com.folio.app")
                )
            } else {
                config = ModelConfiguration("Folio", schema: DataManager.schema)
            }
            container = try ModelContainer(for: DataManager.schema, configurations: [config])
            DataManager.shared.preloadCategories(in: container.mainContext)
            _offlineQueueManager = State(initialValue: OfflineQueueManager(context: container.mainContext))
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    MainTabView()
                } else {
                    OnboardingView {
                        hasCompletedOnboarding = true
                    }
                }
            }
            .environment(authViewModel)
            .environment(offlineQueueManager)
            .task {
                await authViewModel.checkExistingAuth()
            }
            .onChange(of: authViewModel.authState) { _, newValue in
                if newValue == .signedIn, let manager = offlineQueueManager {
                    let sync = SyncService(context: container.mainContext)
                    syncService = sync
                    manager.onProcessPending = { articles in
                        await sync.submitPendingArticles(articles)
                    }
                    Task {
                        await sync.performFullSync()
                        await manager.processPendingArticles()
                    }
                } else if newValue == .signedOut {
                    offlineQueueManager?.onProcessPending = nil
                    syncService = nil
                }
            }
        }
        .modelContainer(container)
    }
}
