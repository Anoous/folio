import SwiftUI

struct LibraryLoadMoreRow: View {
    let remainingCount: Int
    let action: () -> Void

    var body: some View {
        Button("加载更多（还有 \(remainingCount) 篇）", action: action)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(FolioPalette.inkGreenDeep)
            .frame(maxWidth: .infinity, minHeight: 54)
            .accessibilityIdentifier("library-load-more")
    }
}
