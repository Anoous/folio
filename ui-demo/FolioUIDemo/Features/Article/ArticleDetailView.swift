import SwiftUI

struct ArticleDetailView: View {
    let article: DemoArticle
    let onBack: () -> Void
    @State private var selectedIndex: Int
    @State private var presentedSheet: ArticleDetailSheet?
    @AppStorage("readerFontChoice") private var readerFontChoice = ReaderFontChoice.notoSerif
    @AppStorage("readerTheme") private var readerTheme = ReaderTheme.paper
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        article: DemoArticle,
        onBack: @escaping () -> Void,
        initialMode: ArticleReadingMode = .original,
        initiallyShowsEvidence: Bool = false
    ) {
        self.article = article
        self.onBack = onBack
        _selectedIndex = State(initialValue: initialMode.rawValue)
        _presentedSheet = State(
            initialValue: initiallyShowsEvidence
                ? .evidence(
                    DemoEvidence(
                        quote: article.pullQuote,
                        sourceTitle: article.title,
                        sourceMetadata: "\(article.source) · \(article.age)"
                    )
                )
                : nil
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ArticleDetailHeader(
                    article: article,
                    onBack: onBack,
                    onOpenReaderAppearance: showReaderAppearance,
                    readerAppearanceDescription: readerAppearanceDescription
                )

                FolioSegmentedControl(
                    selectedIndex: $selectedIndex,
                    titles: ["原文", "洞察"]
                )
                .padding(.top, FolioMetrics.articleSwitcherTopSpacing)

                ZStack(alignment: .topLeading) {
                    if selectedIndex == ArticleReadingMode.insight.rawValue {
                        InsightContentView(
                            article: article,
                            fontChoice: readerFontChoice,
                            theme: readerTheme,
                            onShowEvidence: showEvidence
                        )
                            .transition(.opacity)
                    } else {
                        ReaderContentView(
                            article: article,
                            fontChoice: readerFontChoice,
                            theme: readerTheme
                        )
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .animation(FolioMotion.articleContentSwitch(reduceMotion: reduceMotion), value: selectedIndex)
            }
            .padding(.horizontal, FolioMetrics.readingInset)
        }
        .scrollIndicators(.hidden)
        .background(articleBackground)
        .toolbar(.hidden, for: .navigationBar)
        .animation(.easeInOut(duration: reduceMotion ? 0 : 0.2), value: readerTheme)
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .appearance:
                ReaderAppearanceSheet(
                    selectedFont: $readerFontChoice,
                    selectedTheme: $readerTheme
                )
            case .evidence(let evidence):
                EvidenceSheetView(
                    evidence: evidence,
                    fontChoice: readerFontChoice,
                    theme: readerTheme,
                    onOpenOriginal: showOriginal
                )
            }
        }
    }

    private func showEvidence() {
        presentedSheet = .evidence(
            DemoEvidence(
                quote: article.pullQuote,
                sourceTitle: article.title,
                sourceMetadata: "\(article.source) · \(article.age)"
            )
        )
    }

    private func showReaderAppearance() {
        presentedSheet = .appearance
    }

    private func showOriginal() {
        selectedIndex = ArticleReadingMode.original.rawValue
    }

    private var readerAppearanceDescription: String {
        "\(readerTheme.title)，\(readerFontChoice.title)"
    }

    private var articleBackground: Color {
        readerTheme.backgroundColor
    }

}

#Preview {
    ArticleDetailView(article: DemoContent.primaryArticle, onBack: {})
}
