import SwiftUI

struct ArticleAskSuggestionButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(title, systemImage: symbol, action: action)
            .font(.body)
            .foregroundStyle(FolioPalette.inkGreenDeep)
            .frame(maxWidth: .infinity, minHeight: FolioMetrics.minimumTapTarget, alignment: .leading)
            .padding(.horizontal, 14)
            .background(FolioPalette.surface, in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(FolioPalette.paperLine, lineWidth: 0.8)
            }
            .buttonStyle(FolioPressButtonStyle())
    }
}
