import SwiftUI

struct HomeOfflineBannerView: View {
    var body: some View {
        Label(
            "离线中，新增和修改会在联网后同步。",
            systemImage: "wifi.slash"
        )
        .font(Typography.caption)
        .foregroundStyle(Color.folio.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.vertical, Spacing.xs)
    }
}
