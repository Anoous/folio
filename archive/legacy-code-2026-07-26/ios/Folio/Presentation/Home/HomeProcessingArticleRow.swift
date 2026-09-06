import SwiftUI

struct HomeProcessingArticleRow: View {
    let article: Article
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(article.displayTitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.folio.textPrimary)
                    .lineLimit(2)

                Text(detailText)
                    .font(Typography.caption)
                    .foregroundStyle(Color.folio.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: Spacing.sm)

            if article.status == .failed {
                Button("重试", action: onRetry)
                    .font(Typography.caption)
                    .foregroundStyle(Color.folio.accent)
                    .buttonStyle(.plain)
            }
        }
        .padding(Spacing.md)
        .background(Color.folio.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var iconName: String {
        switch article.status {
        case .failed:
            return "exclamationmark.triangle.fill"
        case .clientReady:
            return "checkmark.circle.fill"
        case .pending:
            return "tray.and.arrow.up"
        case .processing:
            return "clock"
        case .ready:
            return "doc.text"
        }
    }

    private var iconColor: Color {
        switch article.status {
        case .failed:
            return Color.folio.error
        case .clientReady:
            return Color.folio.success
        case .pending, .processing:
            return Color.folio.accent
        case .ready:
            return Color.folio.textTertiary
        }
    }

    private var detailText: String {
        switch article.status {
        case .pending:
            return "已保存，等待上传和分析。"
        case .processing:
            return "服务端正在阅读并提炼摘要。"
        case .clientReady:
            return "本地内容已可读，等待服务端同步增强。"
        case .failed:
            return article.fetchError ?? "处理失败，可重试。"
        case .ready:
            return "已可阅读。"
        }
    }
}
