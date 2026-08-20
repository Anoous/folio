import SwiftUI

struct LibraryConnectivityBanner: View {
    let onOpenSettings: () -> Void

    var body: some View {
        Button(action: onOpenSettings) {
            HStack(spacing: 10) {
                Image(systemName: "wifi.slash")
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("当前离线")
                        .font(.subheadline.weight(.semibold))

                    Text("已有资料保持安全，联网后才能收藏和阅读。")
                        .font(.caption)
                        .foregroundStyle(FolioPalette.secondaryText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(FolioPalette.inkGreenDeep)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(FolioPalette.evidence, in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("library-offline-banner")
    }
}
