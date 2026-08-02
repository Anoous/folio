import SwiftUI

struct SettingsView: View {
    let onBack: () -> Void
    let onShowShareSuccess: () -> Void
    @State private var showsDeleteConfirmation = false
    @State private var activeNotice: DemoNotice?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    FolioBackButton(action: onBack)
                    Spacer()
                    Text("设置")
                        .font(FolioTypography.editorialBold(24, relativeTo: .title2))
                        .foregroundStyle(FolioPalette.inkGreenDeep)
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.top, 13)

                SettingsProfileHeader(action: showProfile)
                    .padding(.top, 26)

                SettingsSectionLabel(title: "账号")
                    .padding(.top, 28)
                SettingsCard {
                    SettingsRow(symbol: "envelope", title: "邮箱", value: "user@example.com", action: showEmail)
                    SettingsRow(symbol: "desktopcomputer", title: "已登录设备", value: "2 台设备", action: showDevices)
                }

                SettingsSectionLabel(title: "云端空间")
                    .padding(.top, 24)
                SettingsStorageCard(action: showStorage)

                SettingsSectionLabel(title: "订阅")
                    .padding(.top, 24)
                SettingsCard {
                    SettingsRow(symbol: "crown", title: "当前方案", value: "Free", action: showPlan)
                    SettingsRow(symbol: "star.circle.fill", title: "查看 Pro", value: "", action: showPro)
                }

                SettingsSectionLabel(title: "数据与隐私")
                    .padding(.top, 24)
                SettingsCard {
                    SettingsRow(symbol: "trash", title: "删除内容", value: "", tint: FolioPalette.danger, action: showDeleteConfirmation)
                    SettingsRow(symbol: "person.crop.circle.badge.xmark", title: "删除账号", value: "", tint: FolioPalette.danger, action: showDeleteConfirmation)
                }

                SettingsSectionLabel(title: "帮助")
                    .padding(.top, 24)
                SettingsCard {
                    SettingsRow(symbol: "shield", title: "Folio 如何处理内容", value: "", action: showContentPolicy)
                        .contextMenu {
                            Button("查看分享保存演示", systemImage: "square.and.arrow.down", action: onShowShareSuccess)
                        }
                    SettingsRow(symbol: "questionmark.circle", title: "联系支持", value: "", action: showSupport)
                }
                .padding(.bottom, 35)
            }
            .padding(.horizontal, FolioMetrics.pageInset)
        }
        .scrollIndicators(.hidden)
        .background(FolioPalette.canvas)
        .confirmationDialog("确认删除", isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
            Button("删除", role: .destructive, action: confirmMockDeletion)
            Button("取消", role: .cancel, action: dismissDeleteConfirmation)
        } message: {
            Text("这是 UI Demo，不会删除任何真实数据。")
        }
        .alert(item: $activeNotice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("好"))
            )
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func showDeleteConfirmation() {
        showsDeleteConfirmation = true
    }

    private func showProfile() {
        activeNotice = DemoNotice(title: "个人资料", message: "Folio 用户 · user@example.com")
    }

    private func showEmail() {
        activeNotice = DemoNotice(title: "邮箱", message: "当前演示账号为 user@example.com。")
    }

    private func showDevices() {
        activeNotice = DemoNotice(title: "已登录设备", message: "Mock 数据：iPhone 与 Mac，共 2 台设备。")
    }

    private func showStorage() {
        activeNotice = DemoNotice(title: "云端空间", message: "Mock 数据：已使用 620 MB，共 1 GB。")
    }

    private func showPlan() {
        activeNotice = DemoNotice(title: "当前方案", message: "当前为 Free 演示方案。")
    }

    private func showPro() {
        activeNotice = DemoNotice(title: "Folio Pro", message: "这是 UI Demo，不会发起真实订阅或支付。")
    }

    private func showContentPolicy() {
        activeNotice = DemoNotice(title: "内容处理", message: "本原型仅使用本地 Mock 数据，不会上传或处理真实内容。")
    }

    private func showSupport() {
        activeNotice = DemoNotice(title: "联系支持", message: "演示入口：support@example.com")
    }

    private func confirmMockDeletion() {
        activeNotice = DemoNotice(title: "未执行删除", message: "这是 UI Demo，没有任何真实数据被删除。")
    }

    private func dismissDeleteConfirmation() {
        showsDeleteConfirmation = false
    }
}

#Preview {
    SettingsView(onBack: {}, onShowShareSuccess: {})
}
