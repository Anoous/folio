import SwiftUI

struct AskHomeView: View {
    let onOpenSettings: () -> Void
    let onOpenSource: () -> Void
    let onReturnHome: () -> Void
    @FocusState.Binding var isQuestionFocused: Bool
    @State private var question = ""
    @State private var submittedQuestion: String?
    @State private var showsInsufficientEvidence = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("问 Folio")
                    .font(.headline)

                HStack {
                    if isQuestionFocused {
                        Button(
                            "返回",
                            systemImage: "chevron.left",
                            action: returnHome
                        )
                        .labelStyle(.iconOnly)
                        .font(.body.bold())
                        .foregroundStyle(FolioPalette.inkGreenDeep)
                        .frame(
                            width: FolioMetrics.minimumTapTarget,
                            height: FolioMetrics.minimumTapTarget
                        )
                        .contentShape(.rect)
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("ask-input-back")
                    } else {
                        Color.clear
                            .frame(
                                width: FolioMetrics.minimumTapTarget,
                                height: FolioMetrics.minimumTapTarget
                            )
                            .accessibilityHidden(true)
                    }

                    Spacer()

                    Button(action: onOpenSettings) {
                        FolioAvatar(size: FolioMetrics.minimumTapTarget)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("打开设置")
                }
            }
            .padding(.horizontal, FolioMetrics.libraryInset)
            .padding(.top, 8)
            .padding(.bottom, 8)

            ScrollView {
                if let submittedQuestion {
                    AskConversationContent(
                        question: submittedQuestion,
                        showsInsufficientEvidence: showsInsufficientEvidence,
                        onOpenSource: onOpenSource,
                        onSuggestion: showTrustAnswer
                    )
                    .transition(.opacity)
                } else {
                    AskHomeEmptyContent(
                        onTrustSuggestion: showTrustAnswer,
                        onReadingSuggestion: showReadingAnswer,
                        onPerformanceSuggestion: showPerformanceInsufficient
                    )
                    .transition(.opacity)
                }
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .animation(
                FolioMotion.articleContentSwitch(reduceMotion: reduceMotion),
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

    private func returnHome() {
        isQuestionFocused = false
        onReturnHome()
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
}

#Preview {
    @Previewable @FocusState var isQuestionFocused: Bool
    @Previewable @State var selectedTab = DemoTab.ask
    @Previewable @State var quickSavePhase = QuickSavePhase.idle
    @Previewable @State var quickSaveText = ""

    AskHomeView(
        onOpenSettings: {},
        onOpenSource: {},
        onReturnHome: {},
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
