import SwiftUI

struct LibraryFilterEmptyView: View {
    let filter: DemoLibraryFilter
    let onClear: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(FolioPalette.tertiaryText)
                .accessibilityHidden(true)

            Text("“\(filter.title)”里还没有内容")
                .font(FolioTypography.editorial(18, relativeTo: .headline))
                .foregroundStyle(FolioPalette.inkGreenDeep)

            Button("显示全部", action: onClear)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FolioPalette.inkGreenDeep)
                .frame(minHeight: FolioMetrics.minimumTapTarget)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 90)
    }
}
