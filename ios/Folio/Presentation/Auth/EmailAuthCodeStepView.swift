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
            ZStack {
                if form.code.isEmpty {
                    Text(verbatim: "000000")
                        .font(.system(.title3, design: .monospaced, weight: .semibold))
                        .foregroundStyle(FolioPaperPalette.tertiaryText)
                        .allowsHitTesting(false)
                }

                TextField("", text: $form.code)
                    .font(.system(.title3, design: .monospaced, weight: .semibold))
                    .foregroundStyle(FolioPaperPalette.primaryText)
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
            .background(FolioPaperPalette.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            .overlay {
                RoundedRectangle(cornerRadius: CornerRadius.medium)
                    .stroke(isCodeFocused ? FolioPaperPalette.accentBlue : FolioPaperPalette.listDivider, lineWidth: 1)
            }

            EmailAuthActionButton(
                title: isLoading ? "正在验证" : "登录",
                isLoading: isLoading,
                isDisabled: !form.canVerifyCode,
                action: onVerify
            )

            HStack(spacing: Spacing.sm) {
                Button(action: onResend) {
                    Text(resendTitle)
                }
                .font(Typography.caption)
                .disabled(form.cooldownRemaining > 0 || isLoading)

                Spacer(minLength: Spacing.sm)

                Button("换一个邮箱", action: onChangeEmail)
                    .font(Typography.caption)
                    .disabled(isLoading)
            }
            .foregroundStyle(FolioPaperPalette.secondaryText)
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
    .background(FolioPaperPalette.background)
}
