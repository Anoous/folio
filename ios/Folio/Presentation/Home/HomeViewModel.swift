import Foundation
import SwiftData
import SwiftUI

enum TimeGroup: String, CaseIterable {
    case today = "今天"
    case yesterday = "昨天"
    case thisWeek = "本周"
    case lastWeek = "上周"
    case earlier = "更早"

    static func group(dates: [Date], calendar: Calendar = .current, now: Date = .now) -> [(group: TimeGroup, indices: [Int])] {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday)!
        let weekday = calendar.component(.weekday, from: now)
        let daysSinceMonday = (weekday + 5) % 7
        let startOfThisWeek = calendar.date(byAdding: .day, value: -daysSinceMonday, to: startOfToday)!
        let startOfLastWeek = calendar.date(byAdding: .day, value: -7, to: startOfThisWeek)!

        var buckets: [TimeGroup: [Int]] = [:]

        for (i, date) in dates.enumerated() {
            let group: TimeGroup
            if date >= startOfToday {
                group = .today
            } else if date >= startOfYesterday {
                group = .yesterday
            } else if date >= startOfThisWeek {
                group = .thisWeek
            } else if date >= startOfLastWeek {
                group = .lastWeek
            } else {
                group = .earlier
            }
            buckets[group, default: []].append(i)
        }

        return TimeGroup.allCases.compactMap { g in
            guard let indices = buckets[g], !indices.isEmpty else { return nil }
            return (group: g, indices: indices)
        }
    }

    static func groupArticles(_ articles: [Article], calendar: Calendar = .current, now: Date = .now) -> [(group: TimeGroup, articles: [Article])] {
        let dated = group(dates: articles.map(\.createdAt), calendar: calendar, now: now)
        return dated.map { (group: $0.group, articles: $0.indices.map { articles[$0] }) }
    }
}

@MainActor
@Observable
final class HomeViewModel {
    private let context: ModelContext
    private let apiClient: APIClient
    private let searchIndexCoordinator: SearchIndexCoordinator
    private let feedQuery: ArticleFeedQuery
    private let articleActions: ArticleActionWorkflow
    private let knowledgeSession: KnowledgeSession

    var articles: [Article] = []
    var echoCards: [EchoCardDTO] = []
    var isEchoLoading = false
    var echoError: String?
    var echoRemainingToday: Int?
    var echoWeeklyCount: Int?
    var echoWeeklyLimit: Int?

    var groupedArticles: [(group: TimeGroup, articles: [Article])] {
        TimeGroup.groupArticles(articles)
    }

    var readyArticleCount: Int {
        articles.filter(\.isKnowledgeReady).count
    }

    var processingArticles: [Article] {
        articles.filter { article in
            switch article.status {
            case .pending, .processing, .clientReady, .failed:
                return true
            case .ready:
                return false
            }
        }
    }

    var continueReadingArticles: [Article] {
        let candidates = articles.filter { article in
            article.isKnowledgeReady && article.readProgress > 0 && article.readProgress < 0.98
        }

        return Array(
            candidates
                .sorted { left, right in
                    (left.lastReadAt ?? left.updatedAt) > (right.lastReadAt ?? right.updatedAt)
                }
                .prefix(2)
        )
    }

    var suggestedReadingArticles: [Article] {
        let candidates = articles.filter { article in
            article.isKnowledgeReady && !continueReadingArticles.contains(where: { $0.id == article.id })
        }
        return Array(candidates.prefix(2))
    }

    var workbenchMetrics: HomeWorkbenchMetrics {
        HomeWorkbenchMetrics(
            processingCount: processingArticles.count,
            continueReadingCount: continueReadingArticles.count,
            askableCount: readyArticleCount
        )
    }

    // MARK: - Feed Interleaving

    enum FeedItem: Identifiable {
        case article(Article)
        case echo(EchoCardDTO)

        var id: String {
            switch self {
            case .article(let a): return "article-\(a.id)"
            case .echo(let e): return "echo-\(e.id)"
            }
        }
    }

    struct FeedSection {
        let group: TimeGroup
        let items: [FeedItem]
    }

    var feedSections: [FeedSection] {
        groupedArticles.map { section in
            FeedSection(group: section.group, items: section.articles.map { .article($0) })
        }
    }

    /// Single echo card displayed between the first and second time-group sections.
    var intersectionEchoCard: EchoCardDTO? {
        echoCards.first
    }

