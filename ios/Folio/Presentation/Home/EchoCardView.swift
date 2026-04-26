import SwiftUI
import UserNotifications

/// Lightweight value type holding only the fields EchoCardView needs for display.
/// Constructed from either `EchoCard` (SwiftData) or `EchoCardDTO` (API).
struct EchoCardData {
    let question: String
    let answer: String
    let sourceContext: String?
    let articleTitle: String
    let intervalDays: Int

    init(question: String, answer: String, sourceContext: String?, articleTitle: String, intervalDays: Int) {
        self.question = question
        self.answer = answer
        self.sourceContext = sourceContext
        self.articleTitle = articleTitle
        self.intervalDays = intervalDays
    }

    init(from model: EchoCard) {
        self.question = model.question
        self.answer = model.answer
        self.sourceContext = model.sourceContext
        self.articleTitle = model.articleTitle
        self.intervalDays = model.intervalDays
    }

    init(from dto: EchoCardDTO) {
        self.question = dto.question
        self.answer = dto.answer
        self.sourceContext = dto.sourceContext
        self.articleTitle = dto.articleTitle
        self.intervalDays = dto.intervalDays
    }

    static let prototype = EchoCardData(
        question: "还记得抽象层常会\n怎样吗?",
        answer: "抽象层会在需求变化时泄漏细节，所以要持续回到具体使用场景里校准。",
        sourceContext: "Essays on programming\nI think about a lot",
        articleTitle: "Essays on programming I think about a lot",
        intervalDays: 2
    )
}

struct EchoCardView: View {
    let card: EchoCardData
    let onReview: (String, @escaping (EchoReviewResponse?) -> Void) -> Void

