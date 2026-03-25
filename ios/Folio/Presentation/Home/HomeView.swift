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
    @Environment(\.selectArticle) private var selectArticle
    @AppStorage("dismissed_milestones") private var dismissedMilestonesRaw = ""

    // MARK: - Milestone Helpers

    private var dismissedMilestones: Set<Int> {
        Set(dismissedMilestonesRaw.split(separator: ",").compactMap { Int($0) })
    }

    private var activeMilestone: Milestone? {
        let count = viewModel?.articles.count ?? 0
        guard count > 0 else { return nil }
        let shown = dismissedMilestones
        // Show highest unshown milestone whose threshold has been reached
        for m in Milestone.allCases.reversed() {
            if count >= m.rawValue && !shown.contains(m.rawValue) {
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
            // Custom top bar (prototype 01)
            if !isSearchActive {
                HStack {
                    Text("页集")
                        .font(Typography.v3PageTitle)
                        .foregroundStyle(Color.folio.textPrimary)
                    Spacer()
                    HStack(spacing: 4) {
                        Button { isSearchActive = true } label: {
                            Circle().fill(Color.clear).frame(width: 38, height: 38)
                                .overlay {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(Color.folio.textSecondary)
                                }
                        }
                        NavigationLink(value: HomeDestination.settings) {
                            Circle().fill(Color.clear).frame(width: 38, height: 38)
                                .overlay {
                                    Image(systemName: "gearshape")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(Color.folio.textSecondary)
                                }
                        }
                    }
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, 6)
            }

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
            .sheet(isPresented: $showVoiceRecording) {
                VoiceRecordingView { transcribedText in
                    saveVoiceNote(transcribedText)
                }
                .presentationDetents([.medium])
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

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        if isSearchActive {
            searchContent
        } else if viewModel?.articles.isEmpty ?? true {
            VStack(spacing: 0) {
                dateHeader
                EmptyStateView(onPasteURL: { url in
                    saveURL(url.absoluteString)
                })
            }
        } else {
            articleList
        }
    }

    // MARK: - Search Content

    private var searchContent: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.folio.textTertiary)
                    TextField("搜索，或提问", text: $searchText)
                        .font(.system(size: 16))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit {
                            let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty { saveRecentSearch(trimmed) }
                            handleSearchTextChange(searchText)
                        }
                        .onChange(of: searchText) { _, newValue in
                            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                            if let vm = viewModel, vm.isRAGQuery(trimmed) {
                                saveRecentSearch(trimmed)
                                vm.submitRAGQuery(trimmed)
                                // Clear FTS state when switching to RAG
                                searchViewModel?.searchText = ""
                            } else {
                                viewModel?.clearRAG()
                                handleSearchTextChange(newValue)
                            }
                        }
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(Color.folio.textTertiary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.folio.echoBg)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                Button("取消") {
                    searchText = ""
                    viewModel?.clearRAG()
                    isSearchActive = false
                }
                .font(.system(size: 16))
                .foregroundStyle(Color.folio.accent)
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.vertical, 10)

            // Search results — RAG and FTS are mutually exclusive
            let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                if let vm = viewModel, vm.isRAGQuery(trimmed) {
                    // RAG mode
                    if vm.ragIsLoading {
                        RAGLoadingView()
                    } else if let error = vm.ragError {
                        RAGErrorView(errorType: error, onRetry: { vm.submitRAGQuery(trimmed) })
                    } else if let response = vm.ragResponse {
                        ScrollView {
                            RAGAnswerView(
                                thread: vm.ragThread,
                                response: response,
                                onSourceTap: { articleId in
                                    // TODO: Navigate to reader for this article
                                },
                                onFollowup: { question in
                                    vm.submitFollowup(question)
                                }
                            )
                        }
                    } else {
                        Spacer() // RAG not yet triggered
                    }
                } else if let svm = searchViewModel {
                    // FTS mode (existing search results)
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
                }
            } else {
                searchSuggestionsContent
            }
        }
    }

    // MARK: - Search Suggestions

    private var recentSearches: [String] {
        // recentSearchesVersion forces SwiftUI to re-evaluate when list changes
        _ = recentSearchesVersion
        return Array(
            (UserDefaults.standard.stringArray(forKey: AppConstants.searchHistoryKey) ?? []).prefix(5)
        )
    }

    private var suggestedQuestions: [String] {
        [
            "我存过的文章里关于用户留存有哪些方法？",
            "哪些文章提到了飞轮效应？",
            "量子计算最近有什么进展？",
        ]
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

    private var searchSuggestionsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Recent searches
                if !recentSearches.isEmpty {
                    Text("最近")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.folio.textTertiary)
                        .tracking(0.5)
                        .padding(.horizontal, Spacing.screenPadding)
                        .padding(.top, 20)
                        .padding(.bottom, 12)

                    ForEach(recentSearches, id: \.self) { search in
                        Button {
                            searchText = search
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color.folio.textTertiary)
                                Text(search)
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color.folio.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, Spacing.screenPadding)
                            .padding(.vertical, 12)
                        }
                    }

                    Rectangle()
                        .fill(Color.folio.separator)
                        .frame(height: 0.5)
                        .padding(.horizontal, Spacing.screenPadding)
                        .padding(.vertical, 16)
                }

                // Suggested questions
                Text("试试这样问")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.folio.textTertiary)
                    .tracking(0.5)
                    .padding(.horizontal, Spacing.screenPadding)
                    .padding(.top, recentSearches.isEmpty ? 20 : 0)
                    .padding(.bottom, 16)

                ForEach(suggestedQuestions, id: \.self) { question in
                    Button {
                        searchText = question
                    } label: {
                        Text("\u{201C}\(question)\u{201D}")
                            .font(Font.custom("LXGWWenKaiTC-Regular", size: 15).italic())
                            .foregroundStyle(Color.folio.textSecondary)
                            .padding(.horizontal, Spacing.screenPadding)
                            .padding(.vertical, 10)
                    }
                }

                // Quick actions
                HStack(spacing: 12) {
                    quickActionCard(icon: "link", title: "粘贴链接") {
                        if let string = UIPasteboard.general.string,
                           let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
                           url.scheme?.hasPrefix("http") == true
                        {
                            searchText = string.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                    quickActionCard(icon: "square.and.pencil", title: "记一条笔记") {
                        noteSheetText = ""
                        showNoteSheet = true
                        isSearchActive = false
                    }
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, 24)
            }
        }
    }

    private func quickActionCard(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(Color.folio.textTertiary)
                Text(title)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.folio.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(Color.folio.echoBg)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Date Header

    private var dateHeader: some View {
        Text(formattedDate())
            .font(.system(size: 13))
            .foregroundStyle(Color.folio.textTertiary)
            .tracking(0.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.top, 4)
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
            dateHeader
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)

            if let milestone = activeMilestone {
                MilestoneCardView(
                    milestone: milestone,
                    articleCount: viewModel?.articles.count ?? 0,
                    onDismiss: { dismissMilestone(milestone) }
                )
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
            }

            if let vm = viewModel {
                ForEach(vm.feedSections, id: \.group) { section in
                    Section {
                        ForEach(section.items) { item in
                            switch item {
                            case .article(let article):
                                let isFirstUnreadToday = section.group == .today
                                    && section.items.first(where: { if case .article = $0 { return true } else { return false } })?.id == item.id
                                    && article.readProgress == 0 && article.status == .ready

                                if isFirstUnreadToday {
                                    HeroArticleCardView(article: article)
                                        .contentShape(Rectangle())
                                        .onTapGesture { selectArticle(article) }
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

                            case .echo(let echoDTO):
                                EchoCardView(
                                    card: EchoCardData(from: echoDTO),
                                    onReview: { result, completion in
                                        vm.submitEchoReview(cardID: echoDTO.id, result: result, completion: completion)
                                    }
                                )
                                .listRowInsets(EdgeInsets())
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
            await viewModel?.fetchEchoCards()
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

    private static let dateWeekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日，EEEE"
        return f
    }()

    private func formattedDate() -> String {
        Self.dateWeekdayFormatter.string(from: .now)
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
        // Empty text returns .error with empty message — just silently return
        if case .error(let msg) = result, msg.isEmpty { return }
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
