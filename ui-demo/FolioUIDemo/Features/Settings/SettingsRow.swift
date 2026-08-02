import SwiftUI

struct SettingsRow: View {
    let symbol: String
    let title: String
    let value: String
    var tint = FolioPalette.inkGreenDeep
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 15) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(tint)
                    .frame(width: 28)

                Text(title)
                    .font(FolioTypography.editorial(16, relativeTo: .body))
                    .foregroundStyle(tint == FolioPalette.danger ? FolioPalette.danger : .primary)

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
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottomTrailing) {
            Rectangle()
                .fill(FolioPalette.paperLine)
                .frame(height: 0.5)
                .padding(.leading, 43)
        }
    }
}
