import SwiftUI

struct HomeSearchView: View {
    @Binding var searchText: String
    var viewModel: HomeViewModel
    var searchViewModel: SearchViewModel?
    var recentSearches: [String]
    var onDismiss: () -> Void
    var onSaveURL: (String) -> Void
    var onSaveNote: (String) -> Void
    var onShowNoteSheet: () -> Void
    var onSaveRecentSearch: (String) -> Void
    var findExistingArticle: (String) -> Article?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.selectArticle) private var selectArticle

    var body: some View {
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
                            if !trimmed.isEmpty { onSaveRecentSearch(trimmed) }
                            handleSearchTextChange(searchText)
                        }
                        .onChange(of: searchText) { _, newValue in
                            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                            if viewModel.isRAGQuery(trimmed) {
                                onSaveRecentSearch(trimmed)
                                viewModel.submitRAGQuery(trimmed)
                                // Clear FTS state when switching to RAG
                                searchViewModel?.searchText = ""
                            } else {
                                viewModel.clearRAG()
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
                    viewModel.clearRAG()
                    onDismiss()
                }
                .font(.system(size: 16))
                .foregroundStyle(Color.folio.accent)
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.vertical, 10)

            // Search results — RAG and FTS are mutually exclusive
            let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                if viewModel.isRAGQuery(trimmed) {
                    // RAG mode
                    if viewModel.ragIsLoading {
                        RAGLoadingView()
                    } else if let error = viewModel.ragError {
                        RAGErrorView(errorType: error, onRetry: { viewModel.submitRAGQuery(trimmed) })
                    } else if let response = viewModel.ragResponse {
                        ScrollView {
                            RAGAnswerView(
                                thread: viewModel.ragThread,
                                response: response,
                                onSourceTap: { articleId in
                                    let repo = ArticleRepository(context: modelContext)
                                    if let article = try? repo.fetchByServerID(articleId) {
                                        selectArticle(article)
                                    }
                                },
                                onFollowup: { question in
                                    viewModel.submitFollowup(question)
                                }
                            )
                        }
                        .scrollDismissesKeyboard(.interactively)
                    } else {
                        Spacer() // RAG not yet triggered
                    }
                } else if let svm = searchViewModel {
                    // FTS mode (existing search results)
                    HomeSearchResultsView(
                        searchViewModel: svm,
                        searchText: $searchText,
                        detectedURL: URLDetection.extractURL(from: trimmed),
                        existingArticle: findExistingArticle(trimmed),
                        onSaveURL: { url in onSaveURL(url) },
                        onSaveNote: { content in onSaveNote(content) }
                    )
                }
            } else {
                SearchSuggestionsView(
                    searchText: $searchText,
                    recentSearches: recentSearches,
                    onShowNoteSheet: onShowNoteSheet
                )
            }
        }
    }

    private func handleSearchTextChange(_ newValue: String) {
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            viewModel.fetchArticles()
        } else {
            searchViewModel?.searchText = trimmed
        }
    }
}
