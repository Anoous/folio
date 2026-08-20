import SwiftUI

struct EmailSignInView: View {
    let onAuthenticated: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var stage = EmailSignInStage.email
    @State private var email = ""
    @State private var code = ""
    @FocusState private var focusedField: EmailSignInStage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(stage == .email ? "邮箱登录" : "输入验证码")
                    .font(FolioTypography.editorialBold(28, relativeTo: .title))
                    .foregroundStyle(FolioPalette.inkGreenDeep)

                Spacer()

                Button("关闭", systemImage: "xmark", action: dismiss.callAsFunction)
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
            }

            Text(helperText)
                .font(FolioTypography.editorial(16, relativeTo: .body))
                .foregroundStyle(FolioPalette.secondaryText)
                .lineSpacing(5)
                .padding(.top, 18)

            if stage == .email {
                TextField("name@example.com", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .email)
                    .accessibilityIdentifier("email-sign-in-address")
                    .padding(.horizontal, 16)
                    .frame(minHeight: 54)
                    .background(FolioPalette.surface, in: .rect(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(FolioPalette.paperLine, lineWidth: 0.8)
                    }
                    .padding(.top, 28)
            } else {
                TextField("6 位验证码", text: $code)
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: .verification)
                    .accessibilityIdentifier("email-sign-in-code")
                    .padding(.horizontal, 16)
                    .frame(minHeight: 54)
                    .background(FolioPalette.surface, in: .rect(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(FolioPalette.paperLine, lineWidth: 0.8)
                    }
                    .padding(.top, 28)

                Button("重新发送验证码", action: resendCode)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(FolioPalette.inkGreenDeep)
                    .frame(minHeight: FolioMetrics.minimumTapTarget)
                    .padding(.top, 8)
            }

            Spacer()

            Button(primaryTitle, action: advance)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(
                    canAdvance ? FolioPalette.inkGreenDeep : FolioPalette.tertiaryText.opacity(0.4),
                    in: .rect(cornerRadius: 12)
                )
                .disabled(!canAdvance)
                .accessibilityIdentifier("email-sign-in-continue")
        }
        .padding(FolioMetrics.pageInset)
        .background(FolioPalette.canvas)
        .presentationDetents([.medium])
        .task {
            focusedField = .email
        }
    }

    private var helperText: String {
        switch stage {
        case .email:
            "我们会发送一次性验证码。登录后会恢复同一份云端资料库。"
        case .verification:
            "验证码已发送到 \(email)。在 Demo 中输入任意 6 位数字即可继续。"
        }
    }

    private var primaryTitle: String {
        stage == .email ? "发送验证码" : "登录并恢复资料库"
    }

    private var canAdvance: Bool {
        switch stage {
        case .email:
            email.contains("@") && email.contains(".")
        case .verification:
            code.count == 6 && code.allSatisfy(\.isNumber)
        }
    }

    private func advance() {
        switch stage {
        case .email:
            stage = .verification
            focusedField = .verification
        case .verification:
            let authenticatedEmail = email
            dismiss()
            onAuthenticated(authenticatedEmail)
        }
    }

    private func resendCode() {
        code = ""
        focusedField = .verification
    }
}
