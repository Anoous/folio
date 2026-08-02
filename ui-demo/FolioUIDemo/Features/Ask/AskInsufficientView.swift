import SwiftUI

struct AskInsufficientView: View {
    let onSuggestion: () -> Void
    @State private var question = ""
    @State private var showsFilters = false
    @State private var answerScope = "全部资料"

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 13) {
                        Text("提问")
                            .font(FolioTypography.editorialBold(43, relativeTo: .largeTitle))
                            .foregroundStyle(FolioPalette.inkGreenDeep)
                        Spacer()
                        FolioFilterButton(action: showFilters)
                        FolioAvatar(size: 48)
                    }
                    .padding(.top, 48)

                    Text("哪些行业最适合使用 AI 解释功能？")
                        .font(FolioTypography.editorial(12.5, relativeTo: .body))
                        .padding(.horizontal, 18)
                        .frame(minHeight: 59)
                        .background(FolioPalette.subtleGreen.opacity(0.58))
                        .clipShape(.rect(cornerRadius: 22, style: .continuous))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.leading, 72)
                        .padding(.top, 39)

                    InsufficientEvidenceCard(onSuggestion: onSuggestion)
                        .padding(.top, 18)

                    Label("回答仅基于你已保存的资料，不会使用外部数据。", systemImage: "lock")
                        .font(.system(size: 12))
                        .foregroundStyle(FolioPalette.tertiaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)
                        .padding(.bottom, 30)
                }
                .padding(.horizontal, FolioMetrics.pageInset)
            }
            .scrollIndicators(.hidden)

            FolioInputBar(
                text: $question,
                placeholder: "提出基于你资料的问题…",
                isEnabled: !question.isEmpty,
                sendSymbol: "paperplane",
                action: onSuggestion
            )
            .padding(.horizontal, 24)
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
