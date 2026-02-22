import SwiftUI
import SwiftData

struct SearchView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: SearchViewModel?

    var body: some View {
        Group {
            if let viewModel {
                SearchContentView(viewModel: viewModel)
            } else {
                VStack(spacing: Spacing.md) {
                    ProgressView()
                    Text(String(localized: "search.indexing", defaultValue: "Preparing search..."))
                        .font(Typography.caption)
                        .foregroundStyle(Color.folio.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(String(localized: "tab.search"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if viewModel == nil {
                guard let manager = try? FTS5SearchManager(inMemory: true) else { return }
                let vm = SearchViewModel(searchManager: manager, context: modelContext)
                viewModel = vm
                vm.loadPopularTags()
            }
        }
    }
}

// MARK: - Search Content

private struct SearchContentView: View {
    @ObservedObject var viewModel: SearchViewModel

    @FocusState private var isSearchFieldFocused: Bool

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
                } else if let error = viewModel.searchError {
                    searchErrorState(error: error)
                } else if viewModel.showsEmptyState {
                    searchEmptyState
                } else {
                    searchResultsList
                }
            }
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
                // Result count header
                HStack {
                    Text("\(viewModel.resultCount) " + String(localized: "search.results", defaultValue: "results"))
                        .font(Typography.caption)
                        .foregroundStyle(Color.folio.textTertiary)
                    Spacer()
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.vertical, Spacing.xs)

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

    // MARK: - Error State

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
                viewModel.performSearch()
            }
            .frame(width: 160)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.screenPadding)
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

#Preview {
    NavigationStack {
        SearchView()
            .modelContainer(try! ModelContainer(
                for: Article.self, Tag.self, Category.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            ))
    }
}
