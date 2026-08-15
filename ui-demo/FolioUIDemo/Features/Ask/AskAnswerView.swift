import SwiftUI

struct AskAnswerView: View {
    let onBack: () -> Void
    let onOpenSource: () -> Void
    @State private var followUp = ""
    @State private var showsFilters = false
    @State private var answerScope = "全部资料"
    @FocusState private var isFollowUpFocused: Bool

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
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(FolioPalette.paperLine)
                    .frame(height: 0.6)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("为什么许多 AI 产品的解释功能反而降低可信度？")
                        .font(.body)
                        .lineSpacing(4)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(FolioPalette.subtleGreen)
                        .clipShape(.rect(cornerRadius: 20))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.leading, 54)

                    Label("回答", systemImage: "sparkles")
                        .font(.headline)
                        .foregroundStyle(FolioPalette.inkGreenDeep)
                        .padding(.top, 28)

                    Text("解释可能让低质量结论显得更加确定。更可靠的设计是说明证据、能力范围和未知边界，而不是用更长的语言掩盖不确定性。")
                        .font(.body)
                        .lineSpacing(6)
                        .padding(.top, 12)

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
                        AskSourceRow(monogram: "e", title: "如何设计可信的 AI 产品", action: onOpenSource)
                        AskSourceRow(monogram: "doc", title: "透明度与可解释性", action: onOpenSource)
                        AskSourceRow(monogram: "dn", title: "建立长期 AI 信任", action: onOpenSource)
                    }
                    .padding(.top, 11)
                    .padding(.bottom, 25)
                }
                .padding(.horizontal, FolioMetrics.readingInset)
                .padding(.top, 24)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)

            FolioInputBar(
                text: $followUp,
                isFocused: $isFollowUpFocused,
                placeholder: "继续提问…",
                isEnabled: hasFollowUp,
                action: clearFollowUp
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

    private func clearFollowUp() {
        guard !followUp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        followUp = ""
    }

    private var hasFollowUp: Bool {
        !followUp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
