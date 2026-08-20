import SwiftUI

struct SettingsToggleRow: View {
    let symbol: String
    let title: String
    @Binding var isOn: Bool
    var tint = FolioPalette.inkGreenDeep

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 15) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(tint)
                    .frame(width: 28)

                Text(title)
                    .font(FolioTypography.editorial(16, relativeTo: .body))
                    .foregroundStyle(.primary)
            }
        }
        .tint(FolioPalette.inkGreen)
        .frame(minHeight: 53)
        .overlay(alignment: .bottomTrailing) {
            Rectangle()
                .fill(FolioPalette.paperLine)
                .frame(height: 0.5)
                .padding(.leading, 43)
        }
    }
}
