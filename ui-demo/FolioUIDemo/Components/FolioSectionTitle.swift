import SwiftUI

struct FolioSectionTitle: View {
    let title: String

    var body: some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 1)
                .fill(FolioPalette.inkGreen)
                .frame(width: 2, height: 20)
            Text(title)
                .font(FolioTypography.editorial(18, relativeTo: .headline))
                .foregroundStyle(FolioPalette.inkGreenDeep)
        }
    }
}
