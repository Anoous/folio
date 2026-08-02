import SwiftUI

struct WelcomeLoginButtons: View {
    let onAppleLogin: () -> Void
    let onEmailLogin: () -> Void

    var body: some View {
        VStack(spacing: 13) {
            Button(action: onAppleLogin) {
                Label("使用 Apple 登录", systemImage: "apple.logo")
                    .font(FolioTypography.editorial(19, relativeTo: .headline))
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .foregroundStyle(.white)
                    .background(FolioPalette.inkGreenDeep)
                    .clipShape(.rect(cornerRadius: 9))
            }
            .buttonStyle(.plain)

            Button("使用邮箱登录", action: onEmailLogin)
                .font(FolioTypography.editorial(19, relativeTo: .headline))
                .foregroundStyle(FolioPalette.inkGreenDeep)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(FolioPalette.surface)
                .clipShape(.rect(cornerRadius: 9))
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(FolioPalette.inkGreenDeep, lineWidth: 1)
                }
        }
    }
}
