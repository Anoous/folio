import SwiftUI

struct FolioPageMascot: View {
    var size = 34.0

    var body: some View {
        ZStack {
            Image(systemName: "doc.fill")
                .font(.system(size: size + 3, weight: .regular))
                .foregroundStyle(FolioPalette.inkGreenDeep)

            Image(systemName: "doc.fill")
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(FolioPalette.surface)

            HStack(spacing: 4) {
                Circle()
                    .frame(width: 2.8, height: 2.8)
                Circle()
                    .frame(width: 2.8, height: 2.8)
            }
            .foregroundStyle(FolioPalette.inkGreenDeep)
            .offset(x: -1, y: 4)
        }
        .frame(width: size + 8, height: size + 8)
        .accessibilityHidden(true)
    }
}

#Preview {
    FolioPageMascot(size: 38)
        .padding()
        .background(FolioPalette.canvas)
}
