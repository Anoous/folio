import SwiftUI

struct ShareArticleCard: View {
    var body: some View {
        HStack(spacing: 19) {
            FolioBrandIcon(monogram: "e", size: 48)
            VStack(alignment: .leading, spacing: 6) {
                Text("如何设计可信的 AI 产品")
                    .font(FolioTypography.editorial(19, relativeTo: .headline))
                Text("example.com")
                    .font(.system(size: 15))
                    .foregroundStyle(FolioPalette.secondaryText)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 83)
        .background(FolioPalette.surface)
        .clipShape(.rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(FolioPalette.paperLine, lineWidth: 0.8)
        }
    }
}
