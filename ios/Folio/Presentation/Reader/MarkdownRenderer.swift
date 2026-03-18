import SwiftUI
import Markdown

// MARK: - Markdown Renderer

/// Converts a Markdown string into a SwiftUI `View` by walking the
/// swift-markdown AST with a `MarkupVisitor`.
struct MarkdownRenderer: View {
    let markdownText: String
    let fontSize: CGFloat
    let lineSpacing: CGFloat
    let fontFamily: ReadingFontFamily
    let textColor: Color
    let secondaryTextColor: Color

    /// Pre-parsed blocks — computed once during init.
    private let parsedBlocks: [MarkdownBlock]

    init(
        markdownText: String,
        fontSize: CGFloat = 17,
        lineSpacing: CGFloat = Typography.articleBodyLineSpacing,
        fontFamily: ReadingFontFamily = .notoSerif,
        textColor: Color = Color.folio.textPrimary,
        secondaryTextColor: Color = Color.folio.textSecondary
    ) {
        self.markdownText = markdownText
        self.fontSize = fontSize
        self.lineSpacing = lineSpacing
        self.fontFamily = fontFamily
        self.textColor = textColor
        self.secondaryTextColor = secondaryTextColor

        let document = Document(parsing: markdownText)
        var visitor = MarkdownSwiftUIVisitor(
            fontSize: fontSize,
            lineSpacing: lineSpacing,
            fontFamily: fontFamily,
            textColor: textColor,
            secondaryTextColor: secondaryTextColor
        )
        self.parsedBlocks = visitor.visitDocument(document)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            ForEach(parsedBlocks) { block in
                MarkdownBlockView(
                    block: block,
                    fontSize: fontSize,
                    lineSpacing: lineSpacing,
                    fontFamily: fontFamily,
                    textColor: textColor,
                    secondaryTextColor: secondaryTextColor
                )
            }
        }
    }
}

// MARK: - Visitor

/// A `MarkupVisitor` that produces an array of `MarkdownBlock` for each top-level
/// block element in the Markdown document.
struct MarkdownSwiftUIVisitor: MarkupVisitor {
    typealias Result = [MarkdownBlock]

    let fontSize: CGFloat
    let lineSpacing: CGFloat
    let fontFamily: ReadingFontFamily
    let textColor: Color
    let secondaryTextColor: Color

    private var nextID = 0

    init(
        fontSize: CGFloat,
        lineSpacing: CGFloat,
        fontFamily: ReadingFontFamily,
        textColor: Color,
        secondaryTextColor: Color
    ) {
        self.fontSize = fontSize
        self.lineSpacing = lineSpacing
        self.fontFamily = fontFamily
        self.textColor = textColor
        self.secondaryTextColor = secondaryTextColor
    }

    private mutating func makeID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    // MARK: - Document

    mutating func defaultVisit(_ markup: any Markup) -> [MarkdownBlock] {
        var result: [MarkdownBlock] = []
        for child in markup.children {
            result.append(contentsOf: visit(child))
        }
        return result
    }

    mutating func visitDocument(_ document: Document) -> [MarkdownBlock] {
        var result: [MarkdownBlock] = []
        for child in document.children {
            result.append(contentsOf: visit(child))
        }
        return result
    }

    // MARK: - Headings

    mutating func visitHeading(_ heading: Heading) -> [MarkdownBlock] {
        let text = collectInlineText(heading)
        return [.heading(id: makeID(), text: text, level: heading.level)]
    }

    // MARK: - Paragraph

    mutating func visitParagraph(_ paragraph: Paragraph) -> [MarkdownBlock] {
        let hasImages = paragraph.children.contains { $0 is Markdown.Image }

        if !hasImages {
            let text = collectInlineText(paragraph)
            return [.paragraph(id: makeID(), text: text)]
        }

        var result: [MarkdownBlock] = []
        var pendingInline: [any Markup] = []

        for child in paragraph.children {
            if let image = child as? Markdown.Image {
                flushInlineContent(&pendingInline, into: &result)
                let urlString = image.source ?? ""
                let altText = image.plainText
                result.append(.image(id: makeID(), urlString: urlString, altText: altText))
            } else {
                pendingInline.append(child)
            }
        }
        flushInlineContent(&pendingInline, into: &result)
        return result
    }

