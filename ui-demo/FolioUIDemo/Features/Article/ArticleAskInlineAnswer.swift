import SwiftUI

struct ArticleAskInlineAnswer: View {
    let articleTitle: String
    let question: String
    let answer: String
    let onOpenEvidence: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Label("基于本文", systemImage: "sparkles")
                    .font(.subheadline.bold())
                    .foregroundStyle(FolioPalette.inkGreenDeep)

                Spacer()

                Button("收起回答", systemImage: "xmark", action: onDismiss)
                    .labelStyle(.iconOnly)
                    .font(.subheadline.bold())
                    .foregroundStyle(FolioPalette.secondaryText)
                    .frame(
                        width: FolioMetrics.minimumTapTarget,
                        height: FolioMetrics.minimumTapTarget
                    )
                    .buttonStyle(FolioPressButtonStyle())
            }

            Text(question)
                .font(.subheadline)
                .foregroundStyle(FolioPalette.secondaryText)
                .accessibilityIdentifier("article-ask-question")

            Text(answer)
                .font(.title3.bold())
                .foregroundStyle(FolioPalette.inkGreenDeep)
                .lineSpacing(5)
                .accessibilityIdentifier("article-ask-inline-answer")

            Text("文章把可信落在三件可以复核的事上：证据来自哪里、系统不知道什么，以及结论在什么条件下可能不成立。")
                .font(.body)
                .foregroundStyle(FolioPalette.secondaryText)
                .lineSpacing(5)

            Button(
                "查看《\(articleTitle)》中的原文依据",
                systemImage: "doc.text.magnifyingglass",
                action: onOpenEvidence
            )
            .font(.headline)
            .foregroundStyle(FolioPalette.inkGreenDeep)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(FolioPalette.evidence, in: .rect(cornerRadius: 15))
            .buttonStyle(FolioPressButtonStyle())
            .accessibilityIdentifier("article-ask-evidence")
        }
        .padding(18)
        .background(FolioPalette.surface.opacity(0.88), in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(FolioPalette.paperLine, lineWidth: 0.8)
        }
        .shadow(color: FolioPalette.inkGreenDeep.opacity(0.05), radius: 12, y: 5)
    }
}

#Preview {
    ArticleAskInlineAnswer(
        articleTitle: DemoContent.primaryArticle.title,
        question: "这篇文章的核心观点是什么？",
        answer: "可信来自证据、边界和可验证的过程。",
        onOpenEvidence: {},
        onDismiss: {}
    )
    .padding()
    .background(FolioPalette.canvas)
}
