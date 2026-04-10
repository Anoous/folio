import XCTest
@testable import Folio

final class MarkdownToHTMLTests: XCTestCase {

    func testConvertWithHeader_progressTracksArticleBodyOnly() {
        let html = MarkdownToHTML.convertWithHeader(
            markdown: "Body paragraph",
            header: .init(
                title: "Title",
                siteName: "Example",
                author: "Author",
                readingTime: "2 min read",
                dateLabel: "today",
                summary: "Summary",
                keyPoints: []
            ),
            highlights: [],
            fontSize: 17,
            lineSpacing: 11.9,
            fontFamily: .notoSerif,
            theme: .system
        )

        XCTAssertTrue(html.contains("function articleBodyMetrics()"))
        XCTAssertTrue(html.contains("var numerator = window.scrollY - metrics.top;"))
        XCTAssertTrue(html.contains("window.scrollTo(0, metrics.top + metrics.scrollable * clamped);"))
        XCTAssertFalse(html.contains("var pct = window.scrollY / Math.max(1, document.body.scrollHeight - window.innerHeight);"))
        XCTAssertFalse(html.contains("window.scrollTo(0, (document.body.scrollHeight - window.innerHeight) * pct);"))
    }
}
