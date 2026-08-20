import SwiftUI

struct DeviceSessionsView: View {
    @Bindable var store: DemoStore
    let onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    FolioBackButton(action: onBack)
                    Spacer()
                    Text("已登录设备")
                        .font(FolioTypography.editorialBold(24, relativeTo: .title2))
                        .foregroundStyle(FolioPalette.inkGreenDeep)
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.top, 13)

                Text("撤销设备后，它的下一次请求会立即失效；当前设备只能通过退出登录结束会话。")
                    .font(FolioTypography.editorial(15, relativeTo: .body))
                    .foregroundStyle(FolioPalette.secondaryText)
                    .lineSpacing(5)
                    .padding(.top, 24)

                VStack(spacing: 0) {
                    ForEach(store.deviceSessions) { session in
                        DeviceSessionRow(
                            session: session,
                            onRevoke: { store.revokeDevice(session) }
                        )
                    }
                }
                .padding(.horizontal, 14)
                .background(FolioPalette.surface)
                .clipShape(.rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(FolioPalette.paperLine, lineWidth: 0.8)
                }
                .padding(.top, 24)
            }
            .padding(.horizontal, FolioMetrics.pageInset)
        }
        .scrollIndicators(.hidden)
        .background(FolioPalette.canvas)
        .toolbar(.hidden, for: .navigationBar)
    }
}
