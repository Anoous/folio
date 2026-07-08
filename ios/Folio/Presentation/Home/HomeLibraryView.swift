import SwiftUI

struct HomeLibraryView: View {
    var viewModel: HomeViewModel
    var searchViewModel: SearchViewModel?
    @Binding var searchText: String
    let focusRequest: HomeTabFocusRequest?
    let onSaveURL: (String) -> Void
    let onSaveNote: (String) -> Void
    let findExistingArticle: (String) -> Article?
    let onArticleAction: (ArticleRowAction, Article) -> Void

    @FocusState private var isSearchFocused: Bool

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar

            if trimmedSearchText.isEmpty {
                articleLibrary
            } else if let searchViewModel {
                HomeSearchResultsView(
                    searchViewModel: searchViewModel,
                    searchText: $searchText,
                    detectedURL: URLDetection.extractURL(from: trimmedSearchText),
                    existingArticle: findExistingArticle(trimmedSearchText),
                    onSaveURL: onSaveURL,
                    onSaveNote: onSaveNote
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(FolioPaperPalette.background)
        .onAppear {
            updateSearch(trimmedSearchText)
            applyFocusRequest(focusRequest)
        }
        .onChange(of: searchText) { _, newValue in
            updateSearch(newValue)
        }
        .onChange(of: focusRequest?.id) { _, _ in
            applyFocusRequest(focusRequest)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundStyle(FolioPaperPalette.tertiaryText)

            TextField(
                "",
                text: $searchText,
                prompt: Text("搜索资料库").foregroundStyle(FolioPaperPalette.tertiaryText)
            )
                .font(.system(size: 16))
                .foregroundStyle(FolioPaperPalette.primaryText)
                .tint(FolioPaperPalette.accentBlue)
                .focused($isSearchFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(FolioPaperPalette.tertiaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(FolioPaperPalette.searchField)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(FolioPaperPalette.listDivider.opacity(0.7), lineWidth: 1)
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.bottom, 10)
    }

    private var articleLibrary: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                if viewModel.articles.isEmpty {
                    EmptyStateView(onPasteURL: { url in
                        onSaveURL(url.absoluteString)
                    })
                } else {
                    HomeSectionHeaderView(
                        title: "全部资料",
                        subtitle: "\(viewModel.articles.count) 篇收藏"
                    )

                    ForEach(Array(viewModel.feedSections.enumerated()), id: \.element.group) { _, section in
                        HomeSectionHeaderView(title: section.group.rawValue, subtitle: nil)
                            .padding(.top, Spacing.sm)

                        ForEach(section.items) { item in
                            switch item {
                            case .article(let article):
                                HomeArticleRow(
                                    article: article,
                                    articleCount: viewModel.articles.count,
                                    articleIndex: viewModel.articles.firstIndex(where: { $0.id == article.id })
                                ) { action in
                                    onArticleAction(action, article)
                                }
                                .padding(.horizontal, Spacing.screenPadding)
                                .padding(.vertical, 5)
                                .overlay(alignment: .bottom) {
                                    Rectangle()
                                        .fill(FolioPaperPalette.listDivider.opacity(0.55))
                                        .frame(height: 0.5)
                                        .padding(.leading, Spacing.screenPadding + 30)
                                        .padding(.trailing, Spacing.screenPadding)
                                }

                            case .echo:
                                EmptyView()
                            }
                        }
                    }
                }
            }
        }
        .contentMargins(.bottom, 124, for: .scrollContent)
    }

    private func updateSearch(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        searchViewModel?.searchText = trimmed
    }

    private func applyFocusRequest(_ request: HomeTabFocusRequest?) {
        guard request?.target == .librarySearch else { return }
        isSearchFocused = true
    }
}
