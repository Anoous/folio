import SwiftUI

struct EmailAuthMessageView: View {
    enum Kind {
        case error
        case success
        case note
    }

    let kind: Kind
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            Image(systemName: iconName)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 18)
                .accessibilityHidden(true)

            Text(message)
                .font(Typography.caption)
                .foregroundStyle(textColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.sm)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.medium)
                .stroke(borderColor, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var iconName: String {
        switch kind {
        case .error:
            "exclamationmark.triangle.fill"
        case .success:
            "checkmark.circle.fill"
        case .note:
            "info.circle.fill"
        }
    }

    private var tint: Color {
        switch kind {
        case .error:
            Color.folio.error
        case .success:
            Color.folio.success
        case .note:
            Color.folio.accent
        }
    }

    private var textColor: Color {
        switch kind {
        case .error:
            Color.folio.error
        case .success:
            Color.folio.textPrimary
        case .note:
            Color.folio.textSecondary
        }
    }

    private var backgroundColor: Color {
        switch kind {
        case .error:
            Color.folio.error.opacity(0.08)
        case .success:
            Color.folio.success.opacity(0.1)
        case .note:
            Color.folio.echoBg
        }
    }

    private var borderColor: Color {
        switch kind {
        case .error:
            Color.folio.error.opacity(0.25)
        case .success:
            Color.folio.success.opacity(0.25)
        case .note:
            Color.folio.separator.opacity(0.7)
        }
    }
}

#Preview {
    VStack {
        EmailAuthMessageView(kind: .error, message: "验证码无效或已过期。")
        EmailAuthMessageView(kind: .success, message: "验证码已发送。")
        EmailAuthMessageView(kind: .note, message: "登录后会同步你的资料库。")
    }
    .padding()
}
