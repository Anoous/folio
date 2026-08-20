import SwiftUI

struct WelcomeAuthMessageView: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "info.circle")
            .font(.footnote)
            .foregroundStyle(FolioPalette.inkGreenDeep)
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FolioPalette.subtleGreen, in: .rect(cornerRadius: 10))
            .accessibilityIdentifier("welcome-auth-message")
    }
}
