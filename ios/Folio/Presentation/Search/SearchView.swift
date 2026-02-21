import SwiftUI
import SwiftData

struct SearchView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: SearchViewModel

    @FocusState private var isSearchFieldFocused: Bool

    init(searchManager: FTS5SearchManager? = nil) {
        // A temporary placeholder init; the real searchManager is injected via
        // the .onAppear / environment approach below.
        _viewModel = StateObject(wrappedValue: SearchViewModel._placeholder)
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Search Bar
            searchBar

            Divider()
                .foregroundStyle(Color.folio.separator)

            // MARK: - Content
            ZStack {
                if viewModel.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    // Default state: history + popular tags
                    SearchHistoryView(
                        history: viewModel.searchHistory,
                        popularTags: viewModel.popularTags,
                        onSelectQuery: { query in
                            viewModel.searchText = query
                            viewModel.saveToHistory(query)
                            viewModel.performSearch()
                        },
                        onDeleteItem: { query in
                            viewModel.deleteHistoryItem(query)
                        },
                        onClearAll: {
                            viewModel.clearHistory()
                        },
                        onSelectTag: { tag in
                            viewModel.searchText = tag.name
                            viewModel.saveToHistory(tag.name)
                            viewModel.performSearch()
                        }
                    )
                } else if viewModel.isSearching {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.showsEmptyState {
                    searchEmptyState
                } else {
                    searchResultsList
                }
            }
        }
        .navigationTitle(String(localized: "tab.search"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.loadPopularTags()
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.folio.textTertiary)

            TextField(
                String(localized: "search.placeholder", defaultValue: "搜索收藏内容..."),
                text: $viewModel.searchText
            )
            .font(Typography.body)
            .foregroundStyle(Color.folio.textPrimary)
            .focused($isSearchFieldFocused)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .submitLabel(.search)
            .onSubmit {
                let query = viewModel.searchText.trimmingCharacters(in: .whitespaces)
                if !query.isEmpty {
                    viewModel.saveToHistory(query)
                    viewModel.performSearch()
                }
            }

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                    viewModel.results = []
                    viewModel.showsEmptyState = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.folio.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(Color.folio.background)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.vertical, Spacing.xs)
    }

    // MARK: - Search Results List

    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.results) { item in
                    NavigationLink {
                        ReaderView(article: item.article)
                    } label: {
                        SearchResultRow(
                            item: item,
                            searchQuery: viewModel.searchText
                        )
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .padding(.leading, Spacing.screenPadding)
                }
            }
        }
    }

    // MARK: - Empty State

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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.screenPadding)
    }
}

// MARK: - Placeholder for Preview/Init

extension SearchViewModel {
    /// A placeholder instance used when the real dependencies are not yet
    /// available. The view should replace this once the environment provides
    /// the necessary context.
    @MainActor
    static var _placeholder: SearchViewModel {
        let manager = try! FTS5SearchManager(inMemory: true)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: Article.self, Tag.self, Category.self, configurations: config)
        return SearchViewModel(searchManager: manager, context: container.mainContext)
    }
}

#Preview {
    NavigationStack {
        SearchView()
    }
}
