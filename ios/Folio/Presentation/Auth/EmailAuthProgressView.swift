import SwiftUI

struct EmailAuthProgressView: View {
    let step: EmailAuthStep

    var body: some View {
        HStack(spacing: Spacing.xs) {
            progressItem(title: "邮箱", systemImage: "at", isActive: true)
            progressConnector(isActive: step == .code)
            progressItem(title: "验证码", systemImage: "number", isActive: step == .code)
            progressConnector(isActive: false)
            progressItem(title: "同步", systemImage: "checkmark", isActive: false)
        }
        .padding(Spacing.sm)
        .background(Color.folio.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.large)
                .stroke(Color.folio.separator.opacity(0.7), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(step == .email ? "第 1 步，共 3 步，输入邮箱" : "第 2 步，共 3 步，输入验证码")
    }

    private func progressItem(title: String, systemImage: String, isActive: Bool) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
            Text(title)
                .font(Typography.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(isActive ? Color.folio.textPrimary : Color.folio.textTertiary)
        .frame(maxWidth: .infinity, minHeight: 34)
        .background(isActive ? Color.folio.echoBg : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
    }

    private func progressConnector(isActive: Bool) -> some View {
        Rectangle()
            .fill(isActive ? Color.folio.accent : Color.folio.separator)
            .frame(width: 12, height: 1)
            .accessibilityHidden(true)
    }
}

#Preview {
    EmailAuthProgressView(step: .code)
        .padding()
}
