import SwiftUI
import AuthenticationServices

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(AuthViewModel.self) private var authViewModel: AuthViewModel?
    @Environment(\.colorScheme) private var colorScheme
    @State private var currentPage = 0
    let onComplete: () -> Void

    private let pages = [
        OnboardingPageData(
            icon: "book.pages",
            title: "Folio \u{00B7} \u{9875}\u{96C6}",
            subtitle: String(localized: "onboarding.page1.subtitle", defaultValue: "Share links, keep knowledge"),
            description: String(localized: "onboarding.page1.description", defaultValue: "Save articles from any app. Folio auto-organizes with AI.")
        ),
        OnboardingPageData(
            icon: "square.and.arrow.up",
            title: String(localized: "onboarding.page2.title", defaultValue: "Easy to Save"),
            subtitle: String(localized: "onboarding.page2.subtitle", defaultValue: "Safari, WeChat, Twitter..."),
            description: String(localized: "onboarding.page2.description", defaultValue: "Open any app → Share → Choose Folio → Done!")
        ),
        OnboardingPageData(
            icon: "lock.shield",
            title: String(localized: "onboarding.page3.title", defaultValue: "Local-First, Privacy Safe"),
            subtitle: String(localized: "onboarding.page3.subtitle", defaultValue: "Your data stays on your device"),
            description: String(localized: "onboarding.page3.description", defaultValue: "All content is stored locally. Only AI processing uses the cloud.")
        ),
    ]

    var body: some View {
        VStack {
            TabView(selection: $currentPage) {
                ForEach(0..<pages.count, id: \.self) { index in
                    OnboardingPage(data: pages[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            VStack(spacing: Spacing.sm) {
                if currentPage < pages.count - 1 {
                    FolioButton(title: String(localized: "onboarding.continue", defaultValue: "Continue"), style: .primary) {
                        withAnimation {
                            currentPage += 1
                        }
                    }
                } else {
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.email, .fullName]
                    } onCompletion: { result in
                        Task {
                            await authViewModel?.handleAppleSignIn(result: result)
                            if authViewModel?.isAuthenticated == true {
                                completeOnboarding()
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
                                completeOnboarding()
                            }
                        }
                    }
                    #endif

                    Button {
                        completeOnboarding()
                    } label: {
                        Text(String(localized: "onboarding.skip", defaultValue: "Skip for now"))
                            .font(Typography.body)
                            .foregroundStyle(Color.folio.textTertiary)
                    }
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.xl)
        }
        .background(Color.folio.background)
    }

    private func completeOnboarding() {
        hasCompletedOnboarding = true
        onComplete()
    }
}

#Preview {
    OnboardingView(onComplete: {})
}