    var selectedCategory: Folio.Category?
    var selectedTags: [Tag] = []
    var isLoading = false
    var isAuthenticated = false
    var syncError: String?
    var hasProcessingArticles = false
    var showToast = false
    var toastMessage = ""
    var toastIcon: String? = nil

    private static let pageSize = 20
    private var hasMorePages = true

    init(
        context: ModelContext,
        isAuthenticated: Bool = false,
        apiClient: APIClient = .shared,
        searchIndexCoordinator: SearchIndexCoordinator? = nil
    ) {
        self.context = context
        self.isAuthenticated = isAuthenticated
        self.apiClient = apiClient
        let resolvedSearchIndexCoordinator = searchIndexCoordinator ?? .shared
        self.searchIndexCoordinator = resolvedSearchIndexCoordinator
        self.feedQuery = ArticleFeedQuery(context: context, pageSize: Self.pageSize)
        self.articleActions = ArticleActionWorkflow(
            apiClient: apiClient,
            context: context,
            searchIndexCoordinator: resolvedSearchIndexCoordinator
        )
        self.knowledgeSession = KnowledgeSession(client: apiClient)
    }

    func fetchArticles() {
        hasMorePages = true
        loadPage(reset: true)
    }

    func loadNextPage() {
        guard hasMorePages, !isLoading else { return }
        loadPage(reset: false)
    }

    func markAsRead(_ article: Article) {
        articleActions.markAsRead(article)
    }

    // MARK: - Server Refresh

    func refreshFromServer() async {
        guard isAuthenticated else {
            fetchArticles()
            return
        }

        isLoading = true
        syncError = nil

        do {
            let response = try await apiClient.listArticles(page: 1, perPage: 50)
            let needsDetail = mergeServerArticles(response.data)
            await fetchMissingContent(needsDetail)
            searchIndexCoordinator.rebuild(context: context)
        } catch {
            FolioLogger.sync.error("refreshFromServer failed: \(error)")
            syncError = (error as? UserFacingError)?.userMessage ?? error.localizedDescription
        }

        fetchArticles()
        isLoading = false
    }

    // MARK: - Echo

    func fetchEchoCards() async {
        guard isAuthenticated else { return }
        isEchoLoading = true
        echoError = nil
        do {
            let response = try await apiClient.getEchoToday()
            echoCards = response.data
            echoRemainingToday = response.remainingToday
            echoWeeklyCount = response.weeklyCount
            echoWeeklyLimit = response.weeklyLimit
        } catch {
            echoCards = []
            echoError = (error as? UserFacingError)?.userMessage ?? error.localizedDescription
        }
        isEchoLoading = false
    }

    func submitEchoReview(cardID: String, result: String, completion: @escaping (EchoReviewResponse?) -> Void) {
        // Remove card from local list immediately (optimistic)
        echoCards.removeAll { $0.id == cardID }

        Task {
            do {
                let response = try await apiClient.submitEchoReview(cardID: cardID, result: result)
                await MainActor.run { completion(response) }
            } catch {
                await MainActor.run { completion(nil) }
            }
        }
    }

    // MARK: - Merge Server Articles

    /// Merges server DTOs into local store. Returns server IDs of articles
    /// that are ready on the server but missing local markdown content.
    @discardableResult
    private func mergeServerArticles(_ dtos: [ArticleDTO]) -> [String] {
        let merger = ArticleMerger(context: context)
        var needsDetail: [String] = []

        for dto in dtos {
            guard let article = (try? merger.merge(dto: dto)) ?? nil else { continue }

            // Article is ready on server but local content is missing
            if dto.status == ArticleStatus.ready.rawValue && article.markdownContent == nil {
                needsDetail.append(dto.id)
            }
        }

        ModelContext.safeSave(context)
        return needsDetail
    }

    // MARK: - Fetch Missing Content

    /// Fetches full article details for articles missing markdown content.
    private func fetchMissingContent(_ serverIDs: [String]) async {
        guard !serverIDs.isEmpty else { return }

        let articleRepo = ArticleRepository(context: context)
        let merger = ArticleMerger(context: context)

        for serverID in serverIDs {
            do {
                let dto = try await apiClient.getArticle(id: serverID)
                guard let article = try? articleRepo.fetchByServerID(serverID) else { continue }

                article.updateFromDTO(dto)
                try merger.resolveRelationships(for: article, from: dto)
            } catch {
                // Failed to fetch detail — will retry on next refresh
                continue
            }
        }

        ModelContext.safeSave(context)
    }

