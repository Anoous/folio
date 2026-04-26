import SwiftUI

struct EmailAuthCodeStepView: View {
    @Binding var form: EmailAuthFormState
    let isLoading: Bool
    let onVerify: () -> Void
    let onResend: () -> Void
    let onChangeEmail: () -> Void

    @FocusState private var isCodeFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            EmailAuthMessageView(
                kind: .success,
                message: "验证码已发送到 \(form.normalizedEmail)。如果没有收到，请检查垃圾邮件或稍后重发。"
            )

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Label("6 位验证码", systemImage: "number")
                    .font(Typography.caption)
                    .foregroundStyle(Color.folio.textSecondary)

                ZStack {
                    if form.code.isEmpty {
                        Text(verbatim: "000000")
                            .font(.system(.title3, design: .monospaced, weight: .semibold))
                            .foregroundStyle(Color.folio.textTertiary)
                            .allowsHitTesting(false)
                    }

                    TextField("", text: $form.code)
                        .font(.system(.title3, design: .monospaced, weight: .semibold))
                        .foregroundStyle(Color.folio.textPrimary)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .multilineTextAlignment(.center)
                        .submitLabel(.done)
                        .focused($isCodeFocused)
                        .padding(.horizontal, Spacing.md)
                        .onChange(of: form.code) {
                            form.sanitizeCode()
                        }
                        .onSubmit(onVerify)
                        .disabled(isLoading)
                        .accessibilityLabel("邮箱验证码")
                        .accessibilityValue("\(form.code.count) 位，需 6 位")
                }
                .frame(minHeight: 56)
                .background(Color.folio.background)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                .overlay {
                    RoundedRectangle(cornerRadius: CornerRadius.medium)
                        .stroke(isCodeFocused ? Color.folio.accent : Color.folio.separator, lineWidth: 1)
                }
            }

            EmailAuthActionButton(
                title: isLoading ? "正在验证" : "验证并进入 Folio",
                systemImage: "checkmark.circle.fill",
                isLoading: isLoading,
                isDisabled: !form.canVerifyCode,
                action: onVerify
            )

            HStack(spacing: Spacing.md) {
                Button(action: onResend) {
                    Label(resendTitle, systemImage: "arrow.clockwise")
                        .font(Typography.caption)
                        .lineLimit(1)
                }
                .disabled(form.cooldownRemaining > 0 || isLoading)

                Spacer(minLength: Spacing.sm)

                Button("换一个邮箱", action: onChangeEmail)
                    .font(Typography.caption)
                    .disabled(isLoading)
            }
            .foregroundStyle(Color.folio.link)
        }
        .padding(Spacing.md)
        .background(Color.folio.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.large)
                .stroke(Color.folio.separator.opacity(0.7), lineWidth: 1)
        }
    }

    private var resendTitle: String {
        if form.cooldownRemaining > 0 {
            return "\(form.cooldownRemaining)s 后重发"
        }

        return "重发验证码"
    }
}

#Preview {
    EmailAuthCodeStepView(
        form: .constant({
            var form = EmailAuthFormState()
            form.email = "reader@example.com"
            form.step = .code
            form.cooldownRemaining = 24
            return form
        }()),
        isLoading: false,
        onVerify: {},
        onResend: {},
        onChangeEmail: {}
    )
    .padding()
    .background(Color.folio.background)
}
