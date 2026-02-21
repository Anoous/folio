import SwiftUI
import Markdown

// MARK: - Markdown Renderer

/// Converts a Markdown string into a SwiftUI `View` by walking the
/// swift-markdown AST with a `MarkupVisitor`.
struct MarkdownRenderer: View {
    let markdownText: String
    let fontSize: CGFloat
    let lineSpacing: CGFloat

    init(
        markdownText: String,
        fontSize: CGFloat = 17,
        lineSpacing: CGFloat = Typography.articleBodyLineSpacing
    ) {
        self.markdownText = markdownText
        self.fontSize = fontSize
        self.lineSpacing = lineSpacing
    }

    var body: some View {
        let document = Document(parsing: markdownText)
        var visitor = MarkdownSwiftUIVisitor(fontSize: fontSize, lineSpacing: lineSpacing)
        let views = visitor.visitDocument(document)

        VStack(alignment: .leading, spacing: Spacing.md) {
            ForEach(Array(views.enumerated()), id: \.offset) { _, view in
                view
            }
        }
    }
}

// MARK: - Visitor

/// A `MarkupVisitor` that produces an array of `AnyView` for each top-level
/// block element in the Markdown document.
struct MarkdownSwiftUIVisitor: MarkupVisitor {
    typealias Result = [AnyView]

    let fontSize: CGFloat
    let lineSpacing: CGFloat

    // MARK: - Document

    mutating func defaultVisit(_ markup: any Markup) -> [AnyView] {
        var result: [AnyView] = []
        for child in markup.children {
            result.append(contentsOf: visit(child))
        }
        return result
    }

    mutating func visitDocument(_ document: Document) -> [AnyView] {
        var result: [AnyView] = []
        for child in document.children {
            result.append(contentsOf: visit(child))
        }
        return result
    }

    // MARK: - Headings

    mutating func visitHeading(_ heading: Heading) -> [AnyView] {
        let text = collectInlineText(heading)
        let font = headingFont(level: heading.level)
        let view = text
            .font(font)
            .foregroundStyle(Color.folio.textPrimary)
            .padding(.top, heading.level <= 2 ? Spacing.md : Spacing.sm)

        return [AnyView(view)]
    }

    // MARK: - Paragraph

    mutating func visitParagraph(_ paragraph: Paragraph) -> [AnyView] {
        let text = collectInlineText(paragraph)
        let view = text
            .font(Font.custom("Noto Serif SC", size: fontSize))
            .foregroundStyle(Color.folio.textPrimary)
            .lineSpacing(lineSpacing)
            .fixedSize(horizontal: false, vertical: true)

        return [AnyView(view)]
    }

    // MARK: - Code Block

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> [AnyView] {
        let language = codeBlock.language ?? ""
        let code = codeBlock.code.trimmingCharacters(in: .newlines)

        let view = CodeBlockView(code: code, language: language)
        return [AnyView(view)]
    }

