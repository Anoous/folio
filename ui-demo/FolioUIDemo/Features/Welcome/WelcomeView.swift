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

                Text("保存你不想忘记的内容")
                    .font(FolioTypography.editorialBold(27, relativeTo: .title))
                    .foregroundStyle(FolioPalette.inkGreenDeep)
                    .padding(.top, 29)

                Text("Folio 会提炼有出处的洞察，并只根据\n你的资料回答问题。资料不足时，\n会明确说明。")
                    .font(FolioTypography.editorial(17, relativeTo: .body))
                    .foregroundStyle(.primary)
                    .lineSpacing(7)
                    .padding(.top, 21)

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

                Text("内容保存在你的个人云端资料库中，\n你可以随时删除。")
                    .font(FolioTypography.editorial(14, relativeTo: .footnote))
                    .foregroundStyle(FolioPalette.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 22)
                    .padding(.bottom, 25)
            }
            .padding(.horizontal, 48)
        }
        .scrollIndicators(.hidden)
        .background(FolioPalette.canvas)
    }
}
