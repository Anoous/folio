import SwiftUI

struct LibrarySummaryLine: View {
    let article: DemoArticle
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            if article.status.isInProgress {
                ProgressView()
                    .controlSize(.small)
                    .tint(FolioPalette.inkGreen)
            } else {
                Rectangle()
                    .fill(article.status == .ready ? FolioPalette.inkGreen : attentionColor)
                    .frame(width: 2, height: 18)
            }

            Text(article.summary)
                .font(FolioTypography.editorial(15.5, relativeTo: .body))
                .foregroundStyle(article.status.isInProgress ? .primary : FolioPalette.secondaryText)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var attentionColor: Color {
        article.status == .failed ? FolioPalette.danger : FolioPalette.warning
    }
}
