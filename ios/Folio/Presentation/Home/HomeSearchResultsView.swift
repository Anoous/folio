import SwiftUI

struct HomeSearchResultsView: View {
    @Environment(\.selectArticle) private var selectArticle

    let searchViewModel: SearchViewModel
    @Binding var searchText: String
    var categoryFilter: String = ""

    /// URL detected in the search text (nil if not a URL)
    var detectedURL: URL?
    /// The article if this URL is already saved
    var existingArticle: Article?
    /// Called when user taps "Save this link"
    var onSaveURL: ((String) -> Void)?
    /// Called when user taps "Save as note"
    var onSaveNote: ((String) -> Void)?

    private var isTextInput: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && detectedURL == nil
            && searchText.count >= 2
    }

    var body: some View {
        if searchViewModel.isSearching && detectedURL == nil && !isTextInput {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = searchViewModel.searchError, detectedURL == nil {
            errorState(error: error)
        } else if detectedURL != nil {
            urlActionList
        } else if !filteredResults.isEmpty {
            // Has search results — show note action at top + results
            resultsWithNoteAction
        } else if searchViewModel.showsEmptyState || isTextInput {
            // No results — show note action prominently
            emptyWithNoteAction
        } else {
            resultsList
        }
    }

    // MARK: - Results With Note Action

    private var resultsWithNoteAction: some View {
        List {
            // Save as note — first row
            if isTextInput {
                noteActionRow
                    .listRowSeparator(.hidden)
            }

            resultsSection
        }
        .listStyle(.plain)
    }

    // MARK: - Empty With Note Action

    private var emptyWithNoteAction: some View {
        List {
            // Save as note — first and most prominent row
            if isTextInput {
                noteActionRow
                    .listRowSeparator(.hidden)
            }

            // No results hint
            Section {
                VStack(spacing: Spacing.sm) {
                    Text(String(localized: "search.noResults", defaultValue: "No matching articles"))
                        .font(Typography.cardMeta)
                        .foregroundStyle(Color.folio.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.lg)
            }
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
    }

    // MARK: - Note Action Row

    private var noteActionRow: some View {
        Button {
            onSaveNote?(searchText.trimmingCharacters(in: .whitespacesAndNewlines))
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "note.text.badge.plus")
                    .font(.body)
                    .foregroundStyle(Color.folio.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "search.saveAsNote", defaultValue: "Save as note"))
                        .font(Typography.body)
                        .foregroundStyle(Color.folio.textPrimary)
                    let trimmedPreview = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                    Text(trimmedPreview.prefix(60) + (trimmedPreview.count > 60 ? "..." : ""))
                        .font(Typography.cardMeta)
                        .foregroundStyle(Color.folio.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.vertical, Spacing.xs)
        }
        .buttonStyle(.plain)
    }

    // MARK: - URL Action List

    private var urlActionList: some View {
        List {
            Section {
                if let article = existingArticle {
                    Button { selectArticle(article) } label: {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(Color.folio.success)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(localized: "search.alreadySaved", defaultValue: "Already saved"))
                                    .font(Typography.body)
                                    .foregroundStyle(Color.folio.textPrimary)
                                Text(article.displayTitle)
                                    .font(Typography.caption)
                                    .foregroundStyle(Color.folio.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.vertical, Spacing.xs)
                    }
                    .buttonStyle(.plain)
                } else if let url = detectedURL {
                    Button {
                        onSaveURL?(url.absoluteString)
                    } label: {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(Color.folio.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(localized: "search.saveLink", defaultValue: "Save this link"))
                                    .font(Typography.body)
                                    .foregroundStyle(Color.folio.textPrimary)
                                Text(url.host() ?? url.absoluteString)
                                    .font(Typography.caption)
                                    .foregroundStyle(Color.folio.textSecondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.vertical, Spacing.xs)
                    }
                    .buttonStyle(.plain)
                }
            }

            if !filteredResults.isEmpty {
                resultsSection
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Results List

    private var filteredResults: [SearchViewModel.SearchResultItem] {
        if categoryFilter.isEmpty {
            return searchViewModel.results
        }
        return searchViewModel.results.filter { $0.article.category?.slug == categoryFilter }
    }

    private var resultsList: some View {
        List {
            resultsSection
        }
        .listStyle(.plain)
    }

    // MARK: - Shared Results Section

    @ViewBuilder
    private var resultsSection: some View {
        Section {
            ForEach(filteredResults) { item in
                Button { selectArticle(item.article) } label: {
                    SearchResultRow(
                        item: item,
                        searchQuery: searchViewModel.searchText
                    )
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets())
            }
        } header: {
            let count = filteredResults.count
            Text("\(count) " + (count == 1
                ? String(localized: "search.result", defaultValue: "result")
                : String(localized: "search.results", defaultValue: "results")))
                .font(Typography.caption)
                .foregroundStyle(Color.folio.textTertiary)
        }
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
}
