import SwiftUI

/// An identifiable block-level element produced by the Markdown visitor.
/// Using an enum with stable IDs lets SwiftUI diff efficiently without AnyView.
enum MarkdownBlock: Identifiable {
    case heading(id: Int, text: Text, level: Int)
    case paragraph(id: Int, text: Text)
    case codeBlock(id: Int, code: String, language: String)
    case blockQuote(id: Int, children: [MarkdownBlock])
    case orderedListItem(id: Int, index: Int, children: [MarkdownBlock])
    case unorderedListItem(id: Int, children: [MarkdownBlock])
    case thematicBreak(id: Int)
    case table(id: Int, headers: [String], rows: [[String]])
    case image(id: Int, urlString: String, altText: String)
    case htmlBlock(id: Int, rawHTML: String)

    var id: Int {
        switch self {
        case .heading(let id, _, _),
             .paragraph(let id, _),
             .codeBlock(let id, _, _),
             .blockQuote(let id, _),
             .orderedListItem(let id, _, _),
             .unorderedListItem(let id, _),
             .thematicBreak(let id),
             .table(let id, _, _),
             .image(let id, _, _),
             .htmlBlock(let id, _):
            return id
        }
    }
}

/// Renders a single `MarkdownBlock` — used inside `ForEach`.
struct MarkdownBlockView: View {
    let block: MarkdownBlock
    let fontSize: CGFloat
    let lineSpacing: CGFloat
    let fontFamily: ReadingFontFamily
    let textColor: Color
    let secondaryTextColor: Color

    var body: some View {
        switch block {
        case .heading(_, let text, let level):
            text
                .font(Typography.readerHeadingFont(level: level, family: fontFamily))
                .foregroundStyle(textColor)
                .padding(.top, level <= 2 ? Spacing.md : Spacing.sm)
                .padding(.bottom, Spacing.xxs)

        case .paragraph(_, let text):
            text
                .font(fontFamily.font(size: fontSize))
                .foregroundStyle(textColor)
                .lineSpacing(lineSpacing)
                .fixedSize(horizontal: false, vertical: true)

        case .codeBlock(_, let code, let language):
            CodeBlockView(code: code, language: language)

        case .blockQuote(_, let children):
            HStack(alignment: .top, spacing: Spacing.sm) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.folio.accent.opacity(0.6))
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(children) { child in
                        MarkdownBlockView(
                            block: child,
                            fontSize: fontSize,
                            lineSpacing: lineSpacing,
                            fontFamily: fontFamily,
                            textColor: textColor,
                            secondaryTextColor: secondaryTextColor
                        )
                    }
                }
            }
            .padding(.vertical, Spacing.xs)

        case .orderedListItem(_, let index, let children):
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                Text("\(index).")
                    .font(fontFamily.font(size: fontSize))
                    .foregroundStyle(secondaryTextColor)
                    .frame(width: 24, alignment: .trailing)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    ForEach(children) { child in
                        MarkdownBlockView(
                            block: child,
                            fontSize: fontSize,
                            lineSpacing: lineSpacing,
                            fontFamily: fontFamily,
                            textColor: textColor,
                            secondaryTextColor: secondaryTextColor
                        )
                    }
                }
            }

        case .unorderedListItem(_, let children):
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                Text("\u{2022}")
                    .font(fontFamily.font(size: fontSize))
                    .foregroundStyle(secondaryTextColor)
                    .frame(width: 24, alignment: .trailing)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    ForEach(children) { child in
                        MarkdownBlockView(
                            block: child,
                            fontSize: fontSize,
                            lineSpacing: lineSpacing,
                            fontFamily: fontFamily,
                            textColor: textColor,
                            secondaryTextColor: secondaryTextColor
                        )
                    }
                }
            }

        case .thematicBreak:
            Divider()
                .padding(.vertical, Spacing.sm)

        case .table(_, let headers, let rows):
            TableView(headers: headers, rows: rows)

        case .image(_, let urlString, let altText):
            ImageView(urlString: urlString, altText: altText)

        case .htmlBlock(_, let rawHTML):
            Text(rawHTML)
                .font(Typography.articleCode)
                .foregroundStyle(secondaryTextColor)
        }
    }
}
