import SwiftUI

struct ArticleAskAnswerCard: View {
    let question: String
    let answer: String
    let onOpenEvidence: () -> Void
    let onContinueReading: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(question)
                .font(.headline)
                .foregroundStyle(FolioPalette.secondaryText)
                .id("article-ask-question")

            Label("基于全文综合", systemImage: "sparkles")
                .font(.subheadline.bold())
                .foregroundStyle(FolioPalette.inkGreenDeep)

            Text(answer)
                .font(.title3.bold())
                .foregroundStyle(FolioPalette.inkGreenDeep)
                .lineSpacing(5)
                .accessibilityIdentifier("article-ask-answer")

            Text("文章把“可信”从一种主观感受，转化成可以检查的体验质量：系统需要说明证据来自哪里、不知道什么，以及结论在什么条件下可能不成立。")
                .font(.body)
                .foregroundStyle(FolioPalette.secondaryText)
                .lineSpacing(5)

            Text("这意味着好的 AI 产品不必假装永远正确，而要让用户能够复核回答、理解边界，并随时回到原文。")
                .font(.body)
                .foregroundStyle(FolioPalette.secondaryText)
                .lineSpacing(5)

            Button("查看 3 处原文依据", systemImage: "doc.text.magnifyingglass", action: onOpenEvidence)
                .font(.headline)
                .foregroundStyle(FolioPalette.inkGreenDeep)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(FolioPalette.evidence, in: .rect(cornerRadius: 15))
                .buttonStyle(FolioPressButtonStyle())
                .id("article-ask-evidence")

            Button("我懂了，继续阅读", systemImage: "book", action: onContinueReading)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(FolioPalette.inkGreenDeep, in: .rect(cornerRadius: 15))
                .buttonStyle(FolioPressButtonStyle())
                .id("article-ask-complete")
        }
    }
}
