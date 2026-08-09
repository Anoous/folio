import SwiftUI

struct ArticleAskScopeChip: View {
    let articleTitle: String

    var body: some View {
        Label("基于《\(articleTitle)》全文", systemImage: "doc.text.magnifyingglass")
            .font(.subheadline)
            .foregroundStyle(FolioPalette.inkGreenDeep)
            .lineLimit(2)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FolioPalette.subtleGreen, in: .rect(cornerRadius: 13))
            .accessibilityIdentifier("article-ask-scope")
    }
}
