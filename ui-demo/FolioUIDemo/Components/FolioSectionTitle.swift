import SwiftUI

struct FolioSectionTitle: View {
    let title: String
    var font = FolioTypography.editorial(18, relativeTo: .headline)
    var foregroundStyle = FolioPalette.inkGreenDeep

    var body: some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 1)
                .fill(FolioPalette.inkGreen)
                .frame(width: 2, height: 20)
            Text(title)
                .font(font)
                .foregroundStyle(foregroundStyle)
        }
    }
}
