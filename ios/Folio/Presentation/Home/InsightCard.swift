import SwiftUI

struct InsightCard: View {
    let onDismiss: () -> Void

    private let mockRecallText = String(
        localized: "insight.recallText",
        defaultValue: "3 weeks ago you saved a pricing strategy insight from \"Growth Hacking Weekly\"."
    )

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Header row
            HStack(alignment: .top, spacing: Spacing.xs) {
                Image(systemName: "lightbulb.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color.folio.warning)

                Text(mockRecallText)
                    .font(Typography.body)
                    .foregroundStyle(Color.folio.textPrimary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        onDismiss()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(Color.folio.textTertiary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }

            // Action buttons
            HStack(spacing: Spacing.md) {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        onDismiss()
                    }
                } label: {
                    Text(String(localized: "insight.gotIt", defaultValue: "Got it"))
                        .font(Typography.tag)
                        .foregroundStyle(Color.folio.textSecondary)
                }
                .buttonStyle(.plain)

                Text("\u{00B7}")
                    .foregroundStyle(Color.folio.textTertiary)

                Button {
                    // Mock action — in production this would navigate to the article
                } label: {
                    Text(String(localized: "insight.readAgain", defaultValue: "Read again"))
                        .font(Typography.tag)
                        .foregroundStyle(Color.folio.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, Spacing.lg)
        }
        .padding(Spacing.md)
        .background(Color.folio.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.medium)
                .stroke(Color.folio.separator, lineWidth: 0.5)
        )
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.vertical, Spacing.xs)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets())
    }
}

#Preview {
    List {
        InsightCard(onDismiss: {})
    }
    .listStyle(.plain)
}
