import SwiftUI

struct HomeAskFolioCardView: View {
    let isAuthenticated: Bool
    let readyArticleCount: Int
    let onAsk: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.folio.accent)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title)
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.folio.textPrimary)

                    Text(message)
                        .font(Typography.caption)
                        .foregroundStyle(Color.folio.textSecondary)
                        .lineLimit(3)
                }
            }

            Button(buttonTitle, systemImage: buttonIcon, action: buttonAction)
                .font(Typography.body)
                .foregroundStyle(buttonEnabled ? Color.folio.background : Color.folio.textTertiary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(buttonEnabled ? Color.folio.textPrimary : Color.folio.echoBg)
                .clipShape(RoundedRectangle(cornerRadius: 8))
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
            return "等内容处理完成后再提问"
        }
        return "向自己的资料库提问"
    }

    private var message: String {
        if !isAuthenticated {
            return "登录后，Folio 会基于你的收藏回答，并在证据不足时明确说明。"
        }
        if readyArticleCount == 0 {
            return "保存的内容完成分析后，会作为问答来源出现在这里。"
        }
        return "当前有 \(readyArticleCount) 篇可作为来源。回答会附带来源文章，便于回到原文核验。"
    }

    private var buttonTitle: String {
        if !isAuthenticated {
            return "登录开启"
        }
        return "开始提问"
    }

    private var buttonIcon: String {
        isAuthenticated ? "text.bubble" : "person.crop.circle"
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
