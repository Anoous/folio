import SwiftUI

struct HomeSearchResultsView: View {
    let searchViewModel: SearchViewModel
    @Binding var searchText: String

    @State private var showAIAnswer = false
    @State private var emptyAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if searchViewModel.isSearching {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = searchViewModel.searchError {
            errorState(error: error)
        } else if searchViewModel.showsEmptyState {
            emptyState
        } else {
            resultsList
        }
    }

    // MARK: - Results List

    private var resultsList: some View {
        List {
            Section {
                ForEach(searchViewModel.results) { item in
                    NavigationLink(value: item.article.id) {
                        SearchResultRow(
                            item: item,
                            searchQuery: searchViewModel.searchText
                        )
                    }
                    .listRowInsets(EdgeInsets())
                }
            } header: {
                Text("\(searchViewModel.resultCount) " + (searchViewModel.resultCount == 1
                    ? String(localized: "search.result", defaultValue: "result")
                    : String(localized: "search.results", defaultValue: "results")))
                    .font(Typography.caption)
                    .foregroundStyle(Color.folio.textTertiary)
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Error State

    private func errorState(error: String) -> some View {
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
                searchViewModel.performSearch()
            }
            .frame(width: 160)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.screenPadding)
    }

    // MARK: - Empty State

    private var emptyState: some View {
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
                    withAnimation(Motion.resolved(Motion.settle, reduceMotion: reduceMotion)) { showAIAnswer = true }
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
        .opacity(emptyAppeared ? 1 : 0)
        .offset(y: emptyAppeared ? 0 : 12)
        .onAppear {
            withAnimation(Motion.resolved(Motion.settle, reduceMotion: reduceMotion) ?? .default) {
                emptyAppeared = true
            }
        }
        .onChange(of: searchText) { _, _ in
            showAIAnswer = false
            emptyAppeared = false
        }
    }
}
