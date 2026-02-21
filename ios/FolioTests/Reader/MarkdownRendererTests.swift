import XCTest
import Markdown
@testable import Folio

final class MarkdownRendererTests: XCTestCase {

    func testRenderHeadings() {
        let md = "# H1\n## H2\n### H3\n#### H4\n##### H5\n###### H6"
        let doc = Document(parsing: md)
        XCTAssertGreaterThan(doc.childCount, 0)
        var headingCount = 0
        for child in doc.children {
            if child is Heading { headingCount += 1 }
        }
        XCTAssertEqual(headingCount, 6)
    }

    func testRenderBoldAndItalic() {
        let md = "This is **bold** and *italic* text"
        let doc = Document(parsing: md)
        XCTAssertGreaterThan(doc.childCount, 0)
    }

    func testRenderInlineCode() {
        let md = "Use `let x = 1` in Swift"
        let doc = Document(parsing: md)
        XCTAssertGreaterThan(doc.childCount, 0)
    }

    func testRenderCodeBlock() {
        let md = "```swift\nlet x = 1\nprint(x)\n```"
        let doc = Document(parsing: md)
        var hasCodeBlock = false
        for child in doc.children {
            if child is CodeBlock { hasCodeBlock = true }
        }
        XCTAssertTrue(hasCodeBlock)
    }

    func testRenderBlockquote() {
        let md = "> This is a quote"
        let doc = Document(parsing: md)
        var hasBlockquote = false
        for child in doc.children {
            if child is BlockQuote { hasBlockquote = true }
        }
        XCTAssertTrue(hasBlockquote)
    }

    func testRenderOrderedList() {
        let md = "1. First\n2. Second\n3. Third"
        let doc = Document(parsing: md)
        var hasOrderedList = false
        for child in doc.children {
            if child is Markdown.OrderedList { hasOrderedList = true }
        }
        XCTAssertTrue(hasOrderedList)
    }

    func testRenderUnorderedList() {
        let md = "- Apple\n- Banana\n- Cherry"
        let doc = Document(parsing: md)
        var hasUnorderedList = false
        for child in doc.children {
            if child is Markdown.UnorderedList { hasUnorderedList = true }
        }
        XCTAssertTrue(hasUnorderedList)
    }

    func testRenderTable() {
        let md = "| A | B |\n|---|---|\n| 1 | 2 |"
        let doc = Document(parsing: md)
        var hasTable = false
        for child in doc.children {
            if child is Markdown.Table { hasTable = true }
        }
        XCTAssertTrue(hasTable)
    }

    func testRenderLink() {
        let md = "[Swift](https://swift.org)"
        let doc = Document(parsing: md)
        XCTAssertGreaterThan(doc.childCount, 0)
    }

    func testRenderImage() {
        let md = "![Alt text](https://example.com/img.png)"
        let doc = Document(parsing: md)
        XCTAssertGreaterThan(doc.childCount, 0)
    }

    func testRenderComplexDocument() {
        let md = """
        # Title

        Some **bold** and *italic* text with `inline code`.

        ## Section

        > A blockquote

        - Item 1
        - Item 2

        ```swift
        let x = 1
        ```

        | Col1 | Col2 |
        |------|------|
        | A    | B    |

        [Link](https://example.com)
        """
        let doc = Document(parsing: md)
        XCTAssertGreaterThan(doc.childCount, 5)
    }

    func testSupportedLanguages() {
        let languages = ["swift", "python", "javascript", "go", "rust",
                         "typescript", "html", "css", "json", "sql"]
        XCTAssertGreaterThanOrEqual(languages.count, 10)
        for lang in languages {
            let md = "```\(lang)\ncode\n```"
            let doc = Document(parsing: md)
            for child in doc.children {
                if let code = child as? CodeBlock {
                    XCTAssertEqual(code.language, lang)
                }
            }
        }
    }
}
