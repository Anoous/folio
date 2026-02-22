import SwiftUI

struct SettingsView: View {
    @Environment(AuthViewModel.self) private var authViewModel: AuthViewModel?
    @Environment(OfflineQueueManager.self) private var offlineQueueManager: OfflineQueueManager?

    var body: some View {
        List {
            userProfileSection
            syncStatusSection
            quotaSection
            appInfoSection
            accountActionsSection
            #if DEBUG
            devToolsSection
            #endif
        }
        .navigationTitle(String(localized: "tab.settings"))
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

                        Text(user.subscription.capitalized)
                            .font(Typography.tag)
                            .foregroundStyle(Color.folio.accent)
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
                            Text(String(localized: "settings.signInBenefits", defaultValue: "Sign in to sync, AI processing, and more"))
                                .font(Typography.caption)
                                .foregroundStyle(Color.folio.textTertiary)
                        }
                    }
                }
                .padding(.vertical, Spacing.xs)
            }
        }
    }

    // MARK: - Sync Status

    @ViewBuilder
    private var syncStatusSection: some View {
        Section(String(localized: "settings.sync", defaultValue: "Sync")) {
            HStack {
                Label {
                    Text(String(localized: "settings.network", defaultValue: "Network"))
                } icon: {
                    Image(systemName: offlineQueueManager?.isNetworkAvailable == true ? "wifi" : "wifi.slash")
                        .foregroundStyle(offlineQueueManager?.isNetworkAvailable == true ? .green : .red)
                }

                Spacer()

                Text(offlineQueueManager?.isNetworkAvailable == true
                     ? String(localized: "settings.connected", defaultValue: "Connected")
                     : String(localized: "settings.offline", defaultValue: "Offline"))
                    .font(Typography.caption)
                    .foregroundStyle(Color.folio.textSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(offlineQueueManager?.isNetworkAvailable == true
                ? String(localized: "settings.a11y.networkConnected", defaultValue: "Network: Connected")
                : String(localized: "settings.a11y.networkOffline", defaultValue: "Network: Offline"))

            HStack {
                Label {
                    Text(String(localized: "settings.pending", defaultValue: "Pending Articles"))
                } icon: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(Color.folio.accent)
                }

                Spacer()

                Text("\(offlineQueueManager?.pendingCount ?? 0)")
                    .font(Typography.caption)
                    .foregroundStyle(Color.folio.textSecondary)
            }
        }
    }

    // MARK: - Quota

    @ViewBuilder
    private var quotaSection: some View {
        if let user = authViewModel?.currentUser {
            Section(String(localized: "settings.quota", defaultValue: "Monthly Quota")) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack {
                        Text(String(localized: "settings.articlesUsed", defaultValue: "Articles saved"))
                            .font(Typography.body)
                        Spacer()
                        Text("\(user.currentMonthCount) / \(user.monthlyQuota)")
                            .font(Typography.caption)
                            .foregroundStyle(Color.folio.textSecondary)
                    }

                    ProgressView(
                        value: Double(user.currentMonthCount),
                        total: Double(max(user.monthlyQuota, 1))
                    )
                    .tint(quotaColor(used: user.currentMonthCount, total: user.monthlyQuota))
                }
            }
        }
    }

    private func quotaColor(used: Int, total: Int) -> Color {
        let ratio = Double(used) / Double(max(total, 1))
        if ratio >= 0.9 { return .red }
        if ratio >= 0.7 { return .orange }
        return Color.folio.accent
    }

    // MARK: - App Info

    private var appInfoSection: some View {
        Section(String(localized: "settings.about", defaultValue: "About")) {
            HStack {
                Text(String(localized: "settings.version", defaultValue: "Version"))
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    .foregroundStyle(Color.folio.textSecondary)
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
                UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
            }
        }
    }
    #endif
}
