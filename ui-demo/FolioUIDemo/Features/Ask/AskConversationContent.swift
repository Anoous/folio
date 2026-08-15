import SwiftUI

struct AskConversationContent: View {
    let question: String
    let showsInsufficientEvidence: Bool
    let onOpenSource: () -> Void
    let onSuggestion: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(question)
                .font(.body)
                .lineSpacing(4)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(FolioPalette.subtleGreen)
                .clipShape(.rect(cornerRadius: 20))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 54)
                .accessibilityIdentifier("ask-thread-question")

            if showsInsufficientEvidence {
                InsufficientEvidenceCard(onSuggestion: onSuggestion)
                    .padding(.top, 18)

                Label(
                    "回答仅基于你已保存的资料，不会使用外部数据。",
                    systemImage: "lock"
                )
                .font(.footnote)
                .foregroundStyle(FolioPalette.tertiaryText)
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
                .padding(.bottom, 30)
            } else {
                Label("回答", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(FolioPalette.inkGreenDeep)
                    .padding(.top, 28)

                Text("解释可能让低质量结论显得更加确定。更可靠的设计是说明证据、能力范围和未知边界，而不是用更长的语言掩盖不确定性。")
                    .font(.body)
                    .lineSpacing(6)
                    .padding(.top, 12)
                    .accessibilityIdentifier("ask-inline-response")

                HStack(spacing: 15) {
                    CitationChip(number: 1, action: onOpenSource)
                    CitationChip(number: 2, action: onOpenSource)
                    CitationChip(number: 3, action: onOpenSource)
                }
                .padding(.top, 10)

                Text("来源")
                    .font(.headline)
                    .foregroundStyle(FolioPalette.inkGreenDeep)
                    .padding(.top, 28)

                VStack(spacing: 0) {
                    AskSourceRow(
                        monogram: "e",
                        title: "如何设计可信的 AI 产品",
                        action: onOpenSource
                    )
                    AskSourceRow(
                        monogram: "doc",
                        title: "透明度与可解释性",
                        action: onOpenSource
                    )
                    AskSourceRow(
                        monogram: "dn",
                        title: "建立长期 AI 信任",
                        action: onOpenSource
                    )
                }
                .padding(.top, 11)
                .padding(.bottom, 25)
            }
        }
        .padding(.horizontal, FolioMetrics.readingInset)
        .padding(.top, 24)
    }
}
