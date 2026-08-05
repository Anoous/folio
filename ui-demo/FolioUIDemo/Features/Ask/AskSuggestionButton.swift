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
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)

                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
