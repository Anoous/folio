import SwiftUI

struct AskSuggestionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(FolioTypography.editorial(14, relativeTo: .body))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(FolioPalette.secondaryText)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 51)
            .background(FolioPalette.surface)
            .clipShape(.rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(FolioPalette.paperLine, lineWidth: 0.8)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
