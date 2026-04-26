import SwiftUI

struct HomeQuotaStatusView: View {
    let snapshot: HomeQuotaSnapshot
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: iconName)
                    .foregroundStyle(iconColor)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title)
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.folio.textPrimary)

                    Text(message)
                        .font(Typography.caption)
                        .foregroundStyle(Color.folio.textSecondary)
                        .lineLimit(3)
                }

                Spacer(minLength: Spacing.sm)

                if showsAction {
                    Button(actionTitle, action: onOpenSettings)
                        .font(Typography.caption)
                        .foregroundStyle(Color.folio.accent)
                        .buttonStyle(.plain)
                }
            }

            if showsProgress {
                ProgressView(value: snapshot.progress)
                    .progressViewStyle(.linear)
                    .tint(progressColor)
                    .accessibilityLabel("本月捕获额度")
                    .accessibilityValue("\(snapshot.used) / \(snapshot.effectiveQuota)")
            }
        }
        .padding(Spacing.md)
        .background(Color.folio.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, Spacing.screenPadding)
    }

    private var title: String {
        switch snapshot.state {
        case .signedOut:
            return "本地可用，登录后同步"
        case .pro:
            return "Pro 已激活"
        case .available:
            return "本月还可捕获 \(snapshot.remaining) 篇"
        case .warning:
            return "额度剩余 \(snapshot.remaining) 篇"
        case .exceeded:
            return "捕获额度已用完"
        }
    }

    private var message: String {
        switch snapshot.state {
        case .signedOut:
            return "当前设备仍可保存内容；登录后可同步订阅和服务端额度。"
        case .pro:
            return "文章捕获、知识问答和 Echo 复习会按 Pro 权益校验。"
        case .available:
            return "已使用 \(snapshot.used) / \(snapshot.effectiveQuota)。接近上限时这里会提前提醒。"
        case .warning:
            return "已使用 \(snapshot.used) / \(snapshot.effectiveQuota)。"
        case .exceeded:
            return "阅读和搜索仍可用；新增捕获需等待重置或升级。"
        }
    }

    private var iconName: String {
        switch snapshot.state {
        case .signedOut:
            return "person.crop.circle.badge.exclamationmark"
        case .pro:
            return "checkmark.seal.fill"
        case .available:
            return "gauge.with.dots.needle.33percent"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .exceeded:
            return "lock.fill"
        }
    }

    private var iconColor: Color {
        switch snapshot.state {
        case .warning:
            return Color.folio.warning
        case .exceeded:
            return Color.folio.error
        case .pro, .available:
            return Color.folio.accent
        case .signedOut:
            return Color.folio.textTertiary
        }
    }

    private var progressColor: Color {
        switch snapshot.state {
        case .warning:
            return Color.folio.warning
        case .exceeded:
            return Color.folio.error
        default:
            return Color.folio.accent
        }
    }

    private var showsProgress: Bool {
        switch snapshot.state {
        case .available, .warning, .exceeded:
            return true
        case .signedOut, .pro:
            return false
        }
    }

    private var showsAction: Bool {
        switch snapshot.state {
        case .signedOut, .warning, .exceeded:
            return true
        case .pro, .available:
            return false
        }
    }

    private var actionTitle: String {
        snapshot.state == .signedOut ? "登录" : "查看订阅"
    }
}
