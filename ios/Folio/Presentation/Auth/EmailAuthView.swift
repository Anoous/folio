import SwiftUI

struct EmailAuthView: View {
    @Environment(AuthViewModel.self) private var authViewModel: AuthViewModel?
    @Environment(\.dismiss) private var dismiss

    @State private var form = EmailAuthFormState()
    @State private var cooldownTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                EmailAuthHeaderView(step: form.step)
                    .padding(.top, Spacing.lg)

                EmailAuthProgressView(step: form.step)

                EmailAuthFormView(
                    form: $form,
                    isLoading: isLoading,
                    onSendCode: sendCode,
                    onVerify: verifyCode,
                    onResend: resendCode,
                    onChangeEmail: changeEmail
                )

                if let errorMessage = authViewModel?.errorMessage {
                    EmailAuthMessageView(kind: .error, message: errorMessage)
                }

                EmailAuthMessageView(
                    kind: .note,
                    message: "我们只用邮箱确认账号身份。免费额度、Pro 状态和同步记录会跟随这个账号。"
                )

                Spacer(minLength: Spacing.xl)
            }
            .padding(.horizontal, Spacing.screenPadding)
        }
        .background(Color.folio.background.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("邮箱验证")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            cooldownTask?.cancel()
        }
    }

    private var isLoading: Bool {
        authViewModel?.isLoading == true
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
