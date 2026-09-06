import Foundation
import Observation
import SwiftData
import Combine

@MainActor
@Observable
final class SearchViewModel {
    // MARK: - Properties

    var searchText: String = "" {
        didSet { searchTextSubject.send(searchText) }
    }
    var results: [SearchResultItem] = []
    var isSearching: Bool = false
    var showsEmptyState: Bool = false
    var searchError: String?
    var resultCount: Int = 0
    var popularTags: [Tag] = []
    var searchHistory: [String] = []
    var syncedArticleCount: Int = 0
    var state: ViewState<[SearchResultItem]> = .idle

    // MARK: - Dependencies

    private let searchManager: FTS5SearchManager
    private let articleRepository: ArticleRepository
    private let tagRepository: TagRepository
    private let searchTextSubject = PassthroughSubject<String, Never>()
    private var cancellables = Set<AnyCancellable>()

    nonisolated static let historyKey = AppConstants.searchHistoryKey
    private static let maxHistoryCount = 10

    // MARK: - Search Result Item

    struct SearchResultItem: Identifiable {
        let id: UUID
        let article: Article
        let rank: Double
        var highlightedTitle: String?
        var snippet: String?
    }

    // MARK: - Initialization

    init(searchManager: FTS5SearchManager, context: ModelContext) {
        self.searchManager = searchManager
        self.articleRepository = ArticleRepository(context: context)
        self.tagRepository = TagRepository(context: context)

        loadSearchHistory()
        setupDebounce()
        rebuildIndex()
    }

    // MARK: - Index Management

    /// Rebuild FTS5 index from all local articles.
    func rebuildIndex() {
        do {
            let allArticles = try articleRepository.fetchAllForIndex()
            try searchManager.rebuildAll(articles: allArticles)
            FolioLogger.data.info("search index rebuilt: \(allArticles.count) articles")
        } catch {
            FolioLogger.data.error("search index rebuild failed: \(error)")
        }
    }

    // MARK: - Debounce Setup

    private func setupDebounce() {
        searchTextSubject
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] query in
                guard let self else { return }
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    self.applyState(.idle)
                } else {
                    self.performSearch()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Search

    func performSearch() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            applyState(.idle)
            return
        }

        applyState(.loading)

        do {
            let searchResults = try searchManager.searchWithSnippet(query: query, limit: 20)

            var items: [SearchResultItem] = []
            for result in searchResults {
                if let article = try articleRepository.fetchByID(result.articleID) {
                    items.append(SearchResultItem(
                        id: result.articleID,
                        article: article,
                        rank: result.rank,
                        highlightedTitle: result.highlightedTitle,
                        snippet: result.snippet
                    ))
                }
            }

            applyState(items.isEmpty ? .empty : .loaded(items))
        } catch {
            FolioLogger.data.error("search failed: \(error)")
            let message = (error as? UserFacingError)?.userMessage ?? error.localizedDescription
            applyState(.error(message))
        }
    }

    private func applyState(_ newState: ViewState<[SearchResultItem]>) {
        state = newState

        switch newState {
        case .idle:
            results = []
            resultCount = 0
            isSearching = false
            showsEmptyState = false
            searchError = nil
        case .loading:
            results = []
            resultCount = 0
            isSearching = true
            showsEmptyState = false
            searchError = nil
        case .loaded(let items):
            results = items
            resultCount = items.count
            isSearching = false
            showsEmptyState = false
            searchError = nil
        case .empty:
            results = []
            resultCount = 0
            isSearching = false
            showsEmptyState = true
            searchError = nil
        case .error(let message):
            results = []
            resultCount = 0
            isSearching = false
            showsEmptyState = false
            searchError = message
        }
    }

    // MARK: - Search History

    func saveToHistory(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        var history = searchHistory
        history.removeAll { $0 == trimmed }
        history.insert(trimmed, at: 0)

        if history.count > Self.maxHistoryCount {
            history = Array(history.prefix(Self.maxHistoryCount))
        }

        searchHistory = history
        persistHistory()
    }

    func clearHistory() {
        searchHistory = []
        persistHistory()
    }

    private func loadSearchHistory() {
        guard let data = UserDefaults.standard.data(forKey: Self.historyKey),
              let history = try? JSONDecoder().decode([String].self, from: data) else {
            searchHistory = []
            return
        }
        searchHistory = history
    }

    private func persistHistory() {
        if let data = try? JSONEncoder().encode(searchHistory) {
            UserDefaults.standard.set(data, forKey: Self.historyKey)
        }
    }

    // MARK: - Popular Tags

    func loadPopularTags() {
        do {
            popularTags = try tagRepository.fetchPopular(limit: 8)
        } catch {
            popularTags = []
        }
    }

    // MARK: - Synced Article Count

    func refreshSyncedCount(context: ModelContext) {
        let readyRaw = ArticleStatus.ready.rawValue
        let clientReadyRaw = ArticleStatus.clientReady.rawValue
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                article.statusRaw == readyRaw || article.statusRaw == clientReadyRaw
            }
        )
        syncedArticleCount = (try? context.fetchCount(descriptor)) ?? 0
    }
}
