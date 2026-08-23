import SwiftUI

struct LibrarySearchResultRow: View {
    let result: DemoSearchResult
    let transitionNamespace: Namespace.ID
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(result.article.title)
                        .font(FolioTypography.editorial(19, relativeTo: .headline))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Spacer(minLength: 8)

                    Text(result.scope)
                        .font(.footnote.bold())
                        .foregroundStyle(FolioPalette.inkGreenDeep)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(FolioPalette.subtleGreen, in: .capsule)
                }

                Text(result.snippet)
                    .font(FolioTypography.editorial(15.5, relativeTo: .body))
                    .foregroundStyle(FolioPalette.secondaryText)
                    .lineLimit(3)
                    .lineSpacing(4)
                    .multilineTextAlignment(.leading)

                Label(result.article.source, systemImage: "arrow.up.right.square")
                    .font(.footnote)
                    .foregroundStyle(FolioPalette.tertiaryText)
            }
            .padding(.vertical, 14)
            .contentShape(.rect)
        }
        .buttonStyle(FolioPressButtonStyle())
        .overlay(alignment: .bottomTrailing) {
            Rectangle()
                .fill(FolioPalette.paperLine.opacity(0.72))
                .frame(height: 0.6)
        }
        .matchedTransitionSource(id: result.article.id, in: transitionNamespace)
        .accessibilityHint(Text(.openSearchResultHint))
        .accessibilityIdentifier("library-search-result-\(result.id)")
    }
}
