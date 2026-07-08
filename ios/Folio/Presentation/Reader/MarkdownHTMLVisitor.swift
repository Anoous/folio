import Foundation
import Markdown

// MARK: - HTML Visitor

/// A `MarkupVisitor` that emits an HTML string from the swift-markdown AST.
struct MarkdownHTMLVisitor: MarkupVisitor {
    typealias Result = String

    // MARK: - Document

    mutating func defaultVisit(_ markup: any Markup) -> String {
        markup.children.map { visit($0) }.joined()
    }

    mutating func visitDocument(_ document: Document) -> String {
        document.children.map { visit($0) }.joined()
    }

    // MARK: - Block Elements

    mutating func visitHeading(_ heading: Heading) -> String {
        let level = min(heading.level, 6)
        let inner = heading.children.map { visit($0) }.joined()
        return "<h\(level)>\(inner)</h\(level)>\n"
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> String {
        let inner = paragraph.children.map { visit($0) }.joined()
        return "<p>\(inner)</p>\n"
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> String {
        let inner = blockQuote.children.map { visit($0) }.joined()
        return "<blockquote>\(inner)</blockquote>\n"
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> String {
        let code = escapeHTML(codeBlock.code.trimmingCharacters(in: .newlines))
        if let lang = codeBlock.language, !lang.isEmpty {
            return "<pre><code class=\"language-\(escapeHTML(lang))\">\(code)</code></pre>\n"
        }
        return "<pre><code>\(code)</code></pre>\n"
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) -> String {
        let inner = orderedList.children.map { visit($0) }.joined()
        return "<ol>\(inner)</ol>\n"
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> String {
        let inner = unorderedList.children.map { visit($0) }.joined()
        return "<ul>\(inner)</ul>\n"
    }

    mutating func visitListItem(_ listItem: ListItem) -> String {
        let inner = listItem.children.map { visit($0) }.joined()
        return "<li>\(inner)</li>\n"
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> String {
        "<hr>\n"
    }

    mutating func visitTable(_ table: Markdown.Table) -> String {
        var html = "<table>"
        for child in table.children {
            if let head = child as? Markdown.Table.Head {
                html += "<thead><tr>"
                for cell in head.children {
                    if let tableCell = cell as? Markdown.Table.Cell {
                        let inner = tableCell.children.map { visit($0) }.joined()
                        html += "<th>\(inner)</th>"
                    }
                }
                html += "</tr></thead>"
            } else if let body = child as? Markdown.Table.Body {
                html += "<tbody>"
                for row in body.children {
                    if let tableRow = row as? Markdown.Table.Row {
                        html += "<tr>"
                        for cell in tableRow.children {
                            if let tableCell = cell as? Markdown.Table.Cell {
                                let inner = tableCell.children.map { visit($0) }.joined()
                                html += "<td>\(inner)</td>"
                            }
                        }
                        html += "</tr>"
                    }
                }
                html += "</tbody>"
            }
        }
        html += "</table>\n"
        return html
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> String {
        html.rawHTML
    }

    // MARK: - Inline Elements

    mutating func visitText(_ text: Markdown.Text) -> String {
        escapeHTML(text.string)
    }

    mutating func visitStrong(_ strong: Strong) -> String {
        let inner = strong.children.map { visit($0) }.joined()
        return "<strong>\(inner)</strong>"
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> String {
        let inner = emphasis.children.map { visit($0) }.joined()
        return "<em>\(inner)</em>"
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> String {
        let inner = strikethrough.children.map { visit($0) }.joined()
        return "<del>\(inner)</del>"
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> String {
        "<code>\(escapeHTML(inlineCode.code))</code>"
    }

    mutating func visitLink(_ link: Markdown.Link) -> String {
        let href = link.destination ?? ""
        let inner = link.children.map { visit($0) }.joined()
        return "<a href=\"\(escapeHTML(href))\">\(inner)</a>"
    }

    mutating func visitImage(_ image: Markdown.Image) -> String {
        let src = image.source ?? ""
        let alt = image.plainText
        return "<img src=\"\(escapeHTML(src))\" alt=\"\(escapeHTML(alt))\">"
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> String {
        "\n"
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) -> String {
        "<br>\n"
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> String {
        inlineHTML.rawHTML
    }

    // MARK: - Helpers

    private func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
