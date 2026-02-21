import SwiftUI
import UserNotifications

struct PermissionView: View {
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            VStack(spacing: Spacing.md) {
                Text(String(localized: "permission.title", defaultValue: "Folio needs permission to serve you better:"))
                    .font(Typography.listTitle)
                    .foregroundStyle(Color.folio.textPrimary)
                    .multilineTextAlignment(.center)

                HStack(spacing: Spacing.sm) {
                    Image(systemName: "bell.fill")
                        .font(.title2)
                        .foregroundStyle(Color.folio.accent)
                        .frame(width: 44)

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(String(localized: "permission.notification.title", defaultValue: "Notifications"))
                            .font(Typography.listTitle)
                            .foregroundStyle(Color.folio.textPrimary)
                        Text(String(localized: "permission.notification.description", defaultValue: "Get notified when articles are ready"))
                            .font(Typography.caption)
                            .foregroundStyle(Color.folio.textSecondary)
                    }

                    Spacer()

                    Button(String(localized: "permission.allow", defaultValue: "Allow")) {
                        requestNotificationPermission()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(Spacing.md)
                .background(Color.folio.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            }
            .padding(.horizontal, Spacing.xl)

            Text(String(localized: "permission.disclaimer", defaultValue: "Notifications are only used for article status. No marketing messages."))
                .font(Typography.caption)
                .foregroundStyle(Color.folio.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)

            Spacer()

            FolioButton(title: String(localized: "permission.start", defaultValue: "Get Started"), style: .primary) {
                onComplete()
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.xl)
        }
        .background(Color.folio.background)
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }
}

#Preview {
    PermissionView(onComplete: {})
}
