import Foundation

extension DemoStore {
    var hasSearchQuery: Bool {
        !normalizedSearchQuery.isEmpty
    }

    var searchResults: [DemoSearchResult] {
        guard hasSearchQuery else { return [] }
        return articles.compactMap(bestSearchResult)
    }

    func toggleSearch() {
        isSearchPresented.toggle()
        if !isSearchPresented {
            searchQuery = ""
        }
    }

    func closeSearch() {
        isSearchPresented = false
        searchQuery = ""
    }

    private var normalizedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func bestSearchResult(for article: DemoArticle) -> DemoSearchResult? {
        let query = normalizedSearchQuery

        if let articleNote = articleNotes[article.id],
           articleNote.localizedStandardContains(query) {
            return makeSearchResult(
                article: article,
                scope: String(localized: .librarySearchScopeArticleNote),
                snippet: articleNote,
                suffix: "article-note"
            )
        }

        if let highlight = highlights(for: article.id).first(where: {
            $0.note.localizedStandardContains(query)
        }) {
            return makeSearchResult(
                article: article,
                scope: String(localized: .librarySearchScopeHighlightNote),
                snippet: highlight.note,
                paragraphIndex: highlight.paragraphIndex,
                suffix: "highlight-note-\(highlight.id)"
            )
        }

        if let highlight = highlights(for: article.id).first(where: {
            $0.quote.localizedStandardContains(query)
        }) {
            return makeSearchResult(
                article: article,
                scope: String(localized: .librarySearchScopeHighlight),
                snippet: highlight.quote,
                paragraphIndex: highlight.paragraphIndex,
                suffix: "highlight-\(highlight.id)"
            )
        }

        if article.title.localizedStandardContains(query) {
            return makeSearchResult(
                article: article,
                scope: String(localized: .librarySearchScopeTitle),
                snippet: article.title,
                suffix: "title"
            )
        }

        if let match = article.originalParagraphs.enumerated().first(where: {
            $0.element.localizedStandardContains(query)
        }) {
            return makeSearchResult(
                article: article,
                scope: String(localized: .librarySearchScopeBody),
                snippet: match.element,
                paragraphIndex: match.offset,
                suffix: "body-\(match.offset)"
            )
        }

        if article.source.localizedStandardContains(query) {
            return makeSearchResult(
                article: article,
                scope: String(localized: .librarySearchScopeSource),
                snippet: article.source,
                suffix: "source"
            )
        }

        return nil
    }

    private func makeSearchResult(
        article: DemoArticle,
        scope: String,
        snippet: String,
        paragraphIndex: Int? = nil,
        suffix: String
    ) -> DemoSearchResult {
        DemoSearchResult(
            id: "\(article.id)-\(suffix)",
            article: article,
            scope: scope,
            snippet: snippet,
            paragraphIndex: paragraphIndex
        )
    }
}