    // MARK: - Article Actions

    func toggleFavorite(_ article: Article) {
        articleActions.toggleFavorite(article, isAuthenticated: isAuthenticated, showToast: showToastMessage)
    }

    func archiveArticle(_ article: Article) {
        articleActions.toggleArchive(article, isAuthenticated: isAuthenticated, showToast: showToastMessage)
    }

    func deleteArticle(_ article: Article) {
        articleActions.delete(article)
        fetchArticles()
        showToastMessage(String(localized: "home.article.deleted", defaultValue: "Article deleted"), icon: "trash")
    }

    // MARK: - Retry Failed Article

    func retryArticle(_ article: Article) {
        let workflow = ArticleSyncWorkflow(apiClient: apiClient, context: context)
        workflow.prepareForRetry(article)
        fetchArticles()

        showToastMessage(String(localized: "home.article.retrying", defaultValue: "Retrying..."), icon: "arrow.clockwise")

        if isAuthenticated {
            Task {
                await workflow.submitRetry(article)
                fetchArticles()
            }
        }
    }

    // MARK: - Dismiss Sync Error

    func dismissSyncError() {
        syncError = nil
    }

    // MARK: - Toast

    private func showToastMessage(_ message: String, icon: String? = nil) {
        toastMessage = message
        toastIcon = icon
        showToast = true
    }

    // MARK: - Knowledge Session

    var activeKnowledgePanel: KnowledgePanelKind? {
        knowledgeSession.activeKnowledgePanel
    }

    var isKnowledgeLoading: Bool {
        knowledgeSession.isKnowledgeLoading
    }

    var sparkInsights: [SparkInsightDTO] {
        knowledgeSession.sparkInsights
    }

    var learnSummary: String? {
        knowledgeSession.learnSummary
    }

    var learnItems: [LearnItemDTO] {
        knowledgeSession.learnItems
    }

    var knowledgeError: String? {
        knowledgeSession.knowledgeError
    }

    var ragPartialAnswer: String {
        knowledgeSession.ragPartialAnswer
    }

    var ragIsStreaming: Bool {
        knowledgeSession.ragIsStreaming
    }

    var ragSources: RAGSourcesPayload? {
        knowledgeSession.ragSources
    }

    var ragCitedIndices: [Int] {
        knowledgeSession.ragCitedIndices
    }

    var ragFollowupSuggestions: [String] {
        knowledgeSession.ragFollowupSuggestions
    }

    var ragError: RAGErrorView.ErrorType? {
        knowledgeSession.ragError
    }

    var ragConversationId: String? {
        knowledgeSession.ragConversationId
    }

    var ragThread: [RAGThreadEntry] {
        knowledgeSession.ragThread
    }

    var ragStreamTask: Task<Void, Never>? {
        knowledgeSession.ragStreamTask
    }

    func isRAGQuery(_ text: String) -> Bool {
        knowledgeSession.isRAGQuery(text)
    }

    func submitRAGQuery(_ question: String) {
        knowledgeSession.submitRAGQuery(question)
    }

    func submitFollowup(_ question: String) {
        knowledgeSession.submitFollowup(question)
    }

    func clearRAG() {
        knowledgeSession.clearRAG()
    }

    func loadSpark(prompt: String = "") async {
        await knowledgeSession.loadSpark(prompt: prompt)
    }

    func loadLearn(prompt: String = "") async {
        await knowledgeSession.loadLearn(prompt: prompt)
    }

    func clearKnowledge() {
        knowledgeSession.clearKnowledge()
    }

    // MARK: - Private

    private func loadPage(reset: Bool) {
        isLoading = true

        let page: ArticleFeedQuery.Page
        do {
            if reset {
                page = try feedQuery.reset(filter: .init(category: selectedCategory, tags: selectedTags))
            } else {
                page = try feedQuery.next()
            }
        } catch {
            FolioLogger.data.error("home feed load failed: \(error)")
            isLoading = false
            return
        }

        if reset {
            withAnimation(Motion.settle) {
                articles = page.articles
            }
        } else {
            withAnimation(Motion.ink) {
                articles.append(contentsOf: page.articles)
            }
        }

        hasMorePages = page.hasMore
        hasProcessingArticles = articles.contains { $0.status == .processing || $0.status == .clientReady }
        isLoading = false
    }

}
