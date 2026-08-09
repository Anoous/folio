import SwiftUI

struct ArticleAskSheetView: View {
    let article: DemoArticle
    @Bindable var session: ArticleAskSession
    let onOpenEvidence: () -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isComposerFocused: Bool
    @State private var selectedDetent = PresentationDetent.fraction(0.48)

    var body: some View {
        VStack(spacing: 0) {
            ArticleAskSheetHeader(onHide: hide)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ArticleAskScopeChip(articleTitle: article.title)
                        .id("article-ask-scope")

                    if let question = session.submittedQuestion, let answer = session.answer {
                        ArticleAskAnswerCard(
                            question: question,
                            answer: answer,
                            onOpenEvidence: openEvidence,
                            onContinueReading: completeAndHide
                        )
                    } else {
                        ArticleAskSuggestionsView(onSelect: submitSuggestion)
                            .id("article-ask-suggestions")
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, FolioMetrics.libraryInset)
                .padding(.bottom, 20)
            }
            .scrollPosition(id: $session.answerScrollTarget, anchor: .top)
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)

            FolioInputBar(
                text: $session.draft,
                isFocused: $isComposerFocused,
                placeholder: session.hasConversation ? "继续提问…" : "问这篇文章…",
                isEnabled: session.canSubmit,
                action: submitQuestion
            )
            .padding(.horizontal, FolioMetrics.libraryInset)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
        .background(FolioPalette.surface.opacity(0.96))
        .presentationDetents([.fraction(0.48), .large], selection: $selectedDetent)
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
        .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.48)))
        .presentationBackground(.thinMaterial)
        .presentationCornerRadius(26)
        .sensoryFeedback(.selection, trigger: selectedDetent)
        .onChange(of: isComposerFocused, focusChanged)
    }

    private func focusChanged(_ oldValue: Bool, _ newValue: Bool) {
        if newValue {
            selectedDetent = .large
        } else if oldValue {
            selectedDetent = .fraction(0.48)
        }
    }

    private func submitQuestion() {
        guard session.canSubmit else { return }
        session.submit()
        isComposerFocused = false
        selectedDetent = .fraction(0.48)
    }

    private func submitSuggestion(_ question: String) {
        session.submitSuggestion(question)
        isComposerFocused = false
    }

    private func openEvidence() {
        isComposerFocused = false
        onOpenEvidence()
    }

    private func completeAndHide() {
        session.complete()
        hide()
    }

    private func hide() {
        isComposerFocused = false
        dismiss()
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            ArticleAskSheetView(
                article: DemoContent.primaryArticle,
                session: ArticleAskSession(),
                onOpenEvidence: {}
            )
        }
}
