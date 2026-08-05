import SwiftUI

struct AskInsufficientView: View {
    let onBack: () -> Void
    let onSuggestion: () -> Void
    @State private var question = ""
    @State private var showsFilters = false
    @State private var answerScope = "全部资料"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                FolioBackButton(action: onBack)
                Spacer()
                Text("问答")
                    .font(.headline)
                Spacer()
                FolioFilterButton(action: showFilters)
            }
            .padding(.horizontal, FolioMetrics.libraryInset)
            .padding(.top, 8)
            .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("哪些行业最适合使用 AI 解释功能？")
                        .font(.body)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(FolioPalette.subtleGreen)
                        .clipShape(.rect(cornerRadius: 20))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.leading, 54)
                        .padding(.top, 24)

                    InsufficientEvidenceCard(onSuggestion: onSuggestion)
                        .padding(.top, 18)

                    Label("回答仅基于你已保存的资料，不会使用外部数据。", systemImage: "lock")
                        .font(.system(size: 12))
                        .foregroundStyle(FolioPalette.tertiaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)
                        .padding(.bottom, 30)
                }
                .padding(.horizontal, FolioMetrics.readingInset)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)

            FolioInputBar(
                text: $question,
                placeholder: "提出基于你资料的问题…",
                isEnabled: hasQuestion,
                action: onSuggestion
            )
            .padding(.horizontal, FolioMetrics.libraryInset)
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

    private var hasQuestion: Bool {
        !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
