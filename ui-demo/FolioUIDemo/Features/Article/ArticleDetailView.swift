import SwiftUI

struct ArticleDetailView: View {
    let article: DemoArticle
    let onBack: () -> Void
    @State private var selectedIndex: Int
    @State private var presentedSheet: ArticleDetailSheet?
    @State private var askSession = ArticleAskSession()
    @State private var isReaderScrolling = false
    @State private var isMascotExpanded = false
    @State private var readerScrollTarget: String?
    @State private var pendingEvidenceJump = false
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
        ScrollViewReader { proxy in
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
            .onScrollPhaseChange(updateReaderScrollPhase)
            .onChange(of: readerScrollTarget) { _, target in
                scrollReader(to: target, using: proxy)
            }
        }
        .background(articleBackground)
        .toolbar(.hidden, for: .navigationBar)
        .simultaneousGesture(backSwipeGesture)
        .animation(.easeInOut(duration: reduceMotion ? 0 : 0.2), value: readerTheme)
        .overlay(alignment: .trailing) {
            if presentedSheet?.id == nil {
                ArticleAskMascotButton(
                    isExpanded: isMascotExpanded,
                    showsReturnState: showsReturnToAnswer,
                    action: showArticleAsk
                )
                .offset(y: 92)
            }
        }
        .task(id: mascotTaskID) {
            await updateMascotPresentation()
        }
        .sheet(item: $presentedSheet, onDismiss: handleSheetDismissed) { sheet in
            switch sheet {
            case .appearance:
                ReaderAppearanceSheet(
                    selectedFont: $readerFontChoice,
                    selectedTheme: $readerTheme
                )
            case .articleAsk:
                ArticleAskSheetView(
                    article: article,
                    session: askSession,
                    onOpenEvidence: showArticleAskEvidence
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
        isMascotExpanded = false
        presentedSheet = .evidence(
            DemoEvidence(
                quote: article.pullQuote,
                sourceTitle: article.title,
                sourceMetadata: "\(article.source) · \(article.age)"
            )
        )
    }

    private var backSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onEnded(handleBackSwipe)
    }

    private func handleBackSwipe(_ value: DragGesture.Value) {
        let horizontalTravel = value.translation.width
        let verticalTravel = abs(value.translation.height)
        let predictedHorizontalTravel = value.predictedEndTranslation.width

        guard value.startLocation.x <= 96,
              horizontalTravel > 44,
              horizontalTravel > verticalTravel * 1.4,
              predictedHorizontalTravel > 80 else {
            return
        }

        onBack()
    }

    private func showReaderAppearance() {
        isMascotExpanded = false
        presentedSheet = .appearance
    }

    private func showArticleAsk() {
        isMascotExpanded = false
        presentedSheet = .articleAsk
    }

    private func showArticleAskEvidence() {
        pendingEvidenceJump = true
        selectedIndex = ArticleReadingMode.original.rawValue
        presentedSheet = nil
    }

    private func showOriginal() {
        selectedIndex = ArticleReadingMode.original.rawValue
    }

    private func updateReaderScrollPhase(_: ScrollPhase, _ newPhase: ScrollPhase) {
        isReaderScrolling = newPhase != .idle
        if isReaderScrolling {
            withAnimation(FolioMotion.toolbarMorph(reduceMotion: reduceMotion)) {
                isMascotExpanded = false
            }
        }
    }

    private func updateMascotPresentation() async {
        guard !isReaderScrolling, presentedSheet?.id == nil else {
            withAnimation(FolioMotion.toolbarMorph(reduceMotion: reduceMotion)) {
                isMascotExpanded = false
            }
            return
        }

        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled, !isReaderScrolling, presentedSheet?.id == nil else { return }

        withAnimation(FolioMotion.toolbarMorph(reduceMotion: reduceMotion)) {
            isMascotExpanded = true
        }

        try? await Task.sleep(for: .milliseconds(2_600))
        guard !Task.isCancelled, !isReaderScrolling, presentedSheet?.id == nil else { return }

        withAnimation(FolioMotion.toolbarMorph(reduceMotion: reduceMotion)) {
            isMascotExpanded = false
        }
    }

    private func handleSheetDismissed() {
        if pendingEvidenceJump {
            pendingEvidenceJump = false
            readerScrollTarget = "reader-pull-quote"
        }
    }

    private func scrollReader(to target: String?, using proxy: ScrollViewProxy) {
        guard let target else { return }

        withAnimation(FolioMotion.pageSwitch(reduceMotion: reduceMotion)) {
            proxy.scrollTo(target, anchor: .center)
        }
        readerScrollTarget = nil
    }

    private var readerAppearanceDescription: String {
        "\(readerTheme.title)，\(readerFontChoice.title)"
    }

    private var articleBackground: Color {
        readerTheme.backgroundColor
    }

    private var showsReturnToAnswer: Bool {
        askSession.hasConversation && !askSession.isCompleted
    }

    private var mascotTaskID: String {
        [
            isReaderScrolling.description,
            presentedSheet?.id ?? "none",
            askSession.hasConversation.description,
            askSession.isCompleted.description
        ]
        .joined(separator: "-")
    }

}

#Preview {
    ArticleDetailView(article: DemoContent.primaryArticle, onBack: {})
}
