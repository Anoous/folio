import SwiftUI

struct LibraryStatusAccessory: View {
    let status: DemoArticleStatus

    var body: some View {
        if status == .processing {
            Text("处理中")
                .font(FolioTypography.editorial(13, relativeTo: .caption))
                .foregroundStyle(FolioPalette.inkGreenDeep)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(FolioPalette.subtleGreen)
                .clipShape(.capsule)
        }
    }
}
