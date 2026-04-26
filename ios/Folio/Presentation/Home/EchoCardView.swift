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
        .background(Color.folio.cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.folio.separator, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.vertical, Spacing.xs)
        .sensoryFeedback(.impact(weight: .light), trigger: step) { oldValue, newValue in
            newValue == 1
        }
    }

    // MARK: - Step 0: Question

    private var questionStep: some View {
        Button {
            revealAnswer()
        } label: {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.xs) {
                    Label("今日 Echo", systemImage: "sparkle")
                        .font(.headline)
                        .foregroundStyle(Color.folio.textPrimary)

                    Spacer(minLength: Spacing.sm)

                    Text("揭晓")
                        .font(.callout)
                        .foregroundStyle(Color.folio.accent)

                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(Color.folio.textTertiary)
                }

                Text(card.question)
                    .font(.body)
                    .foregroundStyle(Color.folio.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                sourceLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.md)
        }
        .buttonStyle(.plain)
        .scaleEffect(revealPressed ? 0.98 : 1.0)
        .animation(Motion.resolved(Motion.quick, reduceMotion: reduceMotion), value: revealPressed)
        ._onButtonGesture { pressing in
            revealPressed = pressing
        } perform: {}
        .accessibilityLabel("今日 Echo，\(card.question)，揭晓答案")
    }

    private var sourceLine: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "doc.text")
                .font(.footnote)
                .foregroundStyle(Color.folio.textTertiary)

            Text(sourceTitle)
                .font(.footnote)
                .foregroundStyle(Color.folio.textSecondary)
                .lineLimit(1)
        }
    }

    private var sourceTitle: String {
        if let source = card.sourceContext, !source.isEmpty {
            return source
        }
        return card.articleTitle
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
                    .foregroundStyle(Color.folio.textPrimary)

                Text(card.answer)
                    .font(.body)
                    .foregroundStyle(Color.folio.textPrimary)
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
        .padding(Spacing.md)
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
                .foregroundStyle(Color.folio.textPrimary)
            }

            if let response = reviewResponse {
                Text(response.streak.display)
                    .font(.footnote)
                    .foregroundStyle(Color.folio.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
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
