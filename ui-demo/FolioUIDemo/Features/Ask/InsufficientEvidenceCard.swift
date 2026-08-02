import SwiftUI

struct InsufficientEvidenceCard: View {
    let onSuggestion: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(FolioPalette.inkGreenDeep)
                    .frame(width: 54, height: 54)
                    .background(FolioPalette.evidence.opacity(0.65))
                    .clipShape(.circle)

                VStack(alignment: .leading, spacing: 8) {
                    Text("资料不足，无法可靠回答")
                        .font(FolioTypography.editorialBold(17.5, relativeTo: .title2))
                        .foregroundStyle(FolioPalette.inkGreenDeep)
                    Text("你的资料中提到了 AI 可信度，但没有足够内容支持对具体行业作出比较。")
                        .font(FolioTypography.editorial(13, relativeTo: .body))
                        .lineSpacing(4)
                }
            }

            Divider()
                .foregroundStyle(FolioPalette.paperLine)
                .padding(.vertical, 16)

            Text("你可以尝试：")
                .font(FolioTypography.editorialBold(17, relativeTo: .headline))
                .foregroundStyle(FolioPalette.inkGreenDeep)

            VStack(spacing: 0) {
                InsufficientSuggestionRow(symbol: "text.bubble", title: "我保存的内容如何定义 AI 可信度？", action: onSuggestion)
                InsufficientSuggestionRow(symbol: "exclamationmark.triangle", title: "我保存的资料提到了哪些解释风险？", action: onSuggestion)
                InsufficientSuggestionRow(symbol: "chart.bar", title: "AI 可信度在我保存的资料中有哪些应用场景？", action: onSuggestion)
            }
            .padding(.top, 8)
        }
        .padding(16)
        .background(FolioPalette.surface)
        .clipShape(.rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(FolioPalette.paperLine, lineWidth: 0.8)
        }
    }
}
