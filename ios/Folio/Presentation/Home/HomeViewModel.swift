import Foundation
import os
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

    var articles: [Article] = []
    var echoCards: [EchoCardDTO] = []

    var groupedArticles: [(group: TimeGroup, articles: [Article])] {
        TimeGroup.groupArticles(articles)
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
        var echoIdx = 0
        return groupedArticles.map { section in
            var items: [FeedItem] = []
            for (i, article) in section.articles.enumerated() {
                items.append(.article(article))
                if (i + 1) % 4 == 0, echoIdx < echoCards.count {
                    items.append(.echo(echoCards[echoIdx]))
                    echoIdx += 1
                }
            }
            return FeedSection(group: section.group, items: items)
        }
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

    private var currentPage = 0
    private let pageSize = 20
    private var hasMorePages = true

    init(context: ModelContext, isAuthenticated: Bool = false, apiClient: APIClient = .shared) {
        self.context = context
        self.isAuthenticated = isAuthenticated
        self.apiClient = apiClient
    }

    func fetchArticles() {
        currentPage = 0
        hasMorePages = true
        loadPage(reset: true)
    }

    func loadNextPage() {
        guard hasMorePages, !isLoading else { return }
        loadPage(reset: false)
    }

    func markAsRead(_ article: Article) {
        article.markAsRead(in: context)
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
        } catch {
            FolioLogger.sync.error("refreshFromServer failed: \(error)")
            syncError = error.localizedDescription
        }

        fetchArticles()
        isLoading = false
    }

    // MARK: - Echo

    func fetchEchoCards() async {
        guard isAuthenticated else { return }
        do {
            let response = try await apiClient.getEchoToday()
            echoCards = response.data
        } catch {
            // Silent failure — just don't show echo cards
            echoCards = []
        }
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
        article.toggleFavoriteWithSync(
            context: context, apiClient: apiClient,
            isAuthenticated: isAuthenticated, showToast: showToastMessage
        )
    }

    func archiveArticle(_ article: Article) {
        article.toggleArchiveWithSync(
            context: context, apiClient: apiClient,
            isAuthenticated: isAuthenticated, showToast: showToastMessage
        )
    }

    func deleteArticle(_ article: Article) {
        let serverID = article.serverID

        // Record deletion intent for server sync (before deleting the article)
        if let serverID {
            context.insert(PendingDeletion(serverID: serverID))
            // Anti-resurrection: remember this serverID was deleted
            let existing = try? context.fetch(FetchDescriptor<DeletionRecord>(
                predicate: #Predicate<DeletionRecord> { $0.serverID == serverID }
            ))
            if existing?.isEmpty ?? true {
                context.insert(DeletionRecord(serverID: serverID))
            }
        }

        context.delete(article)
        ModelContext.safeSave(context)
        fetchArticles()

        showToastMessage(String(localized: "home.article.deleted", defaultValue: "Article deleted"), icon: "trash")
    }

    // MARK: - Retry Failed Article

    func retryArticle(_ article: Article) {
        article.status = .pending
        article.fetchError = nil
        article.retryCount += 1
        article.updatedAt = .now
        ModelContext.safeSave(context)
        fetchArticles()

        showToastMessage(String(localized: "home.article.retrying", defaultValue: "Retrying..."), icon: "arrow.clockwise")

        if isAuthenticated {
            Task {
                do {
                    let response: SubmitArticleResponse
                    if article.sourceType == .manual {
                        guard let content = article.markdownContent, !content.isEmpty else {
                            article.status = .failed
                            article.fetchError = "No content to submit"
                            ModelContext.safeSave(context)
                            fetchArticles()
                            return
                        }
                        response = try await apiClient.submitManualContent(
                            content: content,
                            title: article.title,
                            clientId: article.id.uuidString
                        )
                    } else if article.extractionSource == .client {
                        response = try await apiClient.submitArticle(
                            url: article.url,
                            title: article.title,
                            author: article.author,
                            siteName: article.siteName,
                            markdownContent: article.markdownContent,
                            wordCount: article.wordCount > 0 ? article.wordCount : nil
                        )
                    } else {
                        response = try await apiClient.submitArticle(url: article.url)
                    }
                    article.serverID = response.articleId
                    article.status = .processing
                } catch {
                    FolioLogger.sync.error("retryArticle failed: \(error) — \(article.url ?? SourceType.manual.rawValue)")
                    article.status = .failed
                    article.fetchError = error.localizedDescription
                }
                ModelContext.safeSave(context)
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

    // MARK: - Private

    private func loadPage(reset: Bool) {
        isLoading = true

        // When tag filtering is active, we must over-fetch because SwiftData
        // #Predicate cannot filter on relationship collections. We keep
        // fetching batches until we fill a page or exhaust the data source.
        let needsTagFilter = !selectedTags.isEmpty
        let tagIDs = needsTagFilter ? Set(selectedTags.map(\.id)) : []
        var collected: [Article] = []
        var fetchOffset = currentPage * pageSize
        let batchSize = needsTagFilter ? pageSize * 3 : pageSize
        var exhausted = false

        repeat {
            var descriptor = FetchDescriptor<Article>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )

            // Apply category filter at predicate level for correct pagination
            if let categoryID = selectedCategory?.id {
                descriptor.predicate = #Predicate<Article> { article in
                    article.category?.id == categoryID
                }
            }

            descriptor.fetchLimit = batchSize
            descriptor.fetchOffset = fetchOffset

            guard let batch = try? context.fetch(descriptor) else {
                FolioLogger.data.error("vm-debug: loadPage fetch failed")
                isLoading = false
                return
            }

            if batch.count < batchSize {
                exhausted = true
            }
            fetchOffset += batch.count

            if needsTagFilter {
                let filtered = batch.filter { article in
                    tagIDs.isSubset(of: Set(article.tags.map(\.id)))
                }
                collected.append(contentsOf: filtered)
            } else {
                collected.append(contentsOf: batch)
            }
        } while needsTagFilter && collected.count < pageSize && !exhausted

        FolioLogger.data.info("vm-debug: loadPage reset=\(reset), collected=\(collected.count), offset=\(self.currentPage * self.pageSize)")

        if reset {
            articles = collected
        } else {
            articles.append(contentsOf: collected)
        }

        hasMorePages = !exhausted
        currentPage = fetchOffset / pageSize
        hasProcessingArticles = articles.contains { $0.status == .processing || $0.status == .clientReady }
        isLoading = false
    }

}
