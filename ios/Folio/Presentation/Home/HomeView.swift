import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AuthViewModel.self) private var authViewModel: AuthViewModel?
    @Environment(OfflineQueueManager.self) private var offlineQueueManager: OfflineQueueManager?
    @Environment(SyncService.self) private var syncService: SyncService?
    @State private var viewModel: HomeViewModel?
    @State private var searchViewModel: SearchViewModel?
    @State private var searchText = ""
    @State private var isSearchActive = false
    @State private var showNoteSheet = false
    @State private var noteSheetText = ""
    @State private var articleToDelete: Article?
    @State private var showDeleteConfirmation = false
    @State private var showShareSheet = false
    @State private var shareItems: [Any]? = nil
    @State private var saveSucceeded = false
    @State private var saveFailed = false
    @State private var deleteConfirmTrigger = false
    @State private var refreshTrigger = false
    @State private var recentSearchesVersion = 0
    @State private var showVoiceRecording = false
    @State private var saveService: ContentSaveService?
    @State private var showSettings = false
    @AppStorage(AppConstants.dismissedMilestonesKey) private var dismissedMilestonesRaw = ""

    // MARK: - Milestone Helpers

    private var dismissedMilestones: Set<Int> {
        Set(dismissedMilestonesRaw.split(separator: ",").compactMap { Int($0) })
    }

    private var isUserPro: Bool {
        authViewModel?.currentUser?.isPro == true
    }

    private var quotaSnapshot: HomeQuotaSnapshot {
        HomeQuotaSnapshot(
            user: authViewModel?.currentUser,
            isAuthenticated: authViewModel?.isAuthenticated ?? false
        )
    }

    private var activeMilestone: Milestone? {
        let count = viewModel?.articles.count ?? 0
        guard count > 0 else { return nil }
        let shown = dismissedMilestones
        // Show highest unshown milestone whose threshold has been reached.
        // A milestone is only relevant within a small window after its threshold;
        // beyond that it feels stale (e.g. showing "5 articles!" when user has 30).
        let staleMargin = 3
        for m in Milestone.allCases.reversed() {
            // Skip upgrade-oriented milestones for Pro users
            if m.showUpgrade && isUserPro { continue }
            let threshold = m.rawValue
            if count >= threshold && count <= threshold + staleMargin && !shown.contains(threshold) {
                return m
            }
        }
        return nil
    }

    private func dismissMilestone(_ milestone: Milestone) {
        var set = dismissedMilestones
        set.insert(milestone.rawValue)
        dismissedMilestonesRaw = set.sorted().map(String.init).joined(separator: ",")
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isSearchActive { topBar }
            mainContent
        }
        .safeAreaInset(edge: .bottom) {
            if !isSearchActive {
                CaptureBarView(
                    onMicTap: { showVoiceRecording = true },
                    onTextTap: {
                        noteSheetText = ""
                        showNoteSheet = true
                    },
                    onPhotoSelected: { image in
                        saveScreenshot(image)
                    }
                )
            }
        }
        .navigationBarHidden(true)
            .navigationDestination(isPresented: $showSettings) {
                SettingsView()
            }
            .toast(isPresented: showToastBinding, message: viewModel?.toastMessage ?? "", icon: viewModel?.toastIcon)
            .alert(
                deleteConfirmTitle,
                isPresented: $showDeleteConfirmation
            ) {
                Button(String(localized: "button.cancel", defaultValue: "Cancel"), role: .cancel) {
                    articleToDelete = nil
                }
                Button(String(localized: "reader.delete", defaultValue: "Delete"), role: .destructive) {
                    if let article = articleToDelete {
                        viewModel?.deleteArticle(article)
                        articleToDelete = nil
                    }
                }
            } message: {
                Text(String(localized: "reader.deleteMessage", defaultValue: "This article will be permanently removed."))
            }
            .sheet(isPresented: $showNoteSheet) {
                ManualNoteSheet(text: noteSheetText) { content in
                    if let url = URLDetection.extractURL(from: content) {
                        saveURL(url.absoluteString)
                    } else {
                        saveManualContent(content)
                    }
                    searchText = ""
                }
            }
            .sheet(isPresented: $showVoiceRecording) {
                VoiceRecordingView { transcribedText in
                    saveVoiceNote(transcribedText)
                }
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showShareSheet) {
                if let items = shareItems {
                    ShareSheet(activityItems: items)
                }
            }
            .sensoryFeedback(.success, trigger: saveSucceeded)
            .sensoryFeedback(.error, trigger: saveFailed)
            .sensoryFeedback(.impact(weight: .medium), trigger: deleteConfirmTrigger)
            .sensoryFeedback(.impact(weight: .light), trigger: refreshTrigger)
            .onAppear(perform: initializeViewModels)
            .onChange(of: authViewModel?.isAuthenticated) { _, newValue in
                viewModel?.isAuthenticated = newValue ?? false
                if newValue == true {
                    Task { await viewModel?.fetchEchoCards() }
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                handleScenePhaseChange(newPhase)
            }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Text("页集")
                .font(Typography.v3PageTitle)
                .foregroundStyle(Color.folio.textPrimary)
            Spacer()
            HStack(spacing: 4) {
                Button("搜索", systemImage: "magnifyingglass") {
                    isSearchActive = true
                }
                .labelStyle(.iconOnly)
                .frame(width: 38, height: 38)
                .foregroundStyle(Color.folio.textSecondary)

                Button("设置", systemImage: "gearshape") {
                    showSettings = true
                }
                .labelStyle(.iconOnly)
                .frame(width: 38, height: 38)
                .foregroundStyle(Color.folio.textSecondary)
            }
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.top, 6)
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        if isSearchActive, let vm = viewModel {
            HomeSearchView(
                searchText: $searchText,
                viewModel: vm,
                searchViewModel: searchViewModel,
                recentSearches: recentSearches,
                onDismiss: { isSearchActive = false },
                onSaveURL: { url in saveURL(url) },
                onSaveNote: { content in
                    noteSheetText = content
                    showNoteSheet = true
                },
                onShowNoteSheet: {
                    noteSheetText = ""
                    showNoteSheet = true
                    isSearchActive = false
                },
                onSaveRecentSearch: { query in saveRecentSearch(query) },
                findExistingArticle: { text in findExistingArticle(for: text) }
            )
        } else if let vm = viewModel {
            workbenchView(vm)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func workbenchView(_ vm: HomeViewModel) -> some View {
        HomeWorkbenchView(
            viewModel: vm,
            quotaSnapshot: quotaSnapshot,
            isAuthenticated: authViewModel?.isAuthenticated ?? false,
            isNetworkAvailable: offlineQueueManager?.isNetworkAvailable ?? true,
            activeMilestone: activeMilestone,
            onDismissMilestone: dismissMilestone,
            onOpenSearch: {
                searchText = ""
                isSearchActive = true
            },
            onOpenSettings: {
                showSettings = true
            },
            onPasteURL: { url in
                saveURL(url.absoluteString)
            },
            onTextTap: {
                noteSheetText = ""
                showNoteSheet = true
            },
            onMicTap: {
                showVoiceRecording = true
            },
            onPhotoSelected: { image in
                saveScreenshot(image)
            },
            onArticleAction: { action, article in
                handleArticleAction(action, article: article, vm: vm)
            },
            onRetrySync: {
                Task {
                    await syncService?.incrementalSync()
                    vm.fetchArticles()
                }
            },
            onDismissSyncError: {
                vm.dismissSyncError()
            },
            onRetryEcho: {
                Task { await vm.fetchEchoCards() }
            }
        )
        .refreshable {
            refreshTrigger.toggle()
            if let syncService {
                await syncService.incrementalSync()
            }
            vm.fetchArticles()
            await vm.fetchEchoCards()
        }
        .task(id: vm.hasProcessingArticles) {
            guard vm.hasProcessingArticles else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                await syncService?.fetchProcessingArticles()
                vm.fetchArticles()
            }
        }
        .overlay(alignment: .top) {
            if vm.isLoading {
                SyncProgressBar()
            }
        }
    }

    // MARK: - Search Content

    private var recentSearches: [String] {
        // recentSearchesVersion forces SwiftUI to re-evaluate when list changes
        _ = recentSearchesVersion
        return Array(
            (UserDefaults.standard.stringArray(forKey: AppConstants.searchHistoryKey) ?? []).prefix(5)
        )
    }

    private func saveRecentSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var recent = UserDefaults.standard.stringArray(forKey: AppConstants.searchHistoryKey) ?? []
        recent.removeAll { $0 == trimmed }
        recent.insert(trimmed, at: 0)
        if recent.count > 10 { recent = Array(recent.prefix(10)) }
        UserDefaults.standard.set(recent, forKey: AppConstants.searchHistoryKey)
        recentSearchesVersion += 1
    }

    // MARK: - Toast Binding

    private var showToastBinding: Binding<Bool> {
        Binding(
            get: { viewModel?.showToast ?? false },
            set: { viewModel?.showToast = $0 }
        )
    }

    // MARK: - Delete Confirmation

    private var deleteConfirmTitle: String {
        let title = articleToDelete?.displayTitle ?? ""
        return String(localized: "reader.deleteConfirm", defaultValue: "Delete this article?") + (title.isEmpty ? "" : "\n\"\(title)\"")
    }

    // MARK: - Article Actions

    private func handleArticleAction(_ action: ArticleRowAction, article: Article, vm: HomeViewModel) {
        switch action {
        case .loadMore:
            vm.loadNextPage()
        case .toggleFavorite:
            vm.toggleFavorite(article)
        case .retry:
            vm.retryArticle(article)
        case .delete:
            articleToDelete = article
            showDeleteConfirmation = true
            deleteConfirmTrigger.toggle()
        case .archive:
            vm.archiveArticle(article)
        case .share(let url):
            shareItems = [url]
            showShareSheet = true
        case .copyLink(let urlString):
            UIPasteboard.general.string = urlString
            showToast(String(localized: "home.article.linkCopied", defaultValue: "Link copied"), icon: "doc.on.doc")
            saveSucceeded.toggle()
        }
    }

    // MARK: - URL Lookup

    private func findExistingArticle(for text: String) -> Article? {
        guard URLDetection.isURLOnly(text) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let repo = ArticleRepository(context: modelContext)
        return try? repo.fetchByURL(trimmed)
    }

    // MARK: - Actions

    private func saveURL(_ urlString: String) {
        guard let result = saveService?.saveURL(urlString) else { return }
        handleSaveResult(result)
        if case .success = result { viewModel?.fetchArticles() }
    }

    private func saveManualContent(_ content: String) {
        guard let result = saveService?.saveManualContent(content) else { return }
        handleSaveResult(result)
        if case .success = result { viewModel?.fetchArticles() }
    }

    private func saveScreenshot(_ image: UIImage) {
        guard let result = saveService?.saveScreenshot(image, onOCRComplete: {
            viewModel?.fetchArticles()
        }) else { return }
        handleSaveResult(result)
        if case .success = result { viewModel?.fetchArticles() }
    }

    private func saveVoiceNote(_ transcribedText: String) {
        guard let result = saveService?.saveVoiceNote(transcribedText) else { return }
        handleSaveResult(result)
        if case .success = result { viewModel?.fetchArticles() }
    }

    private func handleSaveResult(_ result: ContentSaveService.SaveResult) {
        switch result {
        case .success(let message, let icon):
            showToast(message, icon: icon)
            saveSucceeded.toggle()
        case .duplicate:
            showToast(String(localized: "home.addURL.duplicate", defaultValue: "Link already exists"), icon: "exclamationmark.triangle.fill")
            saveFailed.toggle()
        case .quotaExceeded:
            showToast(String(localized: "home.quotaExceeded", defaultValue: "Monthly quota exceeded"), icon: "exclamationmark.triangle.fill")
            saveFailed.toggle()
        case .error(let message):
            showToast(message, icon: "xmark.circle.fill")
            saveFailed.toggle()
        }
    }

    private func showToast(_ message: String, icon: String?) {
        viewModel?.toastMessage = message
        viewModel?.toastIcon = icon
        withAnimation(Motion.ink) { viewModel?.showToast = true }
    }

    // MARK: - Lifecycle

    private func initializeViewModels() {
        if viewModel == nil {
            viewModel = HomeViewModel(
                context: modelContext,
                isAuthenticated: authViewModel?.isAuthenticated ?? false
            )
            viewModel?.fetchArticles()
            Task { await viewModel?.fetchEchoCards() }
        }
        if saveService == nil {
            saveService = ContentSaveService(context: modelContext, syncService: syncService)
        }
        if searchViewModel == nil {
            let svm = SearchViewModel(
                searchManager: SearchIndexCoordinator.shared.searchManager,
                context: modelContext
            )
            searchViewModel = svm
            svm.loadPopularTags()
            svm.refreshSyncedCount(context: modelContext)
        }
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        if newPhase == .active {
            let flag = UserDefaults.appGroup.bool(forKey: AppConstants.shareExtensionDidSaveKey)
            FolioLogger.data.info("home-debug: scenePhase=active, shareFlag=\(flag)")
            if flag {
                UserDefaults.appGroup.set(false, forKey: AppConstants.shareExtensionDidSaveKey)
                viewModel?.fetchArticles()
                SearchIndexCoordinator.shared.rebuild(context: modelContext)
                searchViewModel?.refreshSyncedCount(context: modelContext)
                FolioLogger.data.info("home-debug: fetchArticles called, vm.articles.count=\(viewModel?.articles.count ?? -1)")
            }
        }
    }

}
