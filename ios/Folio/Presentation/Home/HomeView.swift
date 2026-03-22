import SwiftData
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

    var body: some View {
        mainContent
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("页集")
                        .font(Typography.v3PageTitle)
                        .foregroundStyle(Color.folio.textPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: HomeDestination.settings) {
                        Circle()
                            .fill(Color.folio.textTertiary.opacity(0.2))
                            .frame(width: 30, height: 30)
                            .overlay {
                                Image(systemName: "person.fill")
                                    .font(.caption)
                                    .foregroundStyle(Color.folio.textTertiary)
                            }
                    }
                    .accessibilityLabel(String(localized: "tab.settings", defaultValue: "Settings"))
                }
            }
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: String(localized: "search.prompt", defaultValue: "Search or paste a link...")
            )
            .onChange(of: searchText) { _, newValue in
                handleSearchTextChange(newValue)
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
            .sheet(isPresented: $showNoteSheet) {
                ManualNoteSheet(text: noteSheetText) { content in
                    saveManualContent(content)
                    searchText = ""
                }
            }
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

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let isSearchActive = !trimmed.isEmpty

        if isSearchActive, let svm = searchViewModel {
            HomeSearchResultsView(
                searchViewModel: svm,
                searchText: $searchText,
                detectedURL: URLDetection.extractURL(from: trimmed),
                existingArticle: findExistingArticle(for: trimmed),
                onSaveURL: { url in saveURL(url) },
                onSaveNote: { content in
                    noteSheetText = content
                    showNoteSheet = true
                }
            )
        } else if viewModel?.articles.isEmpty ?? true {
            EmptyStateView(onPasteURL: { url in
                saveURL(url.absoluteString)
            })
        } else {
            articleList
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

    // MARK: - Article List (sectioned by date)

    private var articleList: some View {
        List {
            statusBanners

            // Date header
            Text(formattedDate())
                .font(.system(size: 13))
                .foregroundStyle(Color.folio.textTertiary)
                .tracking(0.5)
                .listRowInsets(EdgeInsets(top: 0, leading: Spacing.screenPadding, bottom: 0, trailing: Spacing.screenPadding))
                .listRowSeparator(.hidden)
                .padding(.top, Spacing.md)

            if let vm = viewModel {
                ForEach(vm.groupedArticles, id: \.group) { section in
                    Section {
                        ForEach(Array(section.articles.enumerated()), id: \.element.id) { index, article in
                            if section.group == .today && index == 0 && article.readProgress == 0 && article.status == .ready {
                                NavigationLink(value: article.id) {
                                    HeroArticleCardView(article: article)
                                }
                                .listRowInsets(EdgeInsets(top: 0, leading: Spacing.screenPadding, bottom: 0, trailing: Spacing.screenPadding))
                                .listRowSeparator(.hidden)
                                .onAppear {
                                    if article.id == vm.articles.last?.id {
                                        vm.loadNextPage()
                                    }
                                }
                            } else {
                                HomeArticleRow(
                                    article: article,
                                    isLast: article.id == vm.articles.last?.id
                                ) { action in
                                    handleArticleAction(action, article: article, vm: vm)
                                }
                                .listRowInsets(EdgeInsets(top: 0, leading: Spacing.screenPadding, bottom: 0, trailing: Spacing.screenPadding))
                                .listRowSeparator(.hidden)
                            }
                        }
                    } header: {
                        Text(section.group.rawValue)
                            .font(Typography.v3SectionHeader)
                            .foregroundStyle(Color.folio.textTertiary)
                            .tracking(0.3)
                            .textCase(nil)
                    }
                    .listSectionSeparator(.hidden)
                }
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
        .overlay(alignment: .top) {
            if viewModel?.isLoading == true {
                SyncProgressBar()
            }
        }
        .background(Color.folio.background)
        .sheet(isPresented: $showShareSheet) {
            if let items = shareItems {
                ShareSheet(activityItems: items)
            }
        }
    }

    // MARK: - Date Formatting

    private func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日，EEEE"
        return formatter.string(from: .now)
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

    // MARK: - Search

    private func handleSearchTextChange(_ newValue: String) {
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            viewModel?.fetchArticles()
        } else {
            searchViewModel?.searchText = trimmed
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
        let isPro = UserDefaults.appGroup.bool(forKey: SharedDataManager.isProUserKey)
        guard SharedDataManager.canSave(isPro: isPro) else {
            showToast(String(localized: "home.quotaExceeded", defaultValue: "Monthly quota exceeded"), icon: "exclamationmark.triangle.fill")
            saveFailed.toggle()
            return
        }

        let manager = SharedDataManager(context: modelContext)
        do {
            _ = try manager.saveArticleFromText(urlString)
            SharedDataManager.incrementQuota()
            viewModel?.fetchArticles()
            showToast(String(localized: "home.addURL.saved", defaultValue: "Link saved"), icon: "checkmark.circle.fill")
            saveSucceeded.toggle()

            Task {
                await syncService?.incrementalSync()
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
                await syncService?.incrementalSync()
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
