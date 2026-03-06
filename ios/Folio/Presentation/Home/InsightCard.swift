import SwiftUI

struct InsightCard: View {
    let insight: MockInsight
    var onDismiss: () -> Void = {}
    var onRead: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Header
            HStack(spacing: Spacing.xxs) {
                Image(systemName: "lightbulb.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
                Text(String(localized: "insight.header", defaultValue: "Knowledge Recall"))
                    .font(Typography.tag)
                    .foregroundStyle(Color.folio.textSecondary)
                Spacer()
                Text(insight.timeAgo)
                    .font(Typography.caption)
                    .foregroundStyle(Color.folio.textTertiary)
            }

            // Insight quote
            Text(insight.quote)
                .font(Typography.body)
                .foregroundStyle(Color.folio.textPrimary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            // Article reference
            Text(insight.articleTitle)
                .font(Typography.caption)
                .foregroundStyle(Color.folio.link)
                .lineLimit(1)

            // Action buttons
            HStack(spacing: Spacing.sm) {
                Button {
                    onDismiss()
                } label: {
                    Text(String(localized: "insight.gotIt", defaultValue: "Got it"))
                        .font(Typography.tag)
                        .foregroundStyle(Color.folio.textSecondary)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xxs)
                        .background(Color.folio.cardBackground)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.folio.separator, lineWidth: 1))
                }

                Button {
                    onRead()
                } label: {
                    Text(String(localized: "insight.readAgain", defaultValue: "Read again"))
                        .font(Typography.tag)
                        .foregroundStyle(Color.folio.accent)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xxs)
                        .background(Color.folio.accent.opacity(0.1))
                        .clipShape(Capsule())
                }

                Spacer()
            }
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.medium)
                .fill(Color.folio.cardBackground)
                .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
        )
    }
}

// MARK: - Mock Data

struct MockInsight: Identifiable {
    let id = UUID()
    let quote: String
    let articleTitle: String
    let timeAgo: String

    static let sample = MockInsight(
        quote: String(localized: "insight.mock.quote", defaultValue: "The best pricing strategy for indie apps: anchor to the annual price, then show the monthly price as comparison. Annual plans convert 3x better."),
        articleTitle: String(localized: "insight.mock.article", defaultValue: "Indie App Pricing Strategies in 2026"),
        timeAgo: String(localized: "insight.mock.time", defaultValue: "Saved 3 weeks ago")
    )
}

#Preview {
    InsightCard(insight: .sample)
        .padding()
}
