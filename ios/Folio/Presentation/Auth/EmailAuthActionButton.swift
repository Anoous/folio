import SwiftUI

struct EmailAuthActionButton: View {
    let title: String
    let isLoading: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.white)
                }

                Text(title)
                    .font(Typography.listTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(isDisabled && !isLoading ? Color.folio.textTertiary : Color.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(isDisabled && !isLoading ? Color.folio.separator.opacity(0.5) : Color.folio.accent)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isLoading)
        .accessibilityLabel(title)
        .accessibilityHint(isDisabled && !isLoading ? "请先完成当前输入" : "")
    }
}

#Preview {
    VStack {
        EmailAuthActionButton(title: "继续", isLoading: false, isDisabled: false) {}
        EmailAuthActionButton(title: "正在发送", isLoading: true, isDisabled: false) {}
        EmailAuthActionButton(title: "继续", isLoading: false, isDisabled: true) {}
    }
    .padding()
}
