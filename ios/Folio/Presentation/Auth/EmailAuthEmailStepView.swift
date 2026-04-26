import SwiftUI

struct EmailAuthEmailStepView: View {
    @Binding var form: EmailAuthFormState
    let isLoading: Bool
    let onSendCode: () -> Void

    @FocusState private var isEmailFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Label("邮箱地址", systemImage: "envelope")
                    .font(Typography.caption)
                    .foregroundStyle(Color.folio.textSecondary)

                ZStack(alignment: .leading) {
                    if form.email.isEmpty {
                        Text(verbatim: "name@example.com")
                            .font(Typography.body)
                            .foregroundStyle(Color.folio.textTertiary)
                            .padding(.horizontal, Spacing.md)
                            .allowsHitTesting(false)
                    }

                    TextField("", text: $form.email)
                        .font(Typography.body)
                        .foregroundStyle(Color.folio.textPrimary)
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
                .frame(minHeight: 52)
                .background(Color.folio.background)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                .overlay {
                    RoundedRectangle(cornerRadius: CornerRadius.medium)
                        .stroke(fieldBorderColor, lineWidth: 1)
                }
            }

            HStack(alignment: .top, spacing: Spacing.xs) {
                Image(systemName: helperIconName)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(helperColor)
                    .frame(width: 18)
                    .accessibilityHidden(true)

                Text(form.emailFieldMessage)
                    .font(Typography.caption)
                    .foregroundStyle(helperColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            EmailAuthActionButton(
                title: isLoading ? "正在发送" : "发送验证码",
                systemImage: "paperplane.fill",
                isLoading: isLoading,
                isDisabled: !form.canSendCode,
                action: onSendCode
            )
        }
        .padding(Spacing.md)
        .background(Color.folio.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.large)
                .stroke(Color.folio.separator.opacity(0.7), lineWidth: 1)
        }
    }

    private var fieldBorderColor: Color {
        if form.normalizedEmail.isEmpty || form.isEmailValid {
            return isEmailFocused ? Color.folio.accent : Color.folio.separator
        }

        return Color.folio.error.opacity(0.65)
    }

    private var helperIconName: String {
        form.normalizedEmail.isEmpty || form.isEmailValid ? "lock.fill" : "exclamationmark.circle.fill"
    }

    private var helperColor: Color {
        if form.normalizedEmail.isEmpty {
            return Color.folio.textTertiary
        }

        return form.isEmailValid ? Color.folio.textSecondary : Color.folio.error
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
        .background(Color.folio.background)
}
