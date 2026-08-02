import SwiftUI

struct AskSourceRow: View {
    let monogram: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                FolioBrandIcon(monogram: monogram, size: 34)
                Text(title)
                    .font(FolioTypography.editorial(15.5, relativeTo: .body))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(FolioPalette.tertiaryText)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 48)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottomTrailing) {
            Rectangle()
                .fill(FolioPalette.paperLine)
                .frame(height: 0.6)
                .padding(.leading, 50)
        }
    }
}
