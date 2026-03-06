import SwiftUI

struct DailyDigestCard: View {
    @State private var isExpanded = false
    @State private var isPlaying = false

    private let mockDuration = "5:00"
    private let mockArticleCount = 3

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Header row
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "headphones")
                        .font(.subheadline)
                        .foregroundStyle(Color.folio.accent)

                    Text(String(localized: "digest.title", defaultValue: "Today's Digest"))
                        .font(Typography.listTitle)
                        .foregroundStyle(Color.folio.textPrimary)

                    Text("\u{00B7}")
                        .foregroundStyle(Color.folio.textTertiary)

                    Text(String(
                        format: NSLocalizedString(
                            "digest.duration",
                            value: "%d min",
                            comment: "Digest audio duration in minutes"
                        ),
                        5
                    ))
                    .font(Typography.caption)
                    .foregroundStyle(Color.folio.textTertiary)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(Color.folio.textTertiary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                // Mock audio player
                HStack(spacing: Spacing.sm) {
                    Button {
                        isPlaying.toggle()
                    } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.subheadline)
                            .foregroundStyle(Color.folio.accent)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)

                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.folio.separator)
                                .frame(height: 3)

                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.folio.accent)
                                .frame(width: 0, height: 3)
                        }
                        .frame(maxHeight: .infinity, alignment: .center)
                    }
                    .frame(height: 20)

                    Text("0:00 / \(mockDuration)")
                        .font(Typography.caption)
                        .foregroundStyle(Color.folio.textTertiary)
                        .monospacedDigit()
                }

                // Summary text
                Text(String(
                    format: NSLocalizedString(
                        "digest.summary",
                        value: "Today you saved %d articles about Swift concurrency, iOS architecture, and testing patterns.",
                        comment: "Daily digest summary text"
                    ),
                    mockArticleCount
                ))
                .font(Typography.body)
                .foregroundStyle(Color.folio.textSecondary)
                .lineSpacing(4)
            }
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
        DailyDigestCard()
    }
    .listStyle(.plain)
}
