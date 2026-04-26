import SwiftUI

struct HomeWorkbenchHeaderView: View {
    let articleCount: Int
    let readyCount: Int
    let processingCount: Int
    let echoCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(formattedDate)
                .font(Typography.caption)
                .foregroundStyle(Color.folio.textTertiary)
                .textCase(.uppercase)

            HStack(alignment: .firstTextBaseline) {
                Text(primaryLine)
                    .font(.title3.bold())
                    .foregroundStyle(Color.folio.textPrimary)
                    .lineLimit(2)

                Spacer(minLength: Spacing.md)

                if processingCount > 0 {
                    Label("\(processingCount)", systemImage: "clock")
                        .font(Typography.caption)
                        .foregroundStyle(Color.folio.accent)
                        .accessibilityLabel("\(processingCount) 个内容正在处理")
                }
            }

            Text(secondaryLine)
                .font(Typography.body)
                .foregroundStyle(Color.folio.textSecondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.md)
    }

    private var formattedDate: String {
        Date.now.formatted(.dateTime.month().day().weekday(.wide))
    }

    private var primaryLine: String {
        if articleCount == 0 {
            return "从捕获开始"
        }
        if processingCount > 0 {
            return "有内容正在变成知识"
        }
        if echoCount > 0 {
            return "今天有 \(echoCount) 张 Echo"
        }
        return "资料库就绪"
    }

    private var secondaryLine: String {
        if articleCount == 0 {
            return "保存链接、文字、语音或截图后，Folio 会显示处理进度，并在可用时进入阅读、提问和复习。"
        }

        var parts: [String] = ["\(readyCount) 篇可阅读"]
        if processingCount > 0 {
            parts.append("\(processingCount) 个处理中")
        }
        if echoCount > 0 {
            parts.append("\(echoCount) 个待回忆")
        }
        return parts.joined(separator: " · ")
    }
}
