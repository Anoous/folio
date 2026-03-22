import SwiftUI

enum Milestone: Int, CaseIterable {
    case firstArticle = 1
    case firstAssociation = 3
    case unlockEchoRAG = 5
    case trialSummary = 10
    case freeLimit = 11

    var title: String {
        switch self {
        case .firstArticle: return "Folio 已读过这篇"
        case .firstAssociation: return "发现关联"
        case .unlockEchoRAG: return "Echo + 问答已解锁"
        case .trialSummary: return "你的知识库已初具规模"
        case .freeLimit: return "Free 版额度说明"
        }
    }

    var description: String {
        switch self {
        case .firstArticle: return "Folio 已自动阅读、理解并提炼了这篇文章的洞察。继续收藏，它会发现文章之间的隐藏关联。"
        case .firstAssociation: return "你存的文章之间开始产生关联了。Folio 会在你的收藏中发现你可能忽略的联系。"
        case .unlockEchoRAG: return "你已收藏 5 篇文章！Echo 间隔回忆已开始工作，试试在搜索中提问，Folio 会综合你的收藏回答。"
        case .trialSummary: return "10 篇收藏，你的知识库开始成型。升级 Pro 享受每日 Echo、无限问答、语义搜索。"
        case .freeLimit: return "Free 版：每周 3 次 Echo、每月 5 次问答。AI 摘要和关键词搜索永久免费。升级 Pro 解锁全部能力。"
        }
    }

    var showUpgrade: Bool {
        self == .trialSummary || self == .freeLimit
    }
}

struct MilestoneCardView: View {
    let milestone: Milestone
    let articleCount: Int
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(milestone.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.folio.textPrimary)
                Spacer()
                Button { onDismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.folio.textTertiary)
                }
            }

            Text(milestone.description)
                .font(.system(size: 14))
                .foregroundStyle(Color.folio.textSecondary)
                .lineSpacing(14 * 0.5)

            if milestone == .trialSummary {
                // Small stats line
                Text("\(articleCount) 篇收藏")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.folio.accent)
            }

            if milestone.showUpgrade {
                Button {
                    // TODO: Navigate to upgrade
                } label: {
                    Text("升级 Pro")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.folio.background)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.folio.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(16)
        .background(Color.folio.accentSoft)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.vertical, 8)
    }
}
