import SwiftUI

struct LibraryEmptyStateView: View {
    let onBeginSaving: () -> Void
    let onShowShareDemo: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(FolioPalette.inkGreenDeep)
                .frame(width: 88, height: 88)
                .background(FolioPalette.subtleGreen, in: .circle)
                .accessibilityHidden(true)

            Text("从第一篇开始")
                .font(FolioTypography.editorialBold(25, relativeTo: .title2))
                .foregroundStyle(FolioPalette.inkGreenDeep)
                .padding(.top, 24)

            Text("看到值得留下的网页时，从其他 App 分享到 Folio；也可以先在这里粘贴一个链接。")
                .font(FolioTypography.editorial(16, relativeTo: .body))
                .foregroundStyle(FolioPalette.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .padding(.top, 12)
                .frame(maxWidth: 310)

            Button("收藏第一篇", systemImage: "plus", action: onBeginSaving)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(FolioPalette.inkGreenDeep, in: .rect(cornerRadius: 12))
                .padding(.top, 28)
                .accessibilityIdentifier("library-first-save")

            Button("预览从其他 App 分享", systemImage: "square.and.arrow.up", action: onShowShareDemo)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(FolioPalette.inkGreenDeep)
                .frame(minHeight: FolioMetrics.minimumTapTarget)
                .padding(.top, 8)
        }
        .padding(.horizontal, 30)
        .padding(.top, 74)
    }
}
