import SwiftUI

struct EchoCardView: View {
    let card: EchoCard
    let onReview: (String, @escaping (EchoReviewResponse?) -> Void) -> Void

    @State private var step: Int = 0
    @State private var reviewResult: String?
    @State private var reviewResponse: EchoReviewResponse?
    @State private var answerVisible = false
    @State private var revealPressed = false
    @State private var rememberedPressed = false
    @State private var forgotPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .background(Color.folio.echoBg)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.vertical, 12)
    }

    // MARK: - Step 0: Question

    private var questionStep: some View {
        VStack(spacing: 0) {
            Text("\u{2726} ECHO")
                .font(.system(size: 11, weight: .medium))
                .tracking(2.5)
                .textCase(.uppercase)
                .foregroundStyle(Color.folio.textTertiary)
                .padding(.bottom, 20)

            Text(card.question)
                .font(Typography.v3EchoQuestion)
                .foregroundStyle(Color.folio.textPrimary)
                .multilineTextAlignment(.center)
                .lineSpacing(17 * 0.65)
                .frame(maxWidth: 300)
                .padding(.bottom, 12)

            if let source = card.sourceContext, !source.isEmpty {
                Text(source)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.folio.textQuaternary)
                    .padding(.bottom, 24)
            } else {
                Spacer().frame(height: 24)
            }

            Button {
                withAnimation(Motion.resolved(Motion.settle, reduceMotion: reduceMotion) ?? .default) {
                    step = 1
                }
                // Trigger answer fade-up after step transition
                withAnimation(Motion.resolved(Motion.settle, reduceMotion: reduceMotion)?.delay(0.05) ?? .default) {
                    answerVisible = true
                }
            } label: {
                Text("揭晓答案")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.folio.textSecondary)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 28)
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.folio.separator, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .scaleEffect(revealPressed ? 0.96 : 1.0)
            .opacity(revealPressed ? 0.6 : 1.0)
            .animation(Motion.resolved(Motion.quick, reduceMotion: reduceMotion), value: revealPressed)
            ._onButtonGesture { pressing in
                revealPressed = pressing
            } perform: {}
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Step 1: Answer Revealed

    private var answerStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(card.question)
                .font(.system(size: 15))
                .foregroundStyle(Color.folio.textTertiary)
                .padding(.bottom, 16)

            // Answer with left accent border
            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.folio.accent)
                    .frame(width: 2)
                Text(card.answer)
                    .font(Typography.v3EchoQuestion)
                    .foregroundStyle(Color.folio.textPrimary)
                    .lineSpacing(17 * 0.6)
                    .padding(.leading, 14)
            }
            .opacity(answerVisible ? 1 : 0)
            .offset(y: answerVisible ? 0 : 8)
            .padding(.bottom, 12)

            // Source attribution
            Text(card.articleTitle)
                .font(.system(size: 12))
                .foregroundStyle(Color.folio.textQuaternary)
                .padding(.leading, 16)
                .padding(.bottom, 22)
                .opacity(answerVisible ? 1 : 0)

            // Feedback buttons
            HStack(spacing: 10) {
                feedbackButton(
                    label: "记得",
                    dotColor: Color.folio.success,
                    borderColor: Color(red: 36/255, green: 138/255, blue: 61/255).opacity(0.15),
                    isPressed: $rememberedPressed
                ) {
                    submitReview("remembered")
                }

                feedbackButton(
                    label: "忘了",
                    dotColor: Color.folio.error,
                    borderColor: Color(red: 215/255, green: 0/255, blue: 21/255).opacity(0.1),
                    isPressed: $forgotPressed
                ) {
                    submitReview("forgot")
                }
            }
            .opacity(answerVisible ? 1 : 0)
        }
        .padding(24)
    }

    // MARK: - Step 2: Confirmed

    private var confirmedStep: some View {
        VStack(spacing: 0) {
            if let result = reviewResult {
                let interval = reviewResponse?.intervalDays ?? card.intervalDays
                if result == "remembered" {
                    Text("\u{2713} 已记录 \u{00B7} 下次 \(formatInterval(interval)) 后回顾")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.folio.textSecondary)
                } else {
                    Text("已标记 \u{00B7} \(formatInterval(interval)) 后再来")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.folio.textSecondary)
                }
            }

            if let response = reviewResponse {
                Divider()
                    .padding(.top, 10)

                Text(response.streak.display)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.folio.textQuaternary)
                    .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 24)
    }

    // MARK: - Helpers

    private func feedbackButton(
        label: String,
        dotColor: Color,
        borderColor: Color,
        isPressed: Binding<Bool>,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                Text(label)
                    .font(.system(size: 14))
                    .foregroundStyle(dotColor)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
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
