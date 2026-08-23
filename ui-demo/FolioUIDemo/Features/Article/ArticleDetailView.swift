import SwiftUI

struct ArticleDetailView: View {
    @Bindable var store: DemoStore
    let article: DemoArticle
    let onBack: () -> Void
    @State private var selectedIndex: Int
    @State private var presentedSheet: ArticleDetailSheet?
    @State private var askSession = ArticleAskSession()
    @State private var isAskComposerVisible = true
    @State private var backSwipeOffset: CGFloat = 0
    @State private var readerWidth: CGFloat = 390
    @State private var readerScrollTarget: String?
    @FocusState private var isArticleAskFocused: Bool
    @AppStorage("readerFontChoice") private var readerFontChoice = ReaderFontChoice.notoSerif
    @AppStorage("readerTheme") private var readerTheme = ReaderTheme.paper
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        store: DemoStore,
        article: DemoArticle,
        onBack: @escaping () -> Void,
        initialMode: ArticleReadingMode = .original,
        initiallyShowsEvidence: Bool = false,
        initialParagraphIndex: Int? = nil
    ) {
        self.store = store
        self.article = article
        self.onBack = onBack
        _selectedIndex = State(initialValue: initialMode.rawValue)
        _readerScrollTarget = State(
            initialValue: initialParagraphIndex.map { "reader-paragraph-\($0)" }
        )
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
                        article: article
                    )

                    FolioSegmentedControl(
                        selectedIndex: $selectedIndex,
                        titles: ["原文", "洞察"]
                    )
                    .padding(.top, FolioMetrics.articleSwitcherTopSpacing)

                    if let question = askSession.submittedQuestion,
                       let answer = askSession.answer {
                        ArticleAskInlineAnswer(
                            articleTitle: article.title,
                            question: question,
                            answer: answer,
                            onOpenEvidence: showEvidence,
                            onDismiss: dismissArticleAnswer
                        )
                        .padding(.top, 24)
                        .id("article-ask-inline-answer")
                        .transition(articleAnswerTransition)
                    }

                    ZStack(alignment: .topLeading) {
                        if selectedIndex == ArticleReadingMode.insight.rawValue {
                            InsightContentView(
                                article: article,
                                fontChoice: readerFontChoice,
                                theme: readerTheme,
                                onShowEvidence: showEvidence
                            )
                                .transition(articleContentTransition)
                        } else {
                            ReaderContentView(
                                article: article,
                                fontChoice: readerFontChoice,
                                theme: readerTheme,
                                highlights: store.highlights(for: article.id),
                                onHighlight: addHighlight,
                                onAddNote: addNote
                            )
                                .transition(articleContentTransition)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .animation(FolioMotion.articleContentSwitch(reduceMotion: reduceMotion), value: selectedIndex)
                }
                .padding(.horizontal, FolioMetrics.readingInset)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: readerScrollTarget) { _, target in
                scrollReader(to: target, using: proxy)
            }
            .task {
                scrollReader(to: readerScrollTarget, using: proxy)
            }
        }
        .background(articleBackground)
        .toolbar(.hidden, for: .navigationBar)
        .animation(.easeInOut(duration: reduceMotion ? 0 : 0.2), value: readerTheme)
        .overlay(alignment: .top) {
            ZStack(alignment: .top) {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 1)
                    .background(articleBackground, ignoresSafeAreaEdges: .top)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                LinearGradient(
                    stops: [
                        .init(color: articleBackground, location: 0),
                        .init(color: articleBackground.opacity(0.96), location: 0.72),
                        .init(color: articleBackground.opacity(0), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 76)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

                ArticleDetailTopBar(
                    onBack: onBack,
                    onOpenAnnotations: showAnnotations,
                    onOpenReaderAppearance: showReaderAppearance,
                    readerAppearanceDescription: readerAppearanceDescription
                )
            }
        }
        .overlay(alignment: .bottom) {
            if presentedSheet == nil {
                ArticleAskComposer(
                    text: $askSession.draft,
                    isFocused: $isArticleAskFocused,
                    canSubmit: askSession.canSubmit,
                    onAddContext: referenceCurrentArticle,
                    onVoicePrompt: useVoiceDemoPrompt,
                    onSubmit: submitArticleQuestion
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .offset(y: isAskComposerVisible || reduceMotion ? 0 : 96)
                .opacity(isAskComposerVisible ? 1 : 0)
                .allowsHitTesting(isAskComposerVisible)
                .accessibilityHidden(!isAskComposerVisible)
            }
        }
        .animation(
            FolioMotion.chromeVisibility(reduceMotion: reduceMotion),
            value: isAskComposerVisible
        )
        .offset(x: backSwipeOffset)
        .shadow(
            color: .black.opacity(backSwipeOffset > 0 ? 0.1 : 0),
            radius: 18,
            x: -8
        )
        .background(alignment: .leading) {
            ZStack(alignment: .leading) {
                FolioPalette.canvas

                Label("资料库", systemImage: "chevron.left")
                    .font(.subheadline.bold())
                    .foregroundStyle(FolioPalette.inkGreenDeep)
                    .padding(.leading, 18)
                    .opacity(min(backSwipeProgress * 2, 1))
                    .offset(x: -8 + 8 * backSwipeProgress)
            }
            .accessibilityHidden(true)
        }
        .contentShape(.rect)
        .simultaneousGesture(backSwipeGesture)
        .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.width
        } action: { width in
            readerWidth = width
        }
        .onChange(of: isArticleAskFocused) { _, isFocused in
            if isFocused {
                revealAskComposer()
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .appearance:
                ReaderAppearanceSheet(
                    selectedFont: $readerFontChoice,
                    selectedTheme: $readerTheme
                )
            case .annotations(let focusedHighlightID):
                ArticleAnnotationsSheet(
                    store: store,
                    article: article,
                    focusedHighlightID: focusedHighlightID
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

    private var backSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onChanged(updateBackSwipe)
            .onEnded(completeBackSwipe)
    }

    private func updateBackSwipe(_ value: DragGesture.Value) {
        let horizontalTravel = value.translation.width
        let verticalTravel = abs(value.translation.height)

        if verticalTravel > abs(horizontalTravel),
           !isArticleAskFocused,
           presentedSheet == nil {
            if value.translation.height < -18, isAskComposerVisible {
                isAskComposerVisible = false
            } else if value.translation.height > 7, !isAskComposerVisible {
                revealAskComposer()
            }
            return
        }

        guard value.startLocation.x <= 96,
              horizontalTravel > 0,
              horizontalTravel > verticalTravel else {
            return
        }

        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            backSwipeOffset = min(horizontalTravel, readerWidth)
        }
    }

    private func completeBackSwipe(_ value: DragGesture.Value) {
        guard backSwipeOffset > 0 else { return }

        let predictedTravel = value.predictedEndTranslation.width
        let shouldReturn = backSwipeOffset > readerWidth * 0.28
            || predictedTravel > readerWidth * 0.5

        guard shouldReturn else {
            withAnimation(FolioMotion.backSwipeCancellation(reduceMotion: reduceMotion)) {
                backSwipeOffset = 0
            }
            return
        }

        withAnimation(
            FolioMotion.backSwipeCompletion(reduceMotion: reduceMotion),
            completionCriteria: .logicallyComplete
        ) {
            backSwipeOffset = readerWidth
        } completion: {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                onBack()
            }
            backSwipeOffset = 0
        }
    }

    private func showReaderAppearance() {
        presentedSheet = .appearance
    }

    private func showAnnotations() {
        presentedSheet = .annotations(focusedHighlightID: nil)
    }

    private func addHighlight(_ selection: DemoTextSelection) {
        _ = store.addHighlight(to: article, selection: selection)
    }

    private func addNote(_ selection: DemoTextSelection) {
        guard let highlight = store.addHighlight(to: article, selection: selection) else { return }
        presentedSheet = .annotations(focusedHighlightID: highlight.id)
    }

    private func referenceCurrentArticle() {
        askSession.referenceArticle(article.title)
        isArticleAskFocused = true
        revealAskComposer()
    }

    private func useVoiceDemoPrompt() {
        askSession.useVoiceDemoPrompt()
        isArticleAskFocused = true
        revealAskComposer()
    }

    private func submitArticleQuestion() {
        guard askSession.canSubmit else { return }
        withAnimation(FolioMotion.articleContentSwitch(reduceMotion: reduceMotion)) {
            askSession.submit()
        }
        isArticleAskFocused = false
        revealAskComposer()
        readerScrollTarget = "article-ask-inline-answer"
    }

    private func dismissArticleAnswer() {
        withAnimation(FolioMotion.articleContentSwitch(reduceMotion: reduceMotion)) {
            askSession.clearConversation()
        }
        revealAskComposer()
    }

    private func showOriginal() {
        selectedIndex = ArticleReadingMode.original.rawValue
    }

    private func revealAskComposer() {
        isAskComposerVisible = true
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

    private var articleContentTransition: AnyTransition {
        .asymmetric(insertion: .opacity, removal: .identity)
    }

    private var articleAnswerTransition: AnyTransition {
        if reduceMotion {
            .opacity
        } else {
            .move(edge: .bottom).combined(with: .opacity)
        }
    }

    private var backSwipeProgress: CGFloat {
        guard readerWidth > 0 else { return 0 }
        return min(max(backSwipeOffset / readerWidth, 0), 1)
    }
}

#Preview {
    ArticleDetailView(
        store: DemoStore(initialScreen: .reader),
        article: DemoContent.primaryArticle,
        onBack: {}
    )
}
