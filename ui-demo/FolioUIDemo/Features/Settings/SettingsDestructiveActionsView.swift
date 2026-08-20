import SwiftUI

struct SettingsDestructiveActionsView: View {
    let articleCount: Int
    let onClearLibrary: () -> Void
    let onDeleteAccount: () -> Void
    @State private var showsClearConfirmation = false
    @State private var showsAccountDeletion = false

    var body: some View {
        SettingsCard {
            Button(action: showClearConfirmation) {
                SettingsActionLabel(
                    symbol: "trash",
                    title: "清空资料库",
                    value: articleCount == 0 ? "已为空" : "\(articleCount) 篇",
                    tint: FolioPalette.danger
                )
            }
            .buttonStyle(.plain)
            .disabled(articleCount == 0)
            .confirmationDialog(
                "清空资料库？",
                isPresented: $showsClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("清空全部内容", role: .destructive, action: onClearLibrary)
                Button("取消", role: .cancel) {}
            } message: {
                Text("所有内容会立即从资料库和 Ask 中移除。此 Demo 不连接真实云端。")
            }

            Button(action: showAccountDeletion) {
                SettingsActionLabel(
                    symbol: "person.crop.circle.badge.xmark",
                    title: "删除账号",
                    value: "",
                    tint: FolioPalette.danger
                )
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showsAccountDeletion) {
                AccountDeletionView(onConfirm: onDeleteAccount)
            }
        }
    }

    private func showClearConfirmation() {
        showsClearConfirmation = true
    }

    private func showAccountDeletion() {
        showsAccountDeletion = true
    }
}