    @State private var step: Int = 0
    @State private var reviewResult: String?
    @State private var reviewResponse: EchoReviewResponse?
    @State private var answerVisible = false
    @State private var revealPressed = false
    @State private var rememberedPressed = false
    @State private var forgotPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AppConstants.hasRequestedNotificationsKey) private var hasRequestedNotifications = false

    var body: some View {
        PaperSheetView {
            Group {
                switch step {
                case 0:
                    questionStep
                case 1:
                    answerStep
                default:
                    confirmedStep
                }
            }
        }
        .frame(height: step == 1 ? 382 : 348)
        .padding(.horizontal, 25)
        .padding(.bottom, 30)
        .sensoryFeedback(.impact(weight: .light), trigger: step) { oldValue, newValue in
            newValue == 1
        }
    }

    // MARK: - Step 0: Question

    private var questionStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "sparkle")
                    .font(.system(size: 25, weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(FolioPaperPalette.accentBlue)

                Text("今日 Echo")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(FolioPaperPalette.ink)

                Spacer()
            }

            Rectangle()
                .fill(FolioPaperPalette.faintLine)
                .frame(height: 1)
                .padding(.top, 15)
                .padding(.bottom, 22)

            Text(card.question)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(FolioPaperPalette.ink)
                .lineSpacing(8)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .minimumScaleFactor(0.82)
                .fixedSize(horizontal: false, vertical: true)

            sourceLine
                .padding(.top, 22)

            Spacer(minLength: 12)

            HStack {
                Spacer()

                Button {
                    revealAnswer()
                } label: {
                    Text("回想")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(width: 130, height: 52)
                        .background {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.310, green: 0.596, blue: 1.000),
                                            Color(red: 0.073, green: 0.390, blue: 0.895),
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: FolioPaperPalette.accentBlue.opacity(0.28), radius: 10, x: 0, y: 5)
                        }
                }
                .buttonStyle(.plain)
                .scaleEffect(revealPressed ? 0.98 : 1.0)
                .animation(Motion.resolved(Motion.quick, reduceMotion: reduceMotion), value: revealPressed)
                ._onButtonGesture { pressing in
                    revealPressed = pressing
                } perform: {}
                .accessibilityLabel("回想")
            }
        }
        .padding(.top, 28)
        .padding(.leading, 44)
        .padding(.trailing, 31)
        .padding(.bottom, 31)
        .accessibilityLabel("今日 Echo，\(card.question)，揭晓答案")
    }

    private var sourceLine: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Color.gray.opacity(0.72))
                .padding(.top, 2)

            Text(sourceTitle)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Color.gray.opacity(0.76))
                .lineLimit(2)
                .lineSpacing(3)
        }
    }

    private var sourceTitle: String {
        if let source = card.sourceContext, !source.isEmpty {
            return "来自 《\(source)》 · web"
        }
        return "来自 《\(card.articleTitle)》 · web"
    }

    private func revealAnswer() {
        withAnimation(Motion.resolved(Motion.settle, reduceMotion: reduceMotion) ?? .default) {
            step = 1
        }
        withAnimation(Motion.resolved(Motion.settle, reduceMotion: reduceMotion)?.delay(0.05) ?? .default) {
            answerVisible = true
        }
    }

    // MARK: - Step 1: Answer Revealed

    private var answerStep: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Label("答案", systemImage: "checkmark.circle")
                    .font(.headline)
                    .foregroundStyle(FolioPaperPalette.ink)

                Text(card.answer)
                    .font(.body)
                    .foregroundStyle(FolioPaperPalette.ink)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(answerVisible ? 1 : 0)
                    .offset(y: answerVisible ? 0 : 6)
            }

            Divider()

            HStack(spacing: Spacing.sm) {
                feedbackButton(
                    label: "记得",
                    systemImage: "checkmark",
                    tint: Color.folio.success,
                    isPressed: $rememberedPressed
                ) {
                    submitReview("remembered")
                }

                feedbackButton(
                    label: "忘了",
                    systemImage: "arrow.counterclockwise",
                    tint: Color.folio.error,
                    isPressed: $forgotPressed
                ) {
                    submitReview("forgot")
                }
            }
            .opacity(answerVisible ? 1 : 0)
        }
        .padding(.top, 31)
        .padding(.leading, 44)
        .padding(.trailing, 31)
        .padding(.bottom, 31)
    }

    // MARK: - Step 2: Confirmed

    private var confirmedStep: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if let result = reviewResult {
                let interval = reviewResponse?.intervalDays ?? card.intervalDays
                Label(
                    result == "remembered" ? "已记录，下次 \(formatInterval(interval)) 后回顾" : "已标记，\(formatInterval(interval)) 后再来",
                    systemImage: result == "remembered" ? "checkmark.circle" : "arrow.counterclockwise.circle"
                )
                .font(.body)
                .foregroundStyle(FolioPaperPalette.ink)
            }

            if let response = reviewResponse {
                Text(response.streak.display)
                    .font(.footnote)
                    .foregroundStyle(FolioPaperPalette.secondaryInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 31)
        .padding(.leading, 44)
        .padding(.trailing, 31)
        .padding(.bottom, 31)
    }

    // MARK: - Helpers

    private func feedbackButton(
        label: String,
        systemImage: String,
        tint: Color,
        isPressed: Binding<Bool>,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .font(.body)
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm)
                .background(tint.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed.wrappedValue ? 0.97 : 1.0)
        .animation(Motion.resolved(Motion.quick, reduceMotion: reduceMotion), value: isPressed.wrappedValue)
        ._onButtonGesture { pressing in
            isPressed.wrappedValue = pressing
        } perform: {}
    }

    private func submitReview(_ result: String) {
        reviewResult = result
        onReview(result) { response in
            reviewResponse = response
            withAnimation(Motion.resolved(Motion.exit, reduceMotion: reduceMotion) ?? .default) {
                step = 2
            }
        }
        if !hasRequestedNotifications {
            hasRequestedNotifications = true
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                if granted {
                    DispatchQueue.main.async {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                }
            }
        }
    }

    private func formatInterval(_ days: Int) -> String {
        switch days {
        case 1: return "明天"
        case 7: return "1 周"
        case 14: return "2 周"
        case 30: return "1 个月"
        default: return "\(days) 天"
        }
    }
}
