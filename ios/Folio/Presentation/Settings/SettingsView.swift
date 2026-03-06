import SwiftUI

struct SettingsView: View {
    @Environment(AuthViewModel.self) private var authViewModel: AuthViewModel?
    @State private var showUpgradeAlert = false

    var body: some View {
        List {
            userProfileSection
            subscriptionSection
            accountActionsSection
            appInfoSection
            #if DEBUG
            devToolsSection
            #endif
        }
        .navigationTitle(String(localized: "settings.title", defaultValue: "Settings"))
        .alert(
            String(localized: "settings.upgrade.title", defaultValue: "Upgrade to Pro"),
            isPresented: $showUpgradeAlert
        ) {
            Button(String(localized: "settings.upgrade.buy", defaultValue: "Subscribe — $9.99/year")) {
                // Mock — in production this triggers StoreKit
            }
            Button(String(localized: "button.cancel", defaultValue: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "settings.upgrade.message", defaultValue: "Unlimited saves, priority AI processing, and more."))
        }
    }

    // MARK: - Subscription

    private var subscriptionSection: some View {
        Section {
            Button {
                showUpgradeAlert = true
            } label: {
                HStack {
                    Label(String(localized: "settings.upgrade.row", defaultValue: "Upgrade to Pro"), systemImage: "star.fill")
                        .foregroundStyle(Color.folio.accent)
                    Spacer()
                    Text(String(localized: "settings.upgrade.price", defaultValue: "$9.99/yr"))
                        .font(Typography.caption)
                        .foregroundStyle(Color.folio.textTertiary)
                }
            }
        }
    }

    // MARK: - User Profile

    @ViewBuilder
    private var userProfileSection: some View {
        Section {
            if let user = authViewModel?.currentUser {
                HStack(spacing: Spacing.md) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.folio.accent)

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(user.nickname ?? user.email ?? "User")
                            .font(Typography.listTitle)
                            .foregroundStyle(Color.folio.textPrimary)

                        if let email = user.email {
                            Text(email)
                                .font(Typography.caption)
                                .foregroundStyle(Color.folio.textSecondary)
                        }
                    }
                }
                .padding(.vertical, Spacing.xs)
            } else {
                NavigationLink {
                    SignInView()
                } label: {
                    HStack(spacing: Spacing.md) {
                        Image(systemName: "person.circle")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.folio.textTertiary)

                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(String(localized: "settings.notSignedIn", defaultValue: "Not signed in"))
                                .font(Typography.listTitle)
                                .foregroundStyle(Color.folio.textSecondary)
                            Text(String(localized: "settings.signInBenefits", defaultValue: "Sign in to enable AI and sync"))
                                .font(Typography.caption)
                                .foregroundStyle(Color.folio.textTertiary)
                        }
                    }
                }
                .padding(.vertical, Spacing.xs)
            }
        }
    }

    // MARK: - Account Actions

    @ViewBuilder
    private var accountActionsSection: some View {
        Section {
            if authViewModel?.isAuthenticated == true {
                Button(role: .destructive) {
                    authViewModel?.signOut()
                } label: {
                    Label(String(localized: "settings.signOut", defaultValue: "Sign Out"), systemImage: "rectangle.portrait.and.arrow.right")
                }
            } else {
                NavigationLink {
                    SignInView()
                } label: {
                    Label(String(localized: "settings.signIn", defaultValue: "Sign In"), systemImage: "person.badge.plus")
                }
            }
        }
    }

    // MARK: - App Info

    private var appInfoSection: some View {
        Section {
            HStack {
                Text(String(localized: "settings.version", defaultValue: "Version"))
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    .foregroundStyle(Color.folio.textSecondary)
            }
        }
    }

    // MARK: - Dev Tools

    #if DEBUG
    private var devToolsSection: some View {
        Section("Dev Tools") {
            Button("Dev Login") {
                Task { await authViewModel?.loginDev() }
            }

            Button("Clear Keychain") {
                try? KeyChainManager.shared.clearTokens()
                authViewModel?.signOut()
            }

            Button("Reset Onboarding") {
                UserDefaults.standard.set(false, forKey: AppConstants.onboardingCompletedKey)
            }
        }
    }
    #endif
}
