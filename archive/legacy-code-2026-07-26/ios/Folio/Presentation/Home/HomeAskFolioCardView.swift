import SwiftUI

struct HomeAskFolioCardView: View {
    let isAuthenticated: Bool
    let readyArticleCount: Int
    let onAsk: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.sm) {
            Image(systemName: "sparkles")
                .foregroundStyle(Color.folio.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(Color.folio.textPrimary)

                Text(message)
                    .font(Typography.caption)
                    .foregroundStyle(Color.folio.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Spacing.sm)

            Button(buttonTitle, action: buttonAction)
                .font(Typography.caption)
                .foregroundStyle(buttonEnabled ? Color.folio.background : Color.folio.textTertiary)
                .padding(.horizontal, Spacing.md)
                .frame(height: 34)
                .background(buttonEnabled ? Color.folio.textPrimary : Color.folio.echoBg)
                .clipShape(Capsule())
                .buttonStyle(.plain)
                .disabled(!buttonEnabled)
        }
        .padding(Spacing.md)
        .background(Color.folio.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, Spacing.screenPadding)
    }

    private var title: String {
        if !isAuthenticated {
            return "Ask Folio 需要登录"
        }
        if readyArticleCount == 0 {
            return "Ask Folio"
        }
        return "Ask Folio"
    }

    private var message: String {
        if !isAuthenticated {
            return "登录后使用资料库问答"
        }
        if readyArticleCount == 0 {
            return "等待内容完成分析"
        }
        return "\(readyArticleCount) 篇可作为来源"
    }

    private var buttonTitle: String {
        if !isAuthenticated {
            return "登录"
        }
        return "提问"
    }

    private var buttonEnabled: Bool {
        !isAuthenticated || readyArticleCount > 0
    }

    private func buttonAction() {
        if isAuthenticated {
            onAsk()
        } else {
            onOpenSettings()
        }
    }
}
