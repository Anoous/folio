import SwiftUI

struct SettingsView: View {
    @Bindable var store: DemoStore
    let onBack: () -> Void
    let onShowShareSuccess: () -> Void
    let onShowDevices: () -> Void
    @State private var activeNotice: DemoNotice?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SettingsHeaderView(onBack: onBack)

                SettingsProfileHeader(email: store.accountEmail, action: showProfile)
                    .padding(.top, 26)

                SettingsSectionLabel(title: "账号")
                    .padding(.top, 28)
                SettingsCard {
                    SettingsRow(
                        symbol: "envelope",
                        title: "邮箱",
                        value: store.accountEmail,
                        action: showEmail
                    )
                    SettingsRow(
                        symbol: "desktopcomputer",
                        title: "已登录设备",
                        value: "\(store.deviceSessions.count) 台设备",
                        action: onShowDevices
                    )
                    .accessibilityIdentifier("settings-devices")
                }

                SettingsSectionLabel(title: "云端空间")
                    .padding(.top, 24)
                SettingsStorageCard(
                    usedFraction: store.isCapacityFull ? 1 : 0.62,
                    action: showStorage
                )

                SettingsSectionLabel(title: "订阅")
                    .padding(.top, 24)
                SettingsCard {
                    SettingsRow(symbol: "crown", title: "当前方案", value: "Free", action: showPlan)
                    SettingsRow(symbol: "star.circle.fill", title: "查看 Pro", value: "", action: showPro)
                }

                SettingsSectionLabel(title: "数据与隐私")
                    .padding(.top, 24)
                SettingsDestructiveActionsView(
                    articleCount: store.articles.count,
                    onClearLibrary: store.clearLibrary,
                    onDeleteAccount: store.requestAccountDeletion
                )

                SettingsSectionLabel(title: "可靠性演示")
                    .padding(.top, 24)
                SettingsCard {
                    SettingsToggleRow(
                        symbol: "network",
                        title: "网络可用",
                        isOn: $store.isOnline
                    )
                    SettingsToggleRow(
                        symbol: "externaldrive.badge.exclamationmark",
                        title: "模拟容量已满",
                        isOn: $store.isCapacityFull,
                        tint: FolioPalette.warning
                    )
                    SettingsToggleRow(
                        symbol: "clock.badge.exclamationmark",
                        title: "下次保存超时",
                        isOn: $store.shouldTimeoutNextCapture,
                        tint: FolioPalette.warning
                    )
                    SettingsToggleRow(
                        symbol: "doc.badge.ellipsis",
                        title: "下次处理失败",
                        isOn: $store.shouldFailNextProcessing,
                        tint: FolioPalette.warning
                    )
                    SettingsRow(
                        symbol: "person.crop.circle.badge.exclamationmark",
                        title: "模拟会话失效",
                        value: "",
                        tint: FolioPalette.warning,
                        action: store.expireSession
                    )
                }

                SettingsSectionLabel(title: "帮助")
                    .padding(.top, 24)
                SettingsCard {
                    SettingsRow(
                        symbol: "shield",
                        title: "Folio 如何处理内容",
                        value: "",
                        action: showContentPolicy
                    )
                    .contextMenu {
                        Button("查看分享保存演示", systemImage: "square.and.arrow.down", action: onShowShareSuccess)
                    }
                    SettingsRow(
                        symbol: "questionmark.circle",
                        title: "联系支持",
                        value: "",
                        action: showSupport
                    )
                }

                Button(
                    "退出登录",
                    systemImage: "rectangle.portrait.and.arrow.right",
                    action: { store.signOut() }
                )
                    .font(.body.weight(.semibold))
                    .foregroundStyle(FolioPalette.danger)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .padding(.top, 24)
                    .accessibilityIdentifier("settings-sign-out")
                    .padding(.bottom, 35)
            }
            .padding(.horizontal, FolioMetrics.pageInset)
        }
        .scrollIndicators(.hidden)
        .background(FolioPalette.canvas)
        .alert(item: $activeNotice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("好"))
            )
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func showProfile() {
        activeNotice = DemoNotice(title: "个人资料", message: "Folio 用户 · \(store.accountEmail)")
    }

    private func showEmail() {
        activeNotice = DemoNotice(title: "邮箱", message: "当前账号为 \(store.accountEmail)。")
    }

    private func showStorage() {
        activeNotice = DemoNotice(title: "云端空间", message: "已使用 \(store.storageDescription)。容量已满时仍可阅读和删除已有内容。")
    }

    private func showPlan() {
        activeNotice = DemoNotice(title: "当前方案", message: "当前为 Free 演示方案。")
    }

    private func showPro() {
        activeNotice = DemoNotice(title: "Folio Pro", message: "这是 UI Demo，不会发起真实订阅或支付。")
    }

    private func showContentPolicy() {
        activeNotice = DemoNotice(
            title: "内容处理",
            message: "链接先由云端确认接收，再异步获取正文；任何失败都会保留可恢复路径。"
        )
    }

    private func showSupport() {
        activeNotice = DemoNotice(title: "联系支持", message: "演示入口：support@example.com")
    }
}

#Preview {
    @Previewable @State var store = DemoStore(initialScreen: .settings)

    SettingsView(
        store: store,
        onBack: {},
        onShowShareSuccess: {},
        onShowDevices: {}
    )
}
