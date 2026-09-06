import SwiftUI

struct OnboardingPageData {
    let icon: String
    let title: String
    let subtitle: String
    let description: String
}

struct OnboardingPage: View {
    let data: OnboardingPageData

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            Image(systemName: data.icon)
                .font(.system(size: 64))
                .foregroundStyle(Color.folio.accent)

            VStack(spacing: Spacing.sm) {
                Text(data.title)
                    .font(Typography.pageTitle)
                    .foregroundStyle(Color.folio.textPrimary)

                Text(data.subtitle)
                    .font(Typography.listTitle)
                    .foregroundStyle(Color.folio.textSecondary)

                Text(data.description)
                    .font(Typography.body)
                    .foregroundStyle(Color.folio.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xl)
            }

            Spacer()
            Spacer()
        }
    }
}
