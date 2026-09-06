import SwiftUI

struct HomeProcessingQueueView: View {
    let articles: [Article]
    let onRetry: (Article) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if articles.isEmpty {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(Color.folio.success)
                    Text("没有正在处理或失败的内容")
                        .font(Typography.caption)
                        .foregroundStyle(Color.folio.textSecondary)
                    Spacer()
                }
                .padding(Spacing.md)
                .background(Color.folio.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ForEach(articles) { article in
                    HomeProcessingArticleRow(article: article) {
                        onRetry(article)
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.screenPadding)
    }
}
