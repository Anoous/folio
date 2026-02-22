import XCTest
@testable import Folio

final class HTMLToMarkdownConverterTests: XCTestCase {

    private let converter = HTMLToMarkdownConverter()

    // MARK: - Headings

    func testH1ToMarkdown() throws {
        let html = "<h1>Title</h1>"
        let md = try converter.convert(html: html)
        XCTAssertTrue(md.contains("# Title"))
    }

    func testH2ToMarkdown() throws {
        let html = "<h2>Subtitle</h2>"
        let md = try converter.convert(html: html)
        XCTAssertTrue(md.contains("## Subtitle"))
    }

    func testH3ToMarkdown() throws {
        let html = "<h3>Section</h3>"
        let md = try converter.convert(html: html)
        XCTAssertTrue(md.contains("### Section"))
    }

    func testH4ToH6() throws {
        XCTAssertTrue(try converter.convert(html: "<h4>H4</h4>").contains("#### H4"))
        XCTAssertTrue(try converter.convert(html: "<h5>H5</h5>").contains("##### H5"))
        XCTAssertTrue(try converter.convert(html: "<h6>H6</h6>").contains("###### H6"))
    }

    // MARK: - Paragraphs

    func testParagraph() throws {
        let html = "<p>Hello world</p>"
        let md = try converter.convert(html: html)
        XCTAssertTrue(md.contains("Hello world"))
    }

    func testEmptyParagraphSkipped() throws {
        let html = "<p></p><p>Content</p>"
        let md = try converter.convert(html: html)
        XCTAssertTrue(md.contains("Content"))
        // Should not have stray blank lines from empty paragraph
        XCTAssertFalse(md.contains("\n\n\n"))
    }

    // MARK: - Inline Formatting

    func testBold() throws {
        let html = "<p>This is <strong>bold</strong> text</p>"
        let md = try converter.convert(html: html)
        XCTAssertTrue(md.contains("**bold**"))
    }

    func testItalic() throws {
        let html = "<p>This is <em>italic</em> text</p>"
        let md = try converter.convert(html: html)
        XCTAssertTrue(md.contains("*italic*"))
    }

    func testStrikethrough() throws {
        let html = "<p>This is <del>deleted</del> text</p>"
        let md = try converter.convert(html: html)
        XCTAssertTrue(md.contains("~~deleted~~"))
    }

    func testInlineCode() throws {
        let html = "<p>Use <code>let x = 1</code> to declare</p>"
        let md = try converter.convert(html: html)
        XCTAssertTrue(md.contains("`let x = 1`"))
    }

    // MARK: - Links and Images

    func testLink() throws {
        let html = "<p>Visit <a href=\"https://example.com\">Example</a></p>"
        let md = try converter.convert(html: html)
        XCTAssertTrue(md.contains("[Example](https://example.com)"))
    }

    func testImage() throws {
        let html = "<img src=\"https://example.com/img.png\" alt=\"Photo\">"
        let md = try converter.convert(html: html)
        XCTAssertTrue(md.contains("![Photo](https://example.com/img.png)"))
    }

    func testImageNoSrc() throws {
        let html = "<img alt=\"No source\">"
        let md = try converter.convert(html: html)
        XCTAssertFalse(md.contains("!["))
    }

    // MARK: - Lists

    func testUnorderedList() throws {
        let html = "<ul><li>Item 1</li><li>Item 2</li></ul>"
        let md = try converter.convert(html: html)
        XCTAssertTrue(md.contains("- Item 1"))
        XCTAssertTrue(md.contains("- Item 2"))
    }

    func testOrderedList() throws {
        let html = "<ol><li>First</li><li>Second</li></ol>"
        let md = try converter.convert(html: html)
        XCTAssertTrue(md.contains("1. First"))
        XCTAssertTrue(md.contains("2. Second"))
    }

    // MARK: - Code Blocks

