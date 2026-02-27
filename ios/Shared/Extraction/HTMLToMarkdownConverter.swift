import Foundation
import SwiftSoup

struct HTMLToMarkdownConverter {

    func convert(html: String) throws -> String {
        guard !html.isEmpty else { return "" }
        let document = try SwiftSoup.parseBodyFragment(html)
        guard let body = document.body() else { return "" }
        let result = convertElement(body)
        return cleanMarkdown(result)
    }

    // MARK: - Element Conversion

    private func convertElement(_ element: Element) -> String {
        var result = ""

        for node in element.getChildNodes() {
            if let textNode = node as? TextNode {
                let text = textNode.getWholeText()
                let trimmed = text.replacingOccurrences(of: "\n", with: " ")
                result += trimmed
            } else if let el = node as? Element {
                result += convertTag(el)
            }
        }

        return result
    }

    private func convertTag(_ element: Element) -> String {
        let tag = element.tagName().lowercased()

        switch tag {
        case "h1": return "\n\n# \(convertElement(element).trimmedInline())\n\n"
        case "h2": return "\n\n## \(convertElement(element).trimmedInline())\n\n"
        case "h3": return "\n\n### \(convertElement(element).trimmedInline())\n\n"
        case "h4": return "\n\n#### \(convertElement(element).trimmedInline())\n\n"
        case "h5": return "\n\n##### \(convertElement(element).trimmedInline())\n\n"
        case "h6": return "\n\n###### \(convertElement(element).trimmedInline())\n\n"

        case "p":
            let inner = convertElement(element).trimmedInline()
            guard !inner.isEmpty else { return "" }
            return "\n\n\(inner)\n\n"

        case "br": return "\n"

        case "strong", "b":
            let inner = convertElement(element).trimmedInline()
            guard !inner.isEmpty else { return "" }
            return "**\(inner)**"

        case "em", "i":
            let inner = convertElement(element).trimmedInline()
            guard !inner.isEmpty else { return "" }
            return "*\(inner)*"

        case "del", "s", "strike":
            let inner = convertElement(element).trimmedInline()
            guard !inner.isEmpty else { return "" }
            return "~~\(inner)~~"

        case "code":
            // Inline code (not inside pre)
            let inner = (try? element.text()) ?? ""
            guard !inner.isEmpty else { return "" }
            return "`\(inner)`"

        case "pre":
            return convertPreBlock(element)

        case "a":
            return convertLink(element)

        case "img":
            return convertImage(element)

        case "ul":
            return convertList(element, ordered: false)

        case "ol":
            return convertList(element, ordered: true)

        case "li":
            return convertElement(element).trimmedInline()

        case "blockquote":
            let inner = convertElement(element)
            let lines = inner.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: "\n")
                .map { "> \($0)" }
                .joined(separator: "\n")
            return "\n\n\(lines)\n\n"

        case "hr":
            return "\n\n---\n\n"

        case "table":
            return convertTable(element)

        default:
            return convertElement(element)
        }
    }

    // MARK: - Specific Converters

    private func convertPreBlock(_ element: Element) -> String {
        let codeElement = try? element.select("code").first()
        let target = codeElement ?? element
        let rawText = (try? target.text(trimAndNormaliseWhitespace: false)) ?? ""

        // Detect language from class
        var language = ""
        let className = (try? (codeElement ?? element).className()) ?? ""
        if let match = className.range(of: #"language-(\w+)"#, options: .regularExpression) {
            language = String(className[match]).replacingOccurrences(of: "language-", with: "")
        } else if let match = className.range(of: #"lang-(\w+)"#, options: .regularExpression) {
            language = String(className[match]).replacingOccurrences(of: "lang-", with: "")
        }

        return "\n\n```\(language)\n\(rawText)\n```\n\n"
    }

    private func convertLink(_ element: Element) -> String {
        let href = (try? element.attr("href")) ?? ""
        let text = convertElement(element).trimmedInline()

        guard !text.isEmpty else { return "" }
        guard !href.isEmpty else { return text }

        return "[\(text)](\(href))"
    }

    private func convertImage(_ element: Element) -> String {
        let src = (try? element.attr("src")) ?? ""
        let alt = (try? element.attr("alt")) ?? ""

        guard !src.isEmpty else { return "" }
        return "\n\n![\(alt)](\(src))\n\n"
    }

    private func convertList(_ element: Element, ordered: Bool) -> String {
        var result = "\n\n"
        let items = (try? element.select(":root > li")) ?? Elements()
        for (index, item) in items.array().enumerated() {
            let inner = convertElement(item).trimmedInline()
            let bullet = ordered ? "\(index + 1)." : "-"
            result += "\(bullet) \(inner)\n"
        }
        result += "\n"
        return result
    }

    private func convertTable(_ element: Element) -> String {
        var rows: [[String]] = []

        // Get header row
        if let thead = try? element.select("thead tr").first() {
            let cells = (try? thead.select("th, td")) ?? Elements()
            let row = cells.array().map { (try? $0.text()) ?? "" }
            if !row.isEmpty { rows.append(row) }
        }

        // Get body rows
        let bodyRows = (try? element.select("tbody tr, :root > tr")) ?? Elements()
        for tr in bodyRows {
            let cells = (try? tr.select("td, th")) ?? Elements()
            let row = cells.array().map { (try? $0.text()) ?? "" }
            if !row.isEmpty { rows.append(row) }
        }

        guard !rows.isEmpty else { return "" }

        let colCount = rows.map(\.count).max() ?? 0
        guard colCount > 0 else { return "" }

        // Normalize row lengths
        let normalizedRows = rows.map { row -> [String] in
            var r = row
            while r.count < colCount { r.append("") }
            return r
        }

        var result = "\n\n"

        // Header
        let header = normalizedRows[0]
        result += "| " + header.joined(separator: " | ") + " |\n"
        result += "| " + header.map { _ in "---" }.joined(separator: " | ") + " |\n"

        // Body
        for row in normalizedRows.dropFirst() {
            result += "| " + row.joined(separator: " | ") + " |\n"
        }

        result += "\n"
        return result
    }

    // MARK: - Cleanup

    private func cleanMarkdown(_ text: String) -> String {
        text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - String Helper

private extension String {
    func trimmedInline() -> String {
        let lines = components(separatedBy: .newlines)
        return lines.map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "  ", with: " ")
    }
}
