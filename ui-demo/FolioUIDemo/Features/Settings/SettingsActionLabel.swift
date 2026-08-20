import SwiftUI

struct SettingsActionLabel: View {
    let symbol: String
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(tint)
                .frame(width: 28)

            Text(title)
                .font(FolioTypography.editorial(16, relativeTo: .body))
                .foregroundStyle(tint)

            Spacer()

            if !value.isEmpty {
                Text(value)
                    .font(.system(size: 13))
                    .foregroundStyle(FolioPalette.secondaryText)
            }

            Image(systemName: "chevron.right")
                .foregroundStyle(FolioPalette.tertiaryText)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 53)
        .contentShape(.rect)
        .overlay(alignment: .bottomTrailing) {
            Rectangle()
                .fill(FolioPalette.paperLine)
                .frame(height: 0.5)
                .padding(.leading, 43)
        }
    }
}
