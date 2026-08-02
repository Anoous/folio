import SwiftUI

struct AskAnswerView: View {
    let onBack: () -> Void
    let onOpenSource: () -> Void
    @State private var followUp = ""
    @State private var showsFilters = false
    @State private var answerScope = "全部资料"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                FolioBackButton(action: onBack)
                Spacer()
                Text("提问")
                    .font(FolioTypography.editorialBold(24, relativeTo: .title2))
                    .foregroundStyle(FolioPalette.inkGreenDeep)
                Spacer()
                FolioFilterButton(action: showFilters)
            }
            .padding(.horizontal, 22)
            .padding(.top, 15)
            .padding(.bottom, 15)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(FolioPalette.paperLine)
                    .frame(height: 0.6)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("你的问题")
                        .font(FolioTypography.editorial(15, relativeTo: .headline))
                        .foregroundStyle(FolioPalette.secondaryText)

                    Text("为什么许多 AI 产品的解释功能反而\n降低可信度？")
                        .font(FolioTypography.editorial(16.5, relativeTo: .title2))
                        .lineSpacing(5)
                        .padding(.top, 12)

                    Divider()
                        .foregroundStyle(FolioPalette.paperLine)
                        .padding(.vertical, 18)

                    Text("回答")
                        .font(FolioTypography.editorial(17, relativeTo: .headline))
                        .foregroundStyle(FolioPalette.inkGreenDeep)

                    Text("解释可能让低质量结论显得更加确定。\n更可靠的设计是说明证据、能力范围和\n未知边界，而不是用更长的语言掩盖\n不确定性。")
                        .font(FolioTypography.editorial(16.5, relativeTo: .title3))
                        .lineSpacing(5)
                        .padding(.top, 12)

                    HStack(spacing: 15) {
                        CitationChip(number: 1, action: onOpenSource)
                        CitationChip(number: 2, action: onOpenSource)
                        CitationChip(number: 3, action: onOpenSource)
                    }
                    .padding(.top, 10)

                    Text("来源")
                        .font(FolioTypography.editorial(17, relativeTo: .headline))
                        .foregroundStyle(FolioPalette.inkGreenDeep)
                        .padding(.top, 22)

                    VStack(spacing: 0) {
                        AskSourceRow(monogram: "e", title: "如何设计可信的 AI 产品", action: onOpenSource)
                        AskSourceRow(monogram: "doc", title: "透明度与可解释性", action: onOpenSource)
                        AskSourceRow(monogram: "dn", title: "建立长期 AI 信任", action: onOpenSource)
                    }
                    .padding(.top, 11)
                    .padding(.bottom, 25)
                }
                .padding(.horizontal, FolioMetrics.pageInset)
                .padding(.top, 22)
            }
            .scrollIndicators(.hidden)

            FolioInputBar(
                text: $followUp,
                placeholder: "继续提问…",
                isEnabled: true,
                sendSymbol: "paperplane",
                action: clearFollowUp
            )
            .padding(.horizontal, 25)
            .padding(.vertical, 8)
        }
        .background(FolioPalette.canvas)
        .confirmationDialog("回答范围：\(answerScope)", isPresented: $showsFilters) {
            Button("全部资料", action: useAllSources)
            Button("仅当前文章", action: useCurrentArticle)
            Button("取消", role: .cancel, action: dismissFilters)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func showFilters() {
        showsFilters = true
    }

    private func clearFollowUp() {
        guard !followUp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        followUp = ""
    }

    private func useAllSources() {
        answerScope = "全部资料"
    }

    private func useCurrentArticle() {
        answerScope = "仅当前文章"
    }

    private func dismissFilters() {
        showsFilters = false
    }
}
