import SwiftUI

struct FolioBrandIcon: View {
    let monogram: String
    var size = 42.0

    var body: some View {
        Group {
            if monogram == "doc" {
                Image(systemName: "doc.text")
                    .font(.system(size: size * 0.46, weight: .regular))
                    .foregroundStyle(FolioPalette.inkGreen)
                    .frame(width: size, height: size)
                    .background(FolioPalette.evidence.opacity(0.72))
            } else {
                Text(monogram)
                    .font(FolioTypography.wordmark(monogram.count > 1 ? size * 0.40 : size * 0.72))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(
                        LinearGradient(
                            colors: [FolioPalette.inkGreen, FolioPalette.inkGreenDeep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }
        .clipShape(.rect(cornerRadius: size * 0.18))
        .accessibilityHidden(true)
    }
}