    func testPreCodeBlock() throws {
        let html = "<pre><code class=\"language-swift\">let x = 1</code></pre>"
        let md = try converter.convert(html: html)
        XCTAssertTrue(md.contains("```swift"))
        XCTAssertTrue(md.contains("let x = 1"))
        XCTAssertTrue(md.contains("```"))
    }

    func testPreBlockNoLanguage() throws {
        let html = "<pre><code>some code</code></pre>"
        let md = try converter.convert(html: html)
        XCTAssertTrue(md.contains("```\n"))
        XCTAssertTrue(md.contains("some code"))
    }

    // MARK: - Blockquote

    func testBlockquote() throws {
        let html = "<blockquote><p>A wise quote</p></blockquote>"
        let md = try converter.convert(html: html)
        XCTAssertTrue(md.contains("> "))
        XCTAssertTrue(md.contains("A wise quote"))
    }

    // MARK: - Horizontal Rule

    func testHorizontalRule() throws {
        let html = "<p>Before</p><hr><p>After</p>"
        let md = try converter.convert(html: html)
        XCTAssertTrue(md.contains("---"))
    }

    // MARK: - Table

    func testTable() throws {
        let html = """
        <table>
            <thead><tr><th>Name</th><th>Value</th></tr></thead>
            <tbody><tr><td>A</td><td>1</td></tr></tbody>
        </table>
        """
        let md = try converter.convert(html: html)
        XCTAssertTrue(md.contains("| Name | Value |"))
        XCTAssertTrue(md.contains("| --- | --- |"))
        XCTAssertTrue(md.contains("| A | 1 |"))
    }

    // MARK: - Nested Structures

    func testNestedBoldInParagraph() throws {
        let html = "<p>This has <strong>bold and <em>italic</em></strong> text</p>"
        let md = try converter.convert(html: html)
        XCTAssertTrue(md.contains("**bold and *italic***"))
    }

    // MARK: - Edge Cases

    func testEmptyInput() throws {
        let md = try converter.convert(html: "")
        XCTAssertEqual(md, "")
    }

    func testWhitespaceOnlyInput() throws {
        let md = try converter.convert(html: "   \n\n   ")
        XCTAssertEqual(md, "")
    }

    func testNoExcessiveBlankLines() throws {
        let html = "<p>One</p><p>Two</p><p>Three</p>"
        let md = try converter.convert(html: html)
        XCTAssertFalse(md.contains("\n\n\n"))
    }

    // MARK: - Fixture Files

    func testSimpleBlogFixture() throws {
        let html = try loadFixture("simple-blog.html")
        let md = try converter.convert(html: html)

        XCTAssertTrue(md.contains("# Understanding Swift Concurrency"))
        XCTAssertTrue(md.contains("## Async/Await Basics"))
        XCTAssertTrue(md.contains("`async`"))
        XCTAssertTrue(md.contains("```swift"))
        XCTAssertTrue(md.contains("**data isolation**"))
        XCTAssertTrue(md.contains("*data races*"))
        XCTAssertTrue(md.contains("- Actor types are reference types"))
        XCTAssertTrue(md.contains("[official documentation](https://swift.org/concurrency)"))
    }

    func testChineseContentFixture() throws {
        let html = try loadFixture("chinese-content.html")
        let md = try converter.convert(html: html)

        XCTAssertTrue(md.contains("# 深入理解Swift并发编程"))
        XCTAssertTrue(md.contains("## 基础概念"))
        XCTAssertTrue(md.contains("1. 定义异步函数"))
        XCTAssertTrue(md.contains("| 特性 | 说明 |"))
    }

    // MARK: - Helpers

    private func loadFixture(_ name: String) throws -> String {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: name, withExtension: nil, subdirectory: nil)
            ?? bundle.url(forResource: name.replacingOccurrences(of: ".html", with: ""), withExtension: "html") else {
            // Fallback: read directly from source
            let path = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Fixtures/Extraction/\(name)")
            return try String(contentsOf: path, encoding: .utf8)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
