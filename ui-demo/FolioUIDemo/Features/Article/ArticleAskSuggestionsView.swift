import SwiftUI

struct ArticleAskSuggestionsView: View {
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("你想问这篇文章什么？")
                .font(.title3.bold())
                .foregroundStyle(FolioPalette.inkGreenDeep)

            VStack(spacing: 8) {
                ArticleAskSuggestionButton(
                    title: "总结核心观点",
                    symbol: "text.alignleft",
                    action: selectSummary
                )
                ArticleAskSuggestionButton(
                    title: "举个实际例子",
                    symbol: "lightbulb",
                    action: selectExample
                )
                ArticleAskSuggestionButton(
                    title: "质疑作者结论",
                    symbol: "questionmark.bubble",
                    action: selectChallenge
                )
            }
        }
    }

    private func selectSummary() {
        onSelect("总结核心观点")
    }

    private func selectExample() {
        onSelect("举个实际例子")
    }

    private func selectChallenge() {
        onSelect("质疑作者结论")
    }
}