    // MARK: - Block Quote

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> [AnyView] {
        var innerViews: [AnyView] = []
        for child in blockQuote.children {
            innerViews.append(contentsOf: visit(child))
        }

        let view = HStack(alignment: .top, spacing: Spacing.sm) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.folio.accent.opacity(0.6))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(Array(innerViews.enumerated()), id: \.offset) { _, innerView in
                    innerView
                }
            }
        }
        .padding(.vertical, Spacing.xs)

        return [AnyView(view)]
    }

    // MARK: - Ordered List

    mutating func visitOrderedList(_ orderedList: OrderedList) -> [AnyView] {
        var views: [AnyView] = []
        for (index, item) in orderedList.children.enumerated() {
            guard let listItem = item as? ListItem else { continue }
            let itemViews = visitListItem(listItem)

            let view = HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                Text("\(index + 1).")
                    .font(Font.custom("Noto Serif SC", size: fontSize))
                    .foregroundStyle(Color.folio.textSecondary)
                    .frame(width: 24, alignment: .trailing)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    ForEach(Array(itemViews.enumerated()), id: \.offset) { _, itemView in
                        itemView
                    }
                }
            }
            views.append(AnyView(view))
        }
        return views
    }

    // MARK: - Unordered List

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> [AnyView] {
        var views: [AnyView] = []
        for item in unorderedList.children {
            guard let listItem = item as? ListItem else { continue }
            let itemViews = visitListItem(listItem)

            let view = HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                Text("\u{2022}")
                    .font(Font.custom("Noto Serif SC", size: fontSize))
                    .foregroundStyle(Color.folio.textSecondary)
                    .frame(width: 24, alignment: .trailing)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    ForEach(Array(itemViews.enumerated()), id: \.offset) { _, itemView in
                        itemView
                    }
                }
            }
            views.append(AnyView(view))
        }
        return views
    }

    // MARK: - List Item

    mutating func visitListItem(_ listItem: ListItem) -> [AnyView] {
        var result: [AnyView] = []
        for child in listItem.children {
            result.append(contentsOf: visit(child))
        }
        return result
    }

    // MARK: - Thematic Break

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> [AnyView] {
        let view = Divider()
            .padding(.vertical, Spacing.sm)
        return [AnyView(view)]
    }

    // MARK: - Table

    mutating func visitTable(_ table: Markdown.Table) -> [AnyView] {
        var headerRow: [String] = []
        var bodyRows: [[String]] = []

        for child in table.children {
            if let head = child as? Markdown.Table.Head {
                for cell in head.children {
                    if let tableCell = cell as? Markdown.Table.Cell {
                        headerRow.append(plainText(tableCell))
                    }
                }
            } else if let body = child as? Markdown.Table.Body {
                for row in body.children {
                    if let tableRow = row as? Markdown.Table.Row {
                        var rowData: [String] = []
                        for cell in tableRow.children {
                            if let tableCell = cell as? Markdown.Table.Cell {
                                rowData.append(plainText(tableCell))
                            }
                        }
                        bodyRows.append(rowData)
                    }
                }
            }
        }

        let view = TableView(headers: headerRow, rows: bodyRows)
        return [AnyView(view)]
    }

    // MARK: - Image

    mutating func visitImage(_ image: Markdown.Image) -> [AnyView] {
        let urlString = image.source ?? ""
        let altText = image.plainText

        let view = ImageView(urlString: urlString, altText: altText)
        return [AnyView(view)]
    }

    // MARK: - HTML Block (pass through as text)

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> [AnyView] {
        let view = Text(html.rawHTML)
            .font(Typography.articleCode)
            .foregroundStyle(Color.folio.textSecondary)
        return [AnyView(view)]
    }

    // MARK: - Inline Text Collection

    /// Recursively collects inline markup children into a single SwiftUI `Text`.
    private func collectInlineText(_ markup: any Markup) -> SwiftUI.Text {
        var result = SwiftUI.Text("")
        for child in markup.children {
            result = result + inlineText(child)
        }
        return result
    }

    private func inlineText(_ markup: any Markup) -> SwiftUI.Text {
        if let text = markup as? Markdown.Text {
            return SwiftUI.Text(text.string)
        } else if let strong = markup as? Strong {
            return collectInlineText(strong).bold()
        } else if let emphasis = markup as? Emphasis {
            return collectInlineText(emphasis).italic()
        } else if let code = markup as? InlineCode {
            return Text(code.code)
                .font(Typography.articleCode)
                .foregroundColor(Color.folio.accent)
        } else if let link = markup as? Markdown.Link {
            // SwiftUI Text doesn't support tappable links directly,
            // so we style link text distinctly.
            return collectInlineText(link)
                .foregroundColor(Color.folio.link)
                .underline()
        } else if let softBreak = markup as? SoftBreak {
            _ = softBreak
            return Text(" ")
        } else if let lineBreak = markup as? LineBreak {
            _ = lineBreak
            return Text("\n")
        } else if let image = markup as? Markdown.Image {
            // Inline image reference — display alt text
            return Text("[\(image.plainText)]")
                .foregroundColor(Color.folio.link)
        } else if let strikethrough = markup as? Strikethrough {
            return collectInlineText(strikethrough).strikethrough()
        } else {
            // Fallback: collect children
            var result = SwiftUI.Text("")
            for child in markup.children {
                result = result + inlineText(child)
            }
            return result
        }
    }

    // MARK: - Helpers

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1: return Font.custom("Noto Serif SC", size: 28).weight(.bold)
        case 2: return Font.custom("Noto Serif SC", size: 24).weight(.bold)
        case 3: return Font.custom("Noto Serif SC", size: 20).weight(.semibold)
        case 4: return Font.custom("Noto Serif SC", size: 18).weight(.semibold)
        case 5: return Font.custom("Noto Serif SC", size: 16).weight(.medium)
        case 6: return Font.custom("Noto Serif SC", size: 15).weight(.medium)
        default: return Font.custom("Noto Serif SC", size: 15).weight(.medium)
        }
    }

    private func plainText(_ markup: any Markup) -> String {
        if let text = markup as? Markdown.Text {
            return text.string
        }
        var result = ""
        for child in markup.children {
            result += plainText(child)
        }
        return result
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        MarkdownRenderer(markdownText: """
        # Heading 1

        This is a paragraph with **bold**, *italic*, and `inline code`.

        ## Heading 2

        > This is a blockquote with some important information.

        ### Code Block

        ```swift
        let greeting = "Hello, Folio!"
        print(greeting)
        ```

        ### Lists

        - First item
        - Second item
        - Third item

        1. Ordered one
        2. Ordered two
        3. Ordered three

        ---

        [Visit Example](https://example.com)
        """)
        .padding(Spacing.screenPadding)
    }
}
