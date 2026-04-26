import SwiftUI

struct EmailAuthView: View {
    @Environment(AuthViewModel.self) private var authViewModel: AuthViewModel?
    @Environment(\.dismiss) private var dismiss

    @State private var form = EmailAuthFormState()
    @State private var cooldownTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(title)
                        .font(Typography.pageTitle)
                        .foregroundStyle(Color.folio.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subtitle)
                        .font(Typography.body)
                        .foregroundStyle(Color.folio.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, Spacing.xl)

                VStack(alignment: .leading, spacing: Spacing.md) {
                    EmailAuthFormView(
                        form: $form,
                        isLoading: isLoading,
                        onSendCode: sendCode,
                        onVerify: verifyCode,
                        onResend: resendCode,
                        onChangeEmail: changeEmail
                    )

                    if let errorMessage = authViewModel?.errorMessage {
                        Text(errorMessage)
                            .font(Typography.caption)
                            .foregroundStyle(Color.folio.error)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: Spacing.xl)

                Text("继续即表示使用此邮箱登录或创建账号。")
                    .font(Typography.caption)
                    .foregroundStyle(Color.folio.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, Spacing.screenPadding)
        }
        .background(Color.folio.background.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("邮箱登录")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            cooldownTask?.cancel()
        }
    }

    private var isLoading: Bool {
        authViewModel?.isLoading == true
    }

    private var title: String {
        switch form.step {
        case .email:
            "邮箱登录"
        case .code:
            "输入验证码"
        }
    }

    private var subtitle: String {
        switch form.step {
        case .email:
            "输入邮箱，我们会发送 6 位验证码。"
        case .code:
            "验证码已发送至 \(form.normalizedEmail)。"
        }
    }

    private func sendCode() {
        guard form.canSendCode, !isLoading else { return }
        let email = form.normalizedEmail

        Task { @MainActor in
            await authViewModel?.sendEmailCode(email: email)

            guard authViewModel?.errorMessage == nil else { return }

            form.email = email
            form.moveToCodeStep()
            startCooldown()
        }
    }

    private func verifyCode() {
        guard form.canVerifyCode, !isLoading else { return }
        let email = form.normalizedEmail
        let code = form.code

        Task { @MainActor in
            await authViewModel?.verifyEmailCode(email: email, code: code)
            if authViewModel?.isAuthenticated == true {
                dismiss()
            }
        }
    }

    private func resendCode() {
        guard form.cooldownRemaining == 0, form.isEmailValid, !isLoading else { return }
        let email = form.normalizedEmail

        Task { @MainActor in
            await authViewModel?.sendEmailCode(email: email)

            guard authViewModel?.errorMessage == nil else { return }

            form.startCooldown()
            startCooldown()
        }
    }

    private func changeEmail() {
        cooldownTask?.cancel()
        form.resetToEmailStep()
    }

    private func startCooldown() {
        cooldownTask?.cancel()
        cooldownTask = Task { @MainActor in
            while !Task.isCancelled && form.cooldownRemaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                form.tickCooldown()
            }
        }
    }
}

#Preview {
    NavigationStack {
        EmailAuthView()
            .environment(AuthViewModel())
    }
}
