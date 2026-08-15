import SwiftUI

struct AskSuggestionButton: View {
    let symbol: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(FolioPalette.inkGreenDeep)
                    .frame(width: 30, height: 30)
                    .accessibilityHidden(true)

                Text(title)
                    .font(FolioTypography.editorial(17, relativeTo: .body))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.subheadline.bold())
                    .foregroundStyle(FolioPalette.tertiaryText)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity, minHeight: 60)
            .contentShape(.rect)
        }
        .buttonStyle(FolioPressButtonStyle(scalesOnPress: false))
        .accessibilityLabel(title)
        .accessibilityHint("使用此问题提问")
    }
}