    private mutating func flushInlineContent(_ pending: inout [any Markup], into result: inout [MarkdownBlock]) {
        guard !pending.isEmpty else { return }
        let text = pending.reduce(SwiftUI.Text("")) { acc, node in
            acc + inlineText(node)
        }
        result.append(.paragraph(id: makeID(), text: text))
        pending.removeAll()
    }

    // MARK: - Code Block

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> [MarkdownBlock] {
        let language = codeBlock.language ?? ""
        let code = codeBlock.code.trimmingCharacters(in: .newlines)
        return [.codeBlock(id: makeID(), code: code, language: language)]
    }

    // MARK: - Block Quote

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> [MarkdownBlock] {
        var children: [MarkdownBlock] = []
        for child in blockQuote.children {
            children.append(contentsOf: visit(child))
        }
        return [.blockQuote(id: makeID(), children: children)]
    }

    // MARK: - Ordered List

    mutating func visitOrderedList(_ orderedList: OrderedList) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        for (index, item) in orderedList.children.enumerated() {
            guard let listItem = item as? ListItem else { continue }
            let itemBlocks = visitListItem(listItem)
            blocks.append(.orderedListItem(id: makeID(), index: index + 1, children: itemBlocks))
        }
        return blocks
    }

    // MARK: - Unordered List

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        for item in unorderedList.children {
            guard let listItem = item as? ListItem else { continue }
            let itemBlocks = visitListItem(listItem)
            blocks.append(.unorderedListItem(id: makeID(), children: itemBlocks))
        }
        return blocks
    }

    // MARK: - List Item

    mutating func visitListItem(_ listItem: ListItem) -> [MarkdownBlock] {
        var result: [MarkdownBlock] = []
        for child in listItem.children {
            result.append(contentsOf: visit(child))
        }
        return result
    }

    // MARK: - Thematic Break

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> [MarkdownBlock] {
        [.thematicBreak(id: makeID())]
    }

    // MARK: - Table

    mutating func visitTable(_ table: Markdown.Table) -> [MarkdownBlock] {
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

        return [.table(id: makeID(), headers: headerRow, rows: bodyRows)]
    }

    // MARK: - Image

    mutating func visitImage(_ image: Markdown.Image) -> [MarkdownBlock] {
        let urlString = image.source ?? ""
        let altText = image.plainText
        return [.image(id: makeID(), urlString: urlString, altText: altText)]
    }

    // MARK: - HTML Block

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> [MarkdownBlock] {
        [.htmlBlock(id: makeID(), rawHTML: html.rawHTML)]
    }

    // MARK: - Inline Text Collection

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
                .foregroundStyle(Color.folio.accent)
        } else if let link = markup as? Markdown.Link {
            if let dest = link.destination, let url = URL(string: dest) {
                var attrStr = AttributedString(plainText(link))
                attrStr.link = url
                return Text(attrStr)
            }
            return collectInlineText(link)
                .foregroundStyle(Color.folio.link)
                .underline()
        } else if markup is SoftBreak {
            return Text(" ")
        } else if markup is LineBreak {
            return Text("\n")
        } else if let image = markup as? Markdown.Image {
            return Text("[\(image.plainText)]")
                .foregroundStyle(Color.folio.link)
        } else if let strikethrough = markup as? Strikethrough {
            return collectInlineText(strikethrough).strikethrough()
        } else {
            var result = SwiftUI.Text("")
            for child in markup.children {
                result = result + inlineText(child)
            }
            return result
        }
    }

    // MARK: - Helpers

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

// MARK: - Content Preprocessing

extension MarkdownRenderer {
    static func preprocessed(
        _ markdown: String,
        title: String?
    ) -> String {
        var text = markdown

        if let title, !title.isEmpty {
            let normalizedTitle = title
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedText.hasPrefix(normalizedTitle) {
                let afterTitle = trimmedText.dropFirst(normalizedTitle.count)
                text = afterTitle
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        let metadataPatterns: [String] = [
            #"\[[\d,]+ Views?\]\([^\)]+/analytics\)"#,
            #"\[\d{1,2}:\d{2} [AP]M · .+?\]\([^\)]+\)"#,
        ]
        for pattern in metadataPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                text = regex.stringByReplacingMatches(
                    in: text,
                    range: NSRange(text.startIndex..., in: text),
                    withTemplate: ""
                )
            }
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
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
