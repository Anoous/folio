import SwiftUI

struct EmailAuthHeaderView: View {
    let step: EmailAuthStep

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: iconName)
                    .font(.headline)
                    .foregroundStyle(Color.folio.accent)
                    .frame(width: 32, height: 32)
                    .background(Color.folio.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                    .accessibilityHidden(true)

                Text("Folio 账号")
                    .font(Typography.caption)
                    .foregroundStyle(Color.folio.textSecondary)
            }

            Text(title)
                .font(Typography.pageTitle)
                .foregroundStyle(Color.folio.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(subtitle)
                .font(Typography.body)
                .foregroundStyle(Color.folio.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var title: String {
        switch step {
        case .email:
            "连接你的资料库"
        case .code:
            "输入邮箱验证码"
        }
    }

    private var subtitle: String {
        switch step {
        case .email:
            "登录后可以同步已保存内容，并启用 Ask Folio、AI 摘要和 Echo 复习。"
        case .code:
            "确认邮箱后会回到 Folio。验证码过期或证据不足时，页面会明确给出反馈。"
        }
    }

    private var iconName: String {
        switch step {
        case .email:
            "person.crop.circle.badge.plus"
        case .code:
            "envelope.badge.shield.half.filled"
        }
    }
}

#Preview {
    EmailAuthHeaderView(step: .email)
        .padding()
}
