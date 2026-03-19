import SwiftUI

private enum HomeDestination: Hashable {
    case settings
}

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AuthViewModel.self) private var authViewModel: AuthViewModel?
    @Environment(OfflineQueueManager.self) private var offlineQueueManager: OfflineQueueManager?
    @Environment(SyncService.self) private var syncService: SyncService?
    @State private var viewModel: HomeViewModel?
    @State private var searchViewModel: SearchViewModel?
    @State private var searchText = ""
    @FocusState private var isInputFocused: Bool
    @State private var isSearching = false
    @State private var showAddURL = false
    @State private var urlInput = ""
    @State private var articleToDelete: Article?
    @State private var showDeleteConfirmation = false
    @State private var showShareSheet = false
    @State private var shareItems: [Any]? = nil
    @State private var saveSucceeded = false
    @State private var saveFailed = false
    @State private var deleteConfirmTrigger = false
    @State private var refreshTrigger = false

    var body: some View {
        coreView
        .sensoryFeedback(.success, trigger: saveSucceeded)
        .sensoryFeedback(.error, trigger: saveFailed)
        .sensoryFeedback(.impact(weight: .medium), trigger: deleteConfirmTrigger)
        .sensoryFeedback(.impact(weight: .light), trigger: refreshTrigger)
        .onAppear(perform: initializeViewModels)
        .onChange(of: authViewModel?.isAuthenticated) { _, newValue in
            viewModel?.isAuthenticated = newValue ?? false
        }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
        }
    }

    private var coreView: some View {
        mainContent
        .navigationTitle("Folio")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink(value: HomeDestination.settings) {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel(String(localized: "tab.settings", defaultValue: "Settings"))
            }
            ToolbarItem(placement: .topBarTrailing) {
                addButton
            }
        }
        .safeAreaInset(edge: .bottom) {
            UnifiedInputBar(text: $searchText, isFocused: $isInputFocused) { content in
                if UnifiedInputBar.isURLOnly(content) {
                    saveURL(content)
                } else {
                    saveManualContent(content)
                }
            }
        }
        .onChange(of: searchText) { _, newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            withAnimation(Motion.quick) {
                isSearching = !trimmed.isEmpty
            }
            if trimmed.isEmpty {
                viewModel?.fetchArticles()
            } else {
                searchViewModel?.searchText = trimmed
            }
        }
        .alert(String(localized: "home.addURL.title", defaultValue: "Add Link"), isPresented: $showAddURL) {
            TextField(String(localized: "home.addURL.placeholder", defaultValue: "https://"), text: $urlInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button(String(localized: "button.cancel", defaultValue: "Cancel"), role: .cancel) {}
            Button(String(localized: "home.addURL.save", defaultValue: "Save")) {
                let trimmed = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                saveURL(trimmed)
            }
        } message: {
            Text(String(localized: "home.addURL.message", defaultValue: "Enter or paste a link to save"))
        }
        .navigationDestination(for: UUID.self) { articleID in
            if let article = viewModel?.articles.first(where: { $0.id == articleID }) {
                ReaderView(article: article)
            }
        }
        .navigationDestination(for: HomeDestination.self) { destination in
            switch destination {
            case .settings:
                SettingsView()
            }
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
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        if isSearching, let svm = searchViewModel {
            HomeSearchResultsView(searchViewModel: svm, searchText: $searchText)
                .transition(.opacity)
        } else if viewModel?.articles.isEmpty ?? true {
            EmptyStateView(onPasteURL: { url in
                saveURL(url.absoluteString)
            })
            .transition(.opacity)
        } else {
            articleList
                .transition(.opacity)
        }
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

    // MARK: - Add Button

    private var addButton: some View {
        Button(action: prepareAddURL) {
            Label(String(localized: "home.add", defaultValue: "Add"), systemImage: "plus")
        }
    }

    private func prepareAddURL() {
        urlInput = ""
        if let url = UIPasteboard.general.url {
            urlInput = url.absoluteString
        } else if let string = UIPasteboard.general.string,
                  let url = URL(string: string), url.scheme?.hasPrefix("http") == true {
            urlInput = string
        }
        showAddURL = true
    }

    // MARK: - Article List

    private var articleList: some View {
        List {
            statusBanners

            if let vm = viewModel {
                ForEach(vm.groupedArticles, id: \.0) { group in
                    Section {
                        ForEach(group.1) { article in
                            HomeArticleRow(
                                article: article,
                                isLast: article.id == group.1.last?.id
                            ) { action in
                                handleArticleAction(action, article: article, vm: vm)
                            }
                        }
                    } header: {
                        Text(group.0)
                            .font(Typography.caption)
                            .foregroundStyle(Color.folio.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Spacing.screenPadding)
                            .padding(.vertical, 8)
                            .background(Color.folio.background)
                            .listRowInsets(EdgeInsets())
                    }
                }
                .listRowInsets(EdgeInsets(top: 0, leading: Spacing.screenPadding, bottom: 0, trailing: Spacing.screenPadding))
                .listRowSeparatorTint(Color.folio.separator)
            }
        }
        .listStyle(.plain)
        .refreshable {
            refreshTrigger.toggle()
            if let syncService {
                await syncService.incrementalSync()
            }
            viewModel?.fetchArticles()
        }
        .task(id: viewModel?.hasProcessingArticles) {
            guard viewModel?.hasProcessingArticles == true else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                await syncService?.fetchProcessingArticles()
                viewModel?.fetchArticles()
            }
        }
        .background(Color.folio.background)
        .sheet(isPresented: $showShareSheet) {
            if let items = shareItems {
                ShareSheet(activityItems: items)
            }
        }
    }

    // MARK: - Status Banners

    @ViewBuilder
    private var statusBanners: some View {
        if offlineQueueManager?.isNetworkAvailable == false {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "wifi.slash")
                    .foregroundStyle(Color.folio.textTertiary)
                Text(String(localized: "home.offlineBanner", defaultValue: "You're offline. Changes will sync when connected."))
                    .font(Typography.caption)
                    .foregroundStyle(Color.folio.textSecondary)
            }
            .padding(.vertical, Spacing.xxs)
        }

        if viewModel?.isLoading == true {
            HStack(spacing: Spacing.xs) {
                ProgressView()
                    .scaleEffect(0.7)
                Text(String(localized: "home.syncing", defaultValue: "Syncing..."))
                    .font(Typography.caption)
                    .foregroundStyle(Color.folio.textSecondary)
            }
            .padding(.vertical, Spacing.xxs)
        }

        if let syncError = viewModel?.syncError {
            syncErrorBanner(syncError)
        }
    }

    private func syncErrorBanner(_ syncError: String) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "exclamationmark.icloud.fill")
                .foregroundStyle(Color.folio.error)
            Text(syncError)
                .font(Typography.caption)
                .foregroundStyle(Color.folio.error)
                .lineLimit(2)
            Spacer()
            Button {
                Task {
                    await syncService?.incrementalSync()
                    viewModel?.fetchArticles()
                }
            } label: {
                Text(String(localized: "home.retry", defaultValue: "Retry"))
                    .font(Typography.caption)
                    .foregroundStyle(Color.folio.accent)
            }
            .buttonStyle(.plain)
            Button {
                viewModel?.dismissSyncError()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(Color.folio.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, Spacing.xxs)
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

    // MARK: - Actions

    private func saveURL(_ urlString: String) {
        let manager = SharedDataManager(context: modelContext)
        do {
            _ = try manager.saveArticleFromText(urlString)
            SharedDataManager.incrementQuota()
            viewModel?.fetchArticles()
            showToast(String(localized: "home.addURL.saved", defaultValue: "Link saved"), icon: "checkmark.circle.fill")
            saveSucceeded.toggle()

            Task {
                await offlineQueueManager?.processPendingArticles()
            }
        } catch SharedDataError.duplicateURL {
            showToast(String(localized: "home.addURL.duplicate", defaultValue: "Link already exists"), icon: "exclamationmark.triangle.fill")
            saveFailed.toggle()
        } catch {
            showToast(String(localized: "home.addURL.error", defaultValue: "Failed to save"), icon: "xmark.circle.fill")
            saveFailed.toggle()
        }
    }

    private func saveManualContent(_ content: String) {
        let isPro = UserDefaults.appGroup.bool(forKey: SharedDataManager.isProUserKey)
        guard SharedDataManager.canSave(isPro: isPro) else {
            showToast(String(localized: "home.quotaExceeded", defaultValue: "Monthly quota exceeded"), icon: "exclamationmark.triangle.fill")
            saveFailed.toggle()
            return
        }

        let manager = SharedDataManager(context: modelContext)
        do {
            _ = try manager.saveManualContent(content: content)
            SharedDataManager.incrementQuota()
            viewModel?.fetchArticles()
            showToast(String(localized: "home.manualSaved", defaultValue: "Saved"), icon: "checkmark.circle.fill")
            saveSucceeded.toggle()

            Task {
                await offlineQueueManager?.processPendingArticles()
            }
        } catch {
            showToast(String(localized: "home.manualSaveError", defaultValue: "Failed to save"), icon: "xmark.circle.fill")
            saveFailed.toggle()
        }
    }

    private func showToast(_ message: String, icon: String?) {
        viewModel?.toastMessage = message
        viewModel?.toastIcon = icon
        withAnimation { viewModel?.showToast = true }
    }

    // MARK: - Lifecycle

    private func initializeViewModels() {
        if viewModel == nil {
            viewModel = HomeViewModel(
                context: modelContext,
                isAuthenticated: authViewModel?.isAuthenticated ?? false
            )
            viewModel?.fetchArticles()
        }
        if searchViewModel == nil {
            guard let manager = try? FTS5SearchManager(inMemory: false) else { return }
            let svm = SearchViewModel(searchManager: manager, context: modelContext)
            searchViewModel = svm
            svm.loadPopularTags()
            svm.refreshSyncedCount(context: modelContext)
        }
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        // Share Extension 在独立进程中写入 SQLite，主 App 的 ModelContext
        // 不会自动感知跨进程变更。通过 UserDefaults 标志位检测后重新 fetch。
        if newPhase == .active {
            let flag = UserDefaults.appGroup.bool(forKey: AppConstants.shareExtensionDidSaveKey)
            FolioLogger.data.info("home-debug: scenePhase=active, shareFlag=\(flag)")
            if flag {
                UserDefaults.appGroup.set(false, forKey: AppConstants.shareExtensionDidSaveKey)
                viewModel?.fetchArticles()
                searchViewModel?.refreshSyncedCount(context: modelContext)
                FolioLogger.data.info("home-debug: fetchArticles called, vm.articles.count=\(viewModel?.articles.count ?? -1)")
            }
        }
    }

}
