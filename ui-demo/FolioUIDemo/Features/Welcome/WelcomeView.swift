import SwiftUI

struct WelcomeView: View {
    let onAppleLogin: () -> Void
    let onEmailLogin: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 70)

                Text("Folio")
                    .font(FolioTypography.wordmark(66))
                    .foregroundStyle(FolioPalette.inkGreenDeep)

                Text(.welcomeHeadline)
                    .font(FolioTypography.editorialBold(27, relativeTo: .title))
                    .foregroundStyle(FolioPalette.inkGreenDeep)
                    .padding(.top, 29)
                    .accessibilityIdentifier("welcome.headline")

                Text(.welcomeValueProposition)
                    .font(FolioTypography.editorial(17, relativeTo: .body))
                    .foregroundStyle(.primary)
                    .lineSpacing(7)
                    .padding(.top, 21)
                    .accessibilityIdentifier("welcome.valueProposition")

                Image(.onboardingEditorial)
                    .resizable()
                    .scaledToFit()
                    .accessibilityHidden(true)
                    .frame(maxWidth: .infinity)
                    .frame(height: 242)
                    .padding(.horizontal, -40)
                    .padding(.top, 2)

                WelcomeLoginButtons(
                    onAppleLogin: onAppleLogin,
                    onEmailLogin: onEmailLogin
                )
                .padding(.top, 8)

                Text(.welcomePrivacy)
                    .font(FolioTypography.editorial(14, relativeTo: .footnote))
                    .foregroundStyle(FolioPalette.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 22)
                    .padding(.bottom, 25)
                    .accessibilityIdentifier("welcome.privacy")
            }
            .padding(.horizontal, 48)
        }
        .scrollIndicators(.hidden)
        .background(FolioPalette.canvas)
    }
}
