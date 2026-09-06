import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @Environment(AuthViewModel.self) private var authViewModel: AuthViewModel?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            Image(systemName: "book.pages")
                .font(.system(size: 64))
                .foregroundStyle(FolioPaperPalette.accentBlue)

            VStack(spacing: Spacing.xs) {
                Text(String(localized: "signin.title", defaultValue: "Sign in to Folio"))
                    .font(Typography.navTitle)
                    .foregroundStyle(FolioPaperPalette.primaryText)

                Text(String(localized: "signin.subtitle", defaultValue: "Enable cloud sync and AI processing"))
                    .font(Typography.body)
                    .foregroundStyle(FolioPaperPalette.secondaryText)
                    .multilineTextAlignment(.center)
            }

            // Benefits list
            VStack(alignment: .leading, spacing: Spacing.sm) {
                benefitRow(icon: "icloud", text: String(localized: "signin.benefit.sync", defaultValue: "Sync articles across devices"))
                benefitRow(icon: "sparkles", text: String(localized: "signin.benefit.ai", defaultValue: "AI auto-classification and tagging"))
                benefitRow(icon: "arrow.down.doc", text: String(localized: "signin.benefit.content", defaultValue: "Full content extraction"))
            }
            .padding(.horizontal, Spacing.lg)

            Spacer()

            VStack(spacing: Spacing.sm) {
                if authViewModel?.isLoading == true {
                    ProgressView()
                        .frame(height: 50)
                } else {
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
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                }

                // 分隔线
                HStack {
                    Rectangle()
                        .frame(height: 1)
                        .foregroundStyle(FolioPaperPalette.listDivider)
                    Text(String(localized: "signin.or", defaultValue: "or"))
                        .font(Typography.caption)
                        .foregroundStyle(FolioPaperPalette.tertiaryText)
                    Rectangle()
                        .frame(height: 1)
                        .foregroundStyle(FolioPaperPalette.listDivider)
                }

                NavigationLink {
                    EmailAuthView()
                } label: {
                    HStack {
                        Image(systemName: "envelope")
                        Text(String(localized: "signin.emailLogin", defaultValue: "Sign in with Email"))
                    }
                    .font(Typography.listTitle)
                    .foregroundStyle(FolioPaperPalette.primaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(FolioPaperPalette.cardSurface)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                    .overlay {
                        RoundedRectangle(cornerRadius: CornerRadius.medium)
                            .stroke(FolioPaperPalette.listDivider.opacity(0.6), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)

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
        .background(FolioPaperPalette.background.ignoresSafeArea())
        .navigationTitle(String(localized: "signin.navTitle", defaultValue: "Sign In"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            dismissIfSignedIn(authViewModel?.isAuthenticated)
        }
        .onChange(of: authViewModel?.isAuthenticated) { _, isAuthenticated in
            dismissIfSignedIn(isAuthenticated)
        }
    }

    private func benefitRow(icon: String, text: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(FolioPaperPalette.accentBlue)
                .frame(width: 28)
            Text(text)
                .font(Typography.body)
                .foregroundStyle(FolioPaperPalette.secondaryText)
        }
    }

    private func dismissIfSignedIn(_ isAuthenticated: Bool?) {
        guard AuthNavigationPolicy.shouldDismissSignIn(isAuthenticated: isAuthenticated) else { return }
        dismiss()
    }
}

#Preview {
    NavigationStack {
        SignInView()
    }
}
