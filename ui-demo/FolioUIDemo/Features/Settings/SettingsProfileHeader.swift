import SwiftUI

struct SettingsProfileHeader: View {
    let email: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                FolioAvatar(size: 58)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Folio 用户")
                        .font(FolioTypography.editorial(20, relativeTo: .headline))
                    Text(email)
                        .font(.system(size: 14))
                        .foregroundStyle(FolioPalette.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(FolioPalette.tertiaryText)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
