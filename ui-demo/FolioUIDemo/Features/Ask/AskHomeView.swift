import SwiftUI

struct AskHomeView: View {
    let onOpenSettings: () -> Void
    let onOpenSource: () -> Void
    @FocusState.Binding var isQuestionFocused: Bool
    @State private var question = ""
    @State private var submittedQuestion: String?
    @State private var showsInsufficientEvidence = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 13) {
                Text("问 Folio")
                    .font(FolioTypography.editorialBold(34, relativeTo: .largeTitle))
                    .foregroundStyle(FolioPalette.inkGreenDeep)
                    .lineLimit(1)

                Spacer()

                ZStack {
                    if isQuestionFocused {
                        Button(
                            "收起键盘",
                            systemImage: "keyboard.chevron.compact.down",
                            action: dismissKeyboard
                        )
                        .labelStyle(.iconOnly)
                        .font(.body.bold())
                        .foregroundStyle(FolioPalette.inkGreenDeep)
                        .contentShape(.rect)
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("ask-dismiss-keyboard")
                        .transition(.opacity)
                    }
                }
                .frame(
                    width: FolioMetrics.minimumTapTarget,
                    height: FolioMetrics.minimumTapTarget
                )

                Button(action: onOpenSettings) {
                    FolioAvatar(size: FolioMetrics.minimumTapTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("打开设置")
            }
            .padding(.horizontal, FolioMetrics.libraryInset)
            .padding(.top, 18)
            .padding(.bottom, 17)
            .animation(
                FolioMotion.chromeVisibility(reduceMotion: reduceMotion),
                value: isQuestionFocused
            )

            ScrollView {
                if let submittedQuestion {
                    AskConversationContent(
                        question: submittedQuestion,
                        showsInsufficientEvidence: showsInsufficientEvidence,
                        onOpenSource: onOpenSource,
                        onSuggestion: showTrustAnswer
                    )
                    .transition(responseTransition)
                } else {
                    AskHomeEmptyContent(
                        onTrustSuggestion: showTrustAnswer,
                        onReadingSuggestion: showReadingAnswer,
                        onPerformanceSuggestion: showPerformanceInsufficient
                    )
                    .transition(responseTransition)
                }
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .animation(
                FolioMotion.chromeVisibility(reduceMotion: reduceMotion),
                value: submittedQuestion
            )

            FolioInputBar(
                text: $question,
                isFocused: $isQuestionFocused,
                placeholder: "问问你的收藏",
                isEnabled: hasQuestion,
                action: submitQuestion
            )
            .padding(.horizontal, FolioMetrics.libraryInset)
            .padding(.vertical, 10)
        }
        .background(FolioPalette.canvas)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func dismissKeyboard() {
        isQuestionFocused = false
    }

    private func submitQuestion() {
        let submittedText = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !submittedText.isEmpty else { return }
        showResponse(
            to: submittedText,
            isInsufficient: submittedText.localizedStandardContains("行业")
                || submittedText.localizedStandardContains("SwiftUI")
        )
    }

    private func showTrustAnswer() {
        showResponse(to: "我保存的内容如何定义 AI 可信度？", isInsufficient: false)
    }

    private func showReadingAnswer() {
        showResponse(to: "我读过哪些关于深度阅读的观点？", isInsufficient: false)
    }

    private func showPerformanceInsufficient() {
        showResponse(to: "SwiftUI 性能优化有哪些共同建议？", isInsufficient: true)
    }

    private func showResponse(to submittedText: String, isInsufficient: Bool) {
        isQuestionFocused = false
        question = ""
        showsInsufficientEvidence = isInsufficient
        submittedQuestion = submittedText
    }

    private var hasQuestion: Bool {
        !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var responseTransition: AnyTransition {
        .asymmetric(insertion: .opacity, removal: .identity)
    }
}

#Preview {
    @Previewable @FocusState var isQuestionFocused: Bool
    @Previewable @State var selectedTab = DemoTab.ask
    @Previewable @State var quickSavePhase = QuickSavePhase.idle
    @Previewable @State var quickSaveText = ""

    AskHomeView(
        onOpenSettings: {},
        onOpenSource: {},
        isQuestionFocused: $isQuestionFocused
    )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FolioTabBar(
                selectedTab: $selectedTab,
                quickSavePhase: $quickSavePhase,
                quickSaveText: $quickSaveText
            )
            .padding(.horizontal, FolioMetrics.compactInset)
            .padding(.vertical, 8)
        }
}
