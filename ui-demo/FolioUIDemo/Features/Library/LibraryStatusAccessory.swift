import SwiftUI

struct LibraryStatusAccessory: View {
    let status: DemoArticleStatus

    var body: some View {
        switch status {
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(FolioPalette.inkGreenDeep)
                .accessibilityLabel("已完成")
        case .processing:
            Text("处理中")
                .font(FolioTypography.editorial(13, relativeTo: .caption))
                .foregroundStyle(FolioPalette.inkGreenDeep)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(FolioPalette.subtleGreen)
                .clipShape(.capsule)
        case .limited:
            Text("受限")
                .font(FolioTypography.editorial(13, relativeTo: .caption))
                .foregroundStyle(FolioPalette.warning)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(FolioPalette.evidence.opacity(0.76))
                .clipShape(.capsule)
        }
    }
}
