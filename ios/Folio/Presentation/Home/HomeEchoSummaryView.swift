import SwiftUI

struct HomeEchoSummaryView: View {
    let isAuthenticated: Bool
    let isLoading: Bool
    let errorMessage: String?
    let remainingToday: Int?
    let weeklyCount: Int?
    let weeklyLimit: Int?
    let onRetry: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 72)
            } else if let errorMessage {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.folio.error)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("Echo 暂时不可用")
                            .font(.subheadline.bold())
                            .foregroundStyle(Color.folio.textPrimary)
                        Text(errorMessage)
                            .font(Typography.caption)
                            .foregroundStyle(Color.folio.textSecondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button("重试", action: onRetry)
                        .font(Typography.caption)
                        .foregroundStyle(Color.folio.accent)
                        .buttonStyle(.plain)
                }
            } else if !isAuthenticated {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Image(systemName: "rectangle.stack.badge.person.crop")
                        .foregroundStyle(Color.folio.textTertiary)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("登录后开启每日回忆")
                            .font(.subheadline.bold())
                            .foregroundStyle(Color.folio.textPrimary)
                        Text("Echo 会从文章和高亮生成复习卡片。")
                            .font(Typography.caption)
                            .foregroundStyle(Color.folio.textSecondary)
                    }
                    Spacer()
                    Button("登录", action: onOpenSettings)
                        .font(Typography.caption)
                        .foregroundStyle(Color.folio.accent)
                        .buttonStyle(.plain)
                }
            } else {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.folio.success)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("今天没有待复习卡片")
                            .font(.subheadline.bold())
                            .foregroundStyle(Color.folio.textPrimary)
                        Text(progressText)
                            .font(Typography.caption)
                            .foregroundStyle(Color.folio.textSecondary)
                            .lineLimit(2)
                    }
                    Spacer()
                }
            }
        }
        .padding(Spacing.md)
        .background(Color.folio.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, Spacing.screenPadding)
    }

    private var progressText: String {
        if let remainingToday, remainingToday > 0 {
            return "今天还可以复习 \(remainingToday) 张。"
        }
        if let weeklyCount, let weeklyLimit {
            return "本周已完成 \(weeklyCount) / \(weeklyLimit)。"
        }
        if let weeklyCount {
            return "本周已完成 \(weeklyCount) 张。"
        }
        return "有新高亮或文章后，Folio 会安排下一轮回忆。"
    }
}
