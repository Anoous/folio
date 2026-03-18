import SwiftUI

struct EmailAuthView: View {
    @Environment(AuthViewModel.self) private var authViewModel: AuthViewModel?
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var cooldown = 0

    var body: some View {
        VStack(spacing: Spacing.lg) {
            if !codeSent {
                emailStep
            } else {
                codeStep
            }
        }
        .padding(.horizontal, Spacing.xl)
        .navigationTitle(String(localized: "emailAuth.title", defaultValue: "Email Sign In"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Email Input Step

    private var emailStep: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            Image(systemName: "envelope")
                .font(.system(size: 48))
                .foregroundStyle(Color.folio.accent)

            Text(String(localized: "emailAuth.enterEmail", defaultValue: "Enter your email to sign in or create an account"))
                .font(Typography.body)
                .foregroundStyle(Color.folio.textSecondary)
                .multilineTextAlignment(.center)

            TextField(String(localized: "emailAuth.emailPlaceholder", defaultValue: "Email address"), text: $email)
                .textFieldStyle(.roundedBorder)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if authViewModel?.isLoading == true {
                ProgressView()
                    .frame(height: 50)
            } else {
                Button {
                    Task {
                        await authViewModel?.sendEmailCode(email: email)
                        if authViewModel?.errorMessage == nil {
                            codeSent = true
                            startCooldown()
                        }
                    }
                } label: {
                    Text(String(localized: "emailAuth.sendCode", defaultValue: "Send Code"))
                        .font(Typography.listTitle)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .disabled(email.isEmpty || !email.contains("@"))
            }

            errorView

            Spacer()
        }
    }

    // MARK: - Code Input Step

    private var codeStep: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            Image(systemName: "number.square")
                .font(.system(size: 48))
                .foregroundStyle(Color.folio.accent)

            Text(String(localized: "emailAuth.enterCode", defaultValue: "Enter the 6-digit code sent to"))
                .font(Typography.body)
                .foregroundStyle(Color.folio.textSecondary)

            Text(email)
                .font(Typography.listTitle)
                .foregroundStyle(Color.folio.textPrimary)

            TextField(String(localized: "emailAuth.codePlaceholder", defaultValue: "000000"), text: $code)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 24, weight: .medium, design: .monospaced))

            if authViewModel?.isLoading == true {
                ProgressView()
                    .frame(height: 50)
            } else {
                Button {
                    Task {
                        await authViewModel?.verifyEmailCode(email: email, code: code)
                    }
                } label: {
                    Text(String(localized: "emailAuth.verify", defaultValue: "Verify"))
                        .font(Typography.listTitle)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .disabled(code.count != 6)
            }

            Button {
                if cooldown == 0 {
                    Task {
                        await authViewModel?.sendEmailCode(email: email)
                        if authViewModel?.errorMessage == nil {
                            startCooldown()
                        }
                    }
                }
            } label: {
                if cooldown > 0 {
                    Text("Resend (\(cooldown)s)")
                        .font(Typography.caption)
                        .foregroundStyle(Color.folio.textTertiary)
                } else {
                    Text(String(localized: "emailAuth.resend", defaultValue: "Resend Code"))
                        .font(Typography.caption)
                }
            }
            .disabled(cooldown > 0)

            Button {
                codeSent = false
                code = ""
            } label: {
                Text(String(localized: "emailAuth.changeEmail", defaultValue: "Change Email"))
                    .font(Typography.caption)
            }

            errorView

            Spacer()
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private var errorView: some View {
        if let error = authViewModel?.errorMessage {
            Text(error)
                .font(Typography.caption)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        }
    }

    private func startCooldown() {
        cooldown = 60
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            DispatchQueue.main.async {
                cooldown -= 1
                if cooldown <= 0 {
                    timer.invalidate()
                }
            }
        }
    }
}
