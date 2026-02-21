import Foundation
import SwiftData
import SwiftUI
import Combine

@MainActor
final class SearchViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var searchText: String = ""
    @Published var results: [SearchResultItem] = []
    @Published var isSearching: Bool = false
    @Published var showsEmptyState: Bool = false
    @Published var popularTags: [Tag] = []
    @Published var searchHistory: [String] = []

    // MARK: - Dependencies

    private let searchManager: FTS5SearchManager
    private let articleRepository: ArticleRepository
    private let tagRepository: TagRepository
    private var cancellables = Set<AnyCancellable>()

    private static let historyKey = "folio_search_history"
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
    }

    // MARK: - Debounce Setup

    private func setupDebounce() {
        $searchText
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] query in
                guard let self else { return }
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    self.results = []
                    self.showsEmptyState = false
                    self.isSearching = false
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
            results = []
            showsEmptyState = false
            isSearching = false
            return
        }

        isSearching = true
        showsEmptyState = false

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

            results = items
            showsEmptyState = items.isEmpty
        } catch {
            results = []
            showsEmptyState = true
        }

        isSearching = false
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

    func deleteHistoryItem(_ query: String) {
        searchHistory.removeAll { $0 == query }
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
}
