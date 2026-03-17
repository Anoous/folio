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
    @State private var showAddURL = false
    @State private var urlInput = ""
    @State private var articleToDelete: Article?
    @State private var showDeleteConfirmation = false
    @State private var showShareSheet = false
    @State private var shareItems: [Any]? = nil
    @State private var showAIAnswer = false

    private let mockTopics: [(name: String, count: Int)] = [
        ("AI & Machine Learning", 12),
        ("Swift & iOS Development", 8),
        ("Product Design", 5),
    ]

    private var isSearchActive: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        Group {
            if isSearchActive {
                searchResultsContent
            } else if viewModel?.articles.isEmpty ?? true {
                EmptyStateView(onPasteURL: { url in
                    saveURL(url.absoluteString)
                })
            } else {
                articleList
            }
        }
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
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: String(localized: "search.placeholder", defaultValue: "Search saved articles...")
        )
        .searchSuggestions {
            if !isSearchActive, let svm = searchViewModel {
                Text(String(
                    format: NSLocalizedString(
                        "search.syncedScope",
                        value: "Search %d saved articles",
                        comment: "Search scope hint"
                    ),
                    svm.syncedArticleCount
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .listRowSeparator(.hidden)

                if !svm.searchHistory.isEmpty {
                    Section {
                        ForEach(svm.searchHistory, id: \.self) { query in
                            Label(query, systemImage: "clock.arrow.circlepath")
                                .searchCompletion(query)
                        }
                    } header: {
                        HStack {
                            Text(String(localized: "search.recent", defaultValue: "Recent"))
                            Spacer()
                            Button(String(localized: "search.clearAll", defaultValue: "Clear")) {
                                svm.clearHistory()
                            }
                            .font(Typography.caption)
                            .foregroundStyle(Color.folio.accent)
                        }
                    }
                }

                if !svm.popularTags.isEmpty {
                    Section(String(localized: "search.popularTags", defaultValue: "Tags")) {
                        ForEach(svm.popularTags) { tag in
                            Label(tag.name, systemImage: "tag")
                                .searchCompletion(tag.name)
                        }
                    }
                }

                // Smart topics (mock data)
                Section(String(localized: "search.topics", defaultValue: "Topics")) {
                    ForEach(mockTopics, id: \.name) { topic in
                        Label {
                            HStack {
                                Text(topic.name)
                                Spacer()
                                Text(String(
                                    format: NSLocalizedString(
                                        "search.topicCount",
                                        value: "%d articles",
                                        comment: "Number of articles in topic"
                                    ),
                                    topic.count
                                ))
                                .font(Typography.caption)
                                .foregroundStyle(Color.folio.textTertiary)
                            }
                        } icon: {
                            Image(systemName: "folder")
                        }
                        .searchCompletion(topic.name)
                    }
                }
            }
        }
        .onSubmit(of: .search) {
            let query = searchText.trimmingCharacters(in: .whitespaces)
            if !query.isEmpty {
                searchViewModel?.saveToHistory(query)
            }
        }
        .onChange(of: searchText) { _, newValue in
            searchViewModel?.searchText = newValue
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
        .toast(isPresented: Binding(
            get: { viewModel?.showToast ?? false },
            set: { viewModel?.showToast = $0 }
        ), message: viewModel?.toastMessage ?? "", icon: viewModel?.toastIcon)
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
        .onAppear {
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
        .onChange(of: authViewModel?.isAuthenticated) { _, newValue in
            viewModel?.isAuthenticated = newValue ?? false
        }
        .onChange(of: scenePhase) { _, newPhase in
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

    private var deleteConfirmTitle: String {
        let title = articleToDelete?.displayTitle ?? ""
        return String(localized: "reader.deleteConfirm", defaultValue: "Delete this article?") + (title.isEmpty ? "" : "\n\"\(title)\"")
    }

    private var addButton: some View {
        Button {
            urlInput = ""
            if let url = UIPasteboard.general.url {
                urlInput = url.absoluteString
            } else if let string = UIPasteboard.general.string,
                      let url = URL(string: string), url.scheme?.hasPrefix("http") == true {
                urlInput = string
            }
            showAddURL = true
        } label: {
            Label(String(localized: "home.add", defaultValue: "Add"), systemImage: "plus")
        }
    }

    // MARK: - Search Results

    @ViewBuilder
    private var searchResultsContent: some View {
        if let svm = searchViewModel {
            if svm.isSearching {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = svm.searchError {
                searchErrorState(error: error)
            } else if svm.showsEmptyState {
                searchEmptyState
            } else {
                searchResultsList(svm: svm)
            }
        }
    }

    private func searchResultsList(svm: SearchViewModel) -> some View {
        List {
            Section {
                ForEach(svm.results) { item in
                    NavigationLink(value: item.article.id) {
                        SearchResultRow(
                            item: item,
                            searchQuery: svm.searchText
                        )
                    }
                    .listRowInsets(EdgeInsets())
                }
            } header: {
                Text("\(svm.resultCount) " + (svm.resultCount == 1
                    ? String(localized: "search.result", defaultValue: "result")
                    : String(localized: "search.results", defaultValue: "results")))
                    .font(Typography.caption)
                    .foregroundStyle(Color.folio.textTertiary)
            }
        }
        .listStyle(.plain)
    }

    private func searchErrorState(error: String) -> some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(Color.folio.error)

            Text(String(localized: "search.error", defaultValue: "Search failed"))
                .font(Typography.listTitle)
                .foregroundStyle(Color.folio.textPrimary)

            Text(error)
                .font(Typography.caption)
                .foregroundStyle(Color.folio.textTertiary)
                .multilineTextAlignment(.center)

            FolioButton(
                title: String(localized: "search.retry", defaultValue: "Retry"),
                style: .secondary
            ) {
                searchViewModel?.performSearch()
            }
            .frame(width: 160)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.screenPadding)
    }

    private var searchEmptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(Color.folio.textTertiary)

            Text(String(localized: "search.noResults", defaultValue: "No results found"))
                .font(Typography.listTitle)
                .foregroundStyle(Color.folio.textPrimary)

            Text(String(localized: "search.noResultsHint", defaultValue: "Try different keywords or check spelling"))
                .font(Typography.body)
                .foregroundStyle(Color.folio.textSecondary)
                .multilineTextAlignment(.center)

            if showAIAnswer {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(spacing: Spacing.xxs) {
                        Text("\u{2726}")
                            .font(.caption)
                            .foregroundStyle(Color.folio.accent)
                        Text("AI")
                            .font(Typography.tag)
                            .foregroundStyle(Color.folio.accent)
                    }
                    Text(String(localized: "search.aiMockAnswer", defaultValue: "Based on 4 articles in your collection, here are some relevant insights on this topic..."))
                        .font(Typography.body)
                        .foregroundStyle(Color.folio.textSecondary)
                        .lineSpacing(4)
                }
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.folio.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            } else {
                Button {
                    withAnimation { showAIAnswer = true }
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Text("\u{2728}")
                        Text(String(localized: "search.askAI", defaultValue: "Ask AI about your collection"))
                            .font(Typography.body)
                    }
                    .foregroundStyle(Color.folio.accent)
                }
                .buttonStyle(.plain)
                .padding(.top, Spacing.sm)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.screenPadding)
        .onChange(of: searchText) { _, _ in
            showAIAnswer = false
        }
    }

    // MARK: - Article List

    private var articleList: some View {
        List {
            statusBanners

            if let vm = viewModel {
                articleSections(vm: vm)
            }
        }
        .listStyle(.plain)
        .refreshable {
            if let syncService {
                await syncService.incrementalSync()
            }
            viewModel?.fetchArticles()
        }
        .task(id: viewModel?.hasProcessingArticles) {
            guard viewModel?.hasProcessingArticles == true else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
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

    // MARK: - Article Sections

    @ViewBuilder
    private func articleSections(vm: HomeViewModel) -> some View {
        ForEach(vm.groupedArticles, id: \.0) { group in
            Section {
                ForEach(group.1) { article in
                    articleRow(article: article, vm: vm, isLast: article.id == group.1.last?.id)
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

    private func articleRow(article: Article, vm: HomeViewModel, isLast: Bool) -> some View {
        NavigationLink(value: article.id) {
            ArticleCardView(article: article, onRetry: article.status == .failed ? {
                vm.retryArticle(article)
            } : nil)
        }
        .onAppear {
            if isLast { vm.loadNextPage() }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                articleToDelete = article
                showDeleteConfirmation = true
            } label: {
                Label(String(localized: "reader.delete", defaultValue: "Delete"), systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                vm.toggleFavorite(article)
            } label: {
                Label(
                    article.isFavorite
                        ? String(localized: "reader.unfavorite", defaultValue: "Remove Favorite")
                        : String(localized: "reader.favorite", defaultValue: "Favorite"),
                    systemImage: article.isFavorite ? "heart.slash" : "heart"
                )
            }
            .tint(article.isFavorite ? .gray : .pink)
        }
        .contextMenu {
            articleContextMenu(article: article, vm: vm)
        }
    }

    @ViewBuilder
    private func articleContextMenu(article: Article, vm: HomeViewModel) -> some View {
        // Retry (only for failed articles)
        if article.status == .failed {
            Button {
                vm.retryArticle(article)
            } label: {
                Label(String(localized: "article.retry", defaultValue: "Retry"), systemImage: "arrow.clockwise")
            }

            Divider()
        }

        Button {
            vm.toggleFavorite(article)
        } label: {
            Label(
                article.isFavorite
                    ? String(localized: "reader.unfavorite", defaultValue: "Remove Favorite")
                    : String(localized: "reader.favorite", defaultValue: "Favorite"),
                systemImage: article.isFavorite ? "heart.fill" : "heart"
            )
        }

        Button {
            vm.archiveArticle(article)
        } label: {
            Label(
                article.isArchived
                    ? String(localized: "reader.unarchive", defaultValue: "Unarchive")
                    : String(localized: "reader.archive", defaultValue: "Archive"),
                systemImage: article.isArchived ? "archivebox.fill" : "archivebox"
            )
        }

        Button {
            if let url = URL(string: article.url) {
                shareItems = [url]
                showShareSheet = true
            }
        } label: {
            Label(String(localized: "reader.share", defaultValue: "Share"), systemImage: "square.and.arrow.up")
        }

        Button {
            UIPasteboard.general.string = article.url
            vm.showToast = false
            DispatchQueue.main.async {
                vm.toastMessage = String(localized: "home.article.linkCopied", defaultValue: "Link copied")
                vm.toastIcon = "doc.on.doc"
                vm.showToast = true
            }
        } label: {
            Label(String(localized: "home.article.copyLink", defaultValue: "Copy Link"), systemImage: "link")
        }

        Divider()

        Button(role: .destructive) {
            articleToDelete = article
            showDeleteConfirmation = true
        } label: {
            Label(String(localized: "reader.delete", defaultValue: "Delete"), systemImage: "trash")
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

            Task {
                await offlineQueueManager?.processPendingArticles()
            }
        } catch SharedDataError.duplicateURL {
            showToast(String(localized: "home.addURL.duplicate", defaultValue: "Link already exists"), icon: "exclamationmark.triangle.fill")
        } catch {
            showToast(String(localized: "home.addURL.error", defaultValue: "Failed to save"), icon: "xmark.circle.fill")
        }
    }

    private func showToast(_ message: String, icon: String?) {
        viewModel?.toastMessage = message
        viewModel?.toastIcon = icon
        withAnimation { viewModel?.showToast = true }
    }

}
