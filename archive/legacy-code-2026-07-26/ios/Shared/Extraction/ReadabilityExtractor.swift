import Foundation
import SwiftSoup

struct ReadabilityResult {
    let title: String?
    let author: String?
    let siteName: String?
    let excerpt: String?
    let contentHTML: String
}

struct ReadabilityExtractor {

    func extract(html: String, url: URL) throws -> ReadabilityResult {
        let document = try SwiftSoup.parse(html, url.absoluteString)

        let title = extractTitle(from: document)
        let author = extractAuthor(from: document)
        let siteName = extractSiteName(from: document)
        let excerpt = extractExcerpt(from: document)
        let contentElement = extractContent(from: document)
        let contentHTML = try contentElement?.html() ?? ""

        return ReadabilityResult(
            title: title,
            author: author,
            siteName: siteName,
            excerpt: excerpt,
            contentHTML: contentHTML
        )
    }

    // MARK: - Metadata Extraction

    private func extractTitle(from doc: Document) -> String? {
        // Try og:title
        if let ogTitle = try? doc.select("meta[property=og:title]").first()?.attr("content"),
           !ogTitle.isEmpty {
            return ogTitle
        }
        // Try <title>
        if let title = try? doc.title(), !title.isEmpty {
            return cleanTitle(title)
        }
        // Try h1
        if let h1 = try? doc.select("h1").first()?.text(), !h1.isEmpty {
            return h1
        }
        return nil
    }

    private func cleanTitle(_ title: String) -> String {
        // Remove site name suffixes like " - Site Name" or " | Site Name"
        let separators = [" - ", " | ", " :: ", " / ", " >> "]
        for separator in separators {
            if let range = title.range(of: separator, options: .backwards) {
                let candidate = String(title[title.startIndex..<range.lowerBound])
                if candidate.count > 10 {
                    return candidate.trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return title
    }

    private func extractAuthor(from doc: Document) -> String? {
        // Try meta author
        if let author = try? doc.select("meta[name=author]").first()?.attr("content"),
           !author.isEmpty {
            return author
        }
        // Try article:author
        if let author = try? doc.select("meta[property=article:author]").first()?.attr("content"),
           !author.isEmpty {
            return author
        }
        // Try common author selectors
        let selectors = [".author", "[rel=author]", ".byline", "[itemprop=author]"]
        for selector in selectors {
            if let author = try? doc.select(selector).first()?.text(),
               !author.isEmpty, author.count < 100 {
                return author
            }
        }
        return nil
    }

    private func extractSiteName(from doc: Document) -> String? {
        if let siteName = try? doc.select("meta[property=og:site_name]").first()?.attr("content"),
           !siteName.isEmpty {
            return siteName
        }
        return nil
    }

    private func extractExcerpt(from doc: Document) -> String? {
        if let desc = try? doc.select("meta[property=og:description]").first()?.attr("content"),
           !desc.isEmpty {
            return desc
        }
        if let desc = try? doc.select("meta[name=description]").first()?.attr("content"),
           !desc.isEmpty {
            return desc
        }
        return nil
    }

    // MARK: - Content Extraction

    private func extractContent(from doc: Document) -> Element? {
        // Try common article containers
        let articleSelectors = [
            "article",
            "[role=main]",
            ".post-content",
            ".article-content",
            ".entry-content",
            ".content",
            "#article-content",
            "#content",
            ".rich_media_content",     // WeChat
            ".Post-RichTextContainer", // Zhihu
            "main",
        ]

        for selector in articleSelectors {
            if let element = try? doc.select(selector).first() {
                let text = (try? element.text()) ?? ""
                if text.count >= 50 {
                    cleanElement(element)
                    return element
                }
            }
        }

        // Fallback: score-based extraction
        return scoreBased(doc: doc)
    }

    private func scoreBased(doc: Document) -> Element? {
        guard let body = doc.body() else { return nil }

        var candidates: [(Element, Double)] = []
        guard let allElements = try? body.select("div, section, article, td") else { return nil }

        for element in allElements {
            let text = (try? element.text()) ?? ""
            guard text.count >= 50 else { continue }

            var score: Double = 0

            // Positive signals
            let className = (try? element.className()) ?? ""
            let id = element.id()
            let positivePatterns = ["article", "content", "post", "body", "text", "entry", "main"]
            for pattern in positivePatterns {
                if className.lowercased().contains(pattern) { score += 25 }
                if id.lowercased().contains(pattern) { score += 25 }
            }

            // Negative signals
            let negativePatterns = ["comment", "sidebar", "nav", "footer", "header", "menu", "ad", "social", "share", "related"]
            for pattern in negativePatterns {
                if className.lowercased().contains(pattern) { score -= 25 }
                if id.lowercased().contains(pattern) { score -= 25 }
            }

            // Text density
            let pCount = (try? element.select("p").size()) ?? 0
            score += Double(pCount) * 3

            // Text length bonus
            score += Double(text.count) / 100.0

            // Link density penalty
            let linkTextLength = ((try? element.select("a").text().count) ?? 0)
            if text.count > 0 {
                let linkDensity = Double(linkTextLength) / Double(text.count)
                if linkDensity > 0.5 { score -= 50 }
            }

            candidates.append((element, score))
        }

        guard let best = candidates.max(by: { $0.1 < $1.1 }), best.1 > 0 else {
            return body
        }

        cleanElement(best.0)
        return best.0
    }

    private func cleanElement(_ element: Element) {
        let removeSelectors = [
            "script", "style", "nav", "footer", "header",
            ".sidebar", ".comments", ".ad", ".social-share",
            ".related-posts", ".navigation", "[role=navigation]",
            "iframe", "form", ".share-buttons",
        ]
        for selector in removeSelectors {
            if let elements = try? element.select(selector) {
                for el in elements {
                    try? el.remove()
                }
            }
        }
    }
}
