import SwiftUI

struct EmailAuthEmailStepView: View {
    @Binding var form: EmailAuthFormState
    let isLoading: Bool
    let onSendCode: () -> Void

    @FocusState private var isEmailFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            ZStack(alignment: .leading) {
                if form.email.isEmpty {
                    Text(verbatim: "邮箱地址")
                        .font(Typography.body)
                        .foregroundStyle(FolioPaperPalette.tertiaryText)
                        .padding(.horizontal, Spacing.md)
                        .allowsHitTesting(false)
                }

                TextField("", text: $form.email)
                    .font(Typography.body)
                    .foregroundStyle(FolioPaperPalette.primaryText)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.continue)
                    .focused($isEmailFocused)
                    .padding(.horizontal, Spacing.md)
                    .onSubmit(onSendCode)
                    .disabled(isLoading)
                    .accessibilityLabel("邮箱地址")
            }
            .frame(minHeight: 54)
            .background(FolioPaperPalette.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            .overlay {
                RoundedRectangle(cornerRadius: CornerRadius.medium)
                    .stroke(fieldBorderColor, lineWidth: 1)
            }

            if let message = form.emailValidationMessage {
                Text(message)
                    .font(Typography.caption)
                    .foregroundStyle(Color.folio.error)
                    .fixedSize(horizontal: false, vertical: true)
            }

            EmailAuthActionButton(
                title: isLoading ? "正在发送" : "继续",
                isLoading: isLoading,
                isDisabled: !form.canSendCode,
                action: onSendCode
            )
        }
    }

    private var fieldBorderColor: Color {
        if form.normalizedEmail.isEmpty || form.isEmailValid {
            return isEmailFocused ? FolioPaperPalette.accentBlue : FolioPaperPalette.listDivider
        }

        return Color.folio.error.opacity(0.65)
    }
}

#Preview {
    EmailAuthEmailStepView(
        form: .constant({
            var form = EmailAuthFormState()
            form.email = "reader@example.com"
            return form
        }()),
        isLoading: false
    ) {}
        .padding()
        .background(FolioPaperPalette.background)
}
