import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @Environment(AuthViewModel.self) private var authViewModel: AuthViewModel?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            Image(systemName: "book.pages")
                .font(.system(size: 64))
                .foregroundStyle(Color.folio.accent)

            VStack(spacing: Spacing.xs) {
                Text(String(localized: "signin.title", defaultValue: "Sign in to Folio"))
                    .font(Typography.navTitle)
                    .foregroundStyle(Color.folio.textPrimary)

                Text(String(localized: "signin.subtitle", defaultValue: "Enable cloud sync and AI processing"))
                    .font(Typography.body)
                    .foregroundStyle(Color.folio.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(spacing: Spacing.sm) {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.email, .fullName]
                } onCompletion: { result in
                    Task {
                        await authViewModel?.handleAppleSignIn(result: result)
                        if authViewModel?.isAuthenticated == true {
                            dismiss()
                        }
                    }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))

                #if DEBUG
                FolioButton(title: "Dev Login", style: .secondary) {
                    Task {
                        await authViewModel?.loginDev()
                        if authViewModel?.isAuthenticated == true {
                            dismiss()
                        }
                    }
                }
                #endif

                if let error = authViewModel?.errorMessage {
                    Text(error)
                        .font(Typography.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.xl)
        }
        .navigationTitle(String(localized: "signin.navTitle", defaultValue: "Sign In"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        SignInView()
    }
}
