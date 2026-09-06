import SwiftUI

struct ReaderInsightPanel: View {
    let article: Article
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header (always visible)
            Button {
                withAnimation(Motion.settle) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Text("✦")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.folio.accent)

                    Text(article.displaySummary ?? "")
                        .font(Typography.v3InsightMain)
                        .foregroundStyle(Color.folio.textPrimary)
                        .lineSpacing(15 * 0.55)
                        .lineLimit(isExpanded ? nil : 2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.folio.textQuaternary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
            }
            .buttonStyle(.plain)

            // Detail (expanded only)
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    Rectangle()
                        .fill(Color.folio.separator)
                        .frame(height: 0.5)
                        .padding(.top, 14)
                        .padding(.bottom, 12)

                    ForEach(article.keyPoints, id: \.self) { point in
                        HStack(alignment: .top, spacing: 0) {
                            Text("·")
                                .foregroundStyle(Color.folio.textQuaternary)
                                .frame(width: 24)
                            Text(point)
                                .font(.system(size: 14))
                                .foregroundStyle(Color.folio.textSecondary)
                                .lineSpacing(14 * 0.6)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(Color.folio.accentSoft)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.bottom, 24)
    }
}
