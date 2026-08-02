import SwiftUI

struct InsightPointRow: View {
    let number: Int
    let text: String
    let citation: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            Text(number, format: .number)
                .font(.system(size: 15, weight: .medium, design: .serif))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(FolioPalette.inkGreenDeep)
                .clipShape(.circle)

            Button(action: action) {
                Text("\(Text(text).foregroundStyle(.primary)) \(Text(citation).foregroundStyle(FolioPalette.inkGreenDeep))")
                    .font(FolioTypography.editorial(13, relativeTo: .body))
                    .lineSpacing(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("查看原文证据")
        }
    }
}
