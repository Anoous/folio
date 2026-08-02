import SwiftUI

struct ArticleDetailView: View {
    let article: DemoArticle
    let onBack: () -> Void
    @State private var selectedIndex: Int
    @State private var selectedEvidence: DemoEvidence?
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
        _selectedEvidence = State(
            initialValue: initiallyShowsEvidence
                ? DemoEvidence(
                    quote: article.pullQuote,
                    sourceTitle: article.title,
                    sourceMetadata: "\(article.source) · \(article.age)"
                )
                : nil
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ArticleDetailHeader(article: article, onBack: onBack)

                FolioSegmentedControl(
                    selectedIndex: $selectedIndex,
                    titles: ["洞察", "原文"]
                )
                .padding(.top, FolioMetrics.articleSwitcherTopSpacing)

                if selectedIndex == ArticleReadingMode.insight.rawValue {
                    InsightContentView(article: article, onShowEvidence: showEvidence)
                        .transition(insightTransition)
                } else {
                    ReaderContentView(article: article)
                        .transition(originalTransition)
                }
            }
            .padding(.horizontal, FolioMetrics.readingInset)
        }
        .scrollIndicators(.hidden)
        .background(FolioPalette.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .animation(FolioMotion.pageSwitch(reduceMotion: reduceMotion), value: selectedIndex)
        .sheet(item: $selectedEvidence) { evidence in
            EvidenceSheetView(evidence: evidence, onOpenOriginal: showOriginal)
        }
    }

    private func showEvidence() {
        selectedEvidence = DemoEvidence(
            quote: article.pullQuote,
            sourceTitle: article.title,
            sourceMetadata: "\(article.source) · \(article.age)"
        )
    }

    private func showOriginal() {
        selectedIndex = ArticleReadingMode.original.rawValue
    }

    private var insightTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: -12)),
            removal: .opacity.combined(with: .offset(x: -8))
        )
    }

    private var originalTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: 12)),
            removal: .opacity.combined(with: .offset(x: 8))
        )
    }
}

#Preview {
    ArticleDetailView(article: DemoContent.primaryArticle, onBack: {})
}
