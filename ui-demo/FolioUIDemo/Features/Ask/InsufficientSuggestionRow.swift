import SwiftUI

struct InsufficientSuggestionRow: View {
    let symbol: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: symbol)
                    .font(.system(size: 16))
                    .foregroundStyle(FolioPalette.inkGreenDeep)
                    .frame(width: 30, height: 30)
                    .background(FolioPalette.evidence.opacity(0.6))
                    .clipShape(.rect(cornerRadius: 7))

                Text(title)
                    .font(FolioTypography.editorial(12.5, relativeTo: .subheadline))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.88)

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .foregroundStyle(FolioPalette.tertiaryText)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 42)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
