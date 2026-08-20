import SwiftUI

struct AccountDeletionView: View {
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("删除账号")
                    .font(FolioTypography.editorialBold(28, relativeTo: .title))
                    .foregroundStyle(FolioPalette.inkGreenDeep)

                Spacer()

                Button("关闭", systemImage: "xmark", action: dismiss.callAsFunction)
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
            }

            Text("提交后会发生什么")
                .font(.headline)
                .padding(.top, 34)

            VStack(alignment: .leading, spacing: 18) {
                Label("所有设备立即退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                Label("内容立即从资料库和 Ask 中移除", systemImage: "books.vertical")
                Label("7 天撤销期后进入不可逆删除", systemImage: "calendar.badge.clock")
                Label("完成后会发送确认通知", systemImage: "checkmark.seal")
            }
            .font(FolioTypography.editorial(16, relativeTo: .body))
            .foregroundStyle(.primary)
            .padding(.top, 20)

            Text("这是 UI Demo，不会删除任何真实服务器数据。")
                .font(.footnote)
                .foregroundStyle(FolioPalette.secondaryText)
                .padding(.top, 24)

            Spacer()

            Button("进入删除撤销期", role: .destructive, action: confirm)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(FolioPalette.danger, in: .rect(cornerRadius: 12))
                .accessibilityIdentifier("account-delete-confirm")

            Button("保留账号", action: dismiss.callAsFunction)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FolioPalette.inkGreenDeep)
                .frame(maxWidth: .infinity, minHeight: 50)
                .padding(.top, 6)
        }
        .padding(FolioMetrics.pageInset)
        .background(FolioPalette.canvas)
        .presentationDetents([.large])
    }

    private func confirm() {
        dismiss()
        onConfirm()
    }
}
