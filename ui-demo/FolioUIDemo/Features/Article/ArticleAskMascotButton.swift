import SwiftUI

struct ArticleAskMascotButton: View {
    let isExpanded: Bool
    let showsReturnState: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(visibleLabel)
                    .font(.subheadline.bold())
                    .foregroundStyle(FolioPalette.inkGreenDeep)
                    .lineLimit(1)
                    .frame(width: isExpanded ? labelWidth : 0, alignment: .trailing)
                    .opacity(isExpanded ? 1 : 0)
                    .clipped()

                FolioPageMascot()
                    .overlay(alignment: .topTrailing) {
                        Circle()
                            .fill(FolioPalette.warning)
                            .frame(width: 8, height: 8)
                            .overlay {
                                Circle()
                                    .stroke(FolioPalette.surface, lineWidth: 1.5)
                            }
                            .opacity(showsReturnState ? 1 : 0)
                    }
            }
            .padding(.leading, isExpanded ? 14 : 4)
            .padding(.trailing, 5)
            .frame(minHeight: 48)
            .background {
                FolioGlassLens(
                    shape: Capsule(),
                    tint: showsReturnState ? FolioPalette.evidence : FolioPalette.subtleGreen,
                    isProminent: isExpanded
                )
            }
            .contentShape(.capsule)
        }
        .buttonStyle(FolioPressButtonStyle())
        .offset(x: isExpanded ? -8 : 24)
        .animation(FolioMotion.toolbarMorph(reduceMotion: reduceMotion), value: isExpanded)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("打开基于当前文章全文的答疑")
        .accessibilityIdentifier("article-ask-mascot")
    }

    private var visibleLabel: String {
        showsReturnState ? "返回回答" : "问这篇"
    }

    private var accessibilityLabel: String {
        showsReturnState ? "返回文章答疑" : "问这篇文章"
    }

    private var labelWidth: Double {
        showsReturnState ? 68 : 54
    }
}

#Preview {
    VStack(alignment: .trailing, spacing: 24) {
        ArticleAskMascotButton(isExpanded: false, showsReturnState: false, action: {})
        ArticleAskMascotButton(isExpanded: true, showsReturnState: false, action: {})
        ArticleAskMascotButton(isExpanded: true, showsReturnState: true, action: {})
    }
    .frame(maxWidth: .infinity, alignment: .trailing)
    .padding(.vertical)
    .background(FolioPalette.canvas)
}
