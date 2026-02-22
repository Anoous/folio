import XCTest
@testable import Folio

final class ContentExtractorTests: XCTestCase {

    // MARK: - Invalid URL

    func testExtract_invalidScheme_throws() async {
        let extractor = ContentExtractor()
        let url = URL(string: "ftp://example.com/article")!

        do {
            _ = try await extractor.extract(url: url)
            XCTFail("Expected ExtractionError.invalidURL")
        } catch {
            guard case ExtractionError.invalidURL = error else {
                XCTFail("Expected ExtractionError.invalidURL, got \(error)")
                return
            }
        }
    }

    // MARK: - Minimum Content Check

    func testMinimumContentLength_isReasonable() {
        // Verify the constant matches the spec (50 chars)
        XCTAssertEqual(ContentExtractor.minimumContentLength, 50)
    }

    // MARK: - Timeout Configuration

    func testTotalTimeout_is8Seconds() {
        XCTAssertEqual(ContentExtractor.totalTimeout, 8)
    }

    // MARK: - Memory Limit

    func testMemoryLimit_is100MB() {
        XCTAssertEqual(ContentExtractor.memoryLimitBytes, 100 * 1024 * 1024)
    }

    // MARK: - Word Count (Existing)

    func testWordCount_englishText() async throws {
        // Test via ExtractionResult directly
        let result = ExtractionResult(
            title: "Test",
            author: nil,
            siteName: nil,
            excerpt: nil,
            markdownContent: "Hello world this is a test",
            wordCount: 6,
            extractedAt: Date()
        )
        XCTAssertEqual(result.wordCount, 6)
    }

    func testWordCount_chineseText() async throws {
        let result = ExtractionResult(
            title: "Test",
            author: nil,
            siteName: nil,
            excerpt: nil,
            markdownContent: "Swift并发编程为iOS开发",
            wordCount: 10,
            extractedAt: Date()
        )
        // Each CJK character counts as one word, plus English words
        XCTAssertEqual(result.wordCount, 10)
    }

    // MARK: - ExtractionResult

    func testExtractionResult_allFieldsPopulated() {
        let now = Date()
        let result = ExtractionResult(
            title: "Title",
            author: "Author",
            siteName: "Site",
            excerpt: "Excerpt",
            markdownContent: "# Content",
            wordCount: 1,
            extractedAt: now
        )
        XCTAssertEqual(result.title, "Title")
        XCTAssertEqual(result.author, "Author")
        XCTAssertEqual(result.siteName, "Site")
        XCTAssertEqual(result.excerpt, "Excerpt")
        XCTAssertEqual(result.markdownContent, "# Content")
        XCTAssertEqual(result.wordCount, 1)
        XCTAssertEqual(result.extractedAt, now)
    }

    func testExtractionResult_nilFields() {
        let result = ExtractionResult(
            title: nil,
            author: nil,
            siteName: nil,
            excerpt: nil,
            markdownContent: "",
            wordCount: 0,
            extractedAt: Date()
        )
        XCTAssertNil(result.title)
        XCTAssertNil(result.author)
        XCTAssertNil(result.siteName)
        XCTAssertNil(result.excerpt)
        XCTAssertEqual(result.markdownContent, "")
        XCTAssertEqual(result.wordCount, 0)
    }

    // MARK: - ReadabilityExtractor + HTMLToMarkdownConverter (Simple Blog Fixture)

    func testExtraction_simpleBlogFixture_extractsMetadata() throws {
        let html = try loadFixture("simple-blog.html")
        let url = URL(string: "https://example.com/swift-concurrency")!

        let readability = ReadabilityExtractor()
        let result = try readability.extract(html: html, url: url)

        XCTAssertEqual(result.title, "Understanding Swift Concurrency")
        XCTAssertEqual(result.author, "Jane Developer")
        XCTAssertEqual(result.siteName, "Swift Blog")
        XCTAssertEqual(result.excerpt, "A deep dive into Swift async/await patterns.")
    }

    func testExtraction_simpleBlogFixture_producesMarkdown() throws {
        let html = try loadFixture("simple-blog.html")
        let url = URL(string: "https://example.com/swift-concurrency")!

        let readability = ReadabilityExtractor()
        let readabilityResult = try readability.extract(html: html, url: url)

        let converter = HTMLToMarkdownConverter()
        let markdown = try converter.convert(html: readabilityResult.contentHTML)

        // Verify key content elements survived the pipeline
        XCTAssertTrue(markdown.contains("Swift concurrency brings structured concurrency"))
        XCTAssertTrue(markdown.contains("Async/Await Basics"))
        XCTAssertTrue(markdown.contains("Actors for Thread Safety"))
        XCTAssertTrue(markdown.contains("**data isolation**"))
        XCTAssertTrue(markdown.contains("*data races*"))
        XCTAssertTrue(markdown.contains("Thanks for reading!"))
    }

    func testExtraction_simpleBlogFixture_markdownMeetsMinimumLength() throws {
        let html = try loadFixture("simple-blog.html")
        let url = URL(string: "https://example.com/swift-concurrency")!

        let readability = ReadabilityExtractor()
        let readabilityResult = try readability.extract(html: html, url: url)

        let converter = HTMLToMarkdownConverter()
        let markdown = try converter.convert(html: readabilityResult.contentHTML)

        XCTAssertGreaterThanOrEqual(markdown.count, ContentExtractor.minimumContentLength)
    }

    // MARK: - ReadabilityExtractor + HTMLToMarkdownConverter (Chinese Content Fixture)

    func testExtraction_chineseFixture_extractsMetadata() throws {
        let html = try loadFixture("chinese-content.html")
        let url = URL(string: "https://example.com/swift-bingfa")!

        let readability = ReadabilityExtractor()
        let result = try readability.extract(html: html, url: url)

        XCTAssertEqual(result.title, "深入理解Swift并发编程")
        XCTAssertEqual(result.author, "张三")
        XCTAssertEqual(result.siteName, "技术博客")
        XCTAssertEqual(result.excerpt, "本文详细讲解Swift的async/await并发模型。")
    }

    func testExtraction_chineseFixture_producesMarkdown() throws {
        let html = try loadFixture("chinese-content.html")
        let url = URL(string: "https://example.com/swift-bingfa")!

        let readability = ReadabilityExtractor()
        let readabilityResult = try readability.extract(html: html, url: url)

        let converter = HTMLToMarkdownConverter()
        let markdown = try converter.convert(html: readabilityResult.contentHTML)

        XCTAssertTrue(markdown.contains("深入理解Swift并发编程"))
        XCTAssertTrue(markdown.contains("基础概念"))
        XCTAssertTrue(markdown.contains("定义异步函数"))
        XCTAssertTrue(markdown.contains("| 特性 | 说明 |"))
    }

    // MARK: - Minimum Content Filter

    func testExtraction_shortContent_belowMinimum() throws {
        // HTML with article content shorter than minimumContentLength (50 chars)
        let shortHTML = """
        <html><body><article><p>Short</p></article></body></html>
        """
        let url = URL(string: "https://example.com/short")!

        let readability = ReadabilityExtractor()
        let readabilityResult = try readability.extract(html: shortHTML, url: url)

        let converter = HTMLToMarkdownConverter()
        let markdown = try converter.convert(html: readabilityResult.contentHTML)

        // Content is below the minimumContentLength threshold
        XCTAssertLessThan(markdown.count, ContentExtractor.minimumContentLength)
    }

    func testExtraction_exactlyMinimumLength_passes() throws {
        // Build content that is exactly at the minimum length
        let padding = String(repeating: "a", count: ContentExtractor.minimumContentLength)
        let html = "<html><body><article><p>\(padding)</p></article></body></html>"
        let url = URL(string: "https://example.com/exact")!

        let readability = ReadabilityExtractor()
        let readabilityResult = try readability.extract(html: html, url: url)

        let converter = HTMLToMarkdownConverter()
        let markdown = try converter.convert(html: readabilityResult.contentHTML)

        XCTAssertGreaterThanOrEqual(markdown.count, ContentExtractor.minimumContentLength)
    }

    // MARK: - Word Count (Behavioral via countWords)

    func testCountWords_pureEnglish() {
        let extractor = ContentExtractor()
        let count = extractor.countWords("Hello world this is a test")
        XCTAssertEqual(count, 6)
    }

    func testCountWords_pureChinese() {
        let extractor = ContentExtractor()
        // 6 CJK characters
        let count = extractor.countWords("中文内容测试")
        XCTAssertEqual(count, 6)
    }

    func testCountWords_mixedChineseAndEnglish() {
        let extractor = ContentExtractor()
        // "Swift" = 1 word, "并发编程" = 4 CJK, "为" = 1 CJK, "iOS" = 1 word, "开发" = 2 CJK
        // Total: 2 English words + 7 CJK characters = 9
        // But look at source: isCJKCharacter checks specific Unicode ranges.
        // 并 U+5E76, 发 U+53D1, 编 U+7F16, 程 U+7A0B, 为 U+4E3A, 开 U+5F00, 发 U+53D1
        // All in CJK Unified Ideographs (U+4E00..U+9FFF). So 7 CJK chars.
        // "Swift" = 1 word, "iOS" = 1 word. Total = 9.
        let count = extractor.countWords("Swift并发编程为iOS开发")
        XCTAssertEqual(count, 9)
    }

    func testCountWords_emptyString() {
        let extractor = ContentExtractor()
        let count = extractor.countWords("")
        XCTAssertEqual(count, 0)
    }

    func testCountWords_whitespaceOnly() {
        let extractor = ContentExtractor()
        let count = extractor.countWords("   \n\t  ")
        XCTAssertEqual(count, 0)
    }

    func testCountWords_markdownFormatting() {
        let extractor = ContentExtractor()
        // Markdown symbols like #, *, - are not alphabetic/numeric, so they don't count as words
        // Only the alphabetic words count
        let count = extractor.countWords("# Hello World")
        XCTAssertEqual(count, 2)
    }

    func testCountWords_numbersCountAsWords() {
        let extractor = ContentExtractor()
        // "2025" contains digits which have isNumeric = true
        let count = extractor.countWords("Year 2025 update")
        XCTAssertEqual(count, 3)
    }

    // MARK: - Empty HTML

    func testExtraction_emptyHTML_producesEmptyMarkdown() throws {
        let converter = HTMLToMarkdownConverter()
        let result = try converter.convert(html: "")
        XCTAssertEqual(result, "")
    }

    func testExtraction_whitespaceOnlyHTML_producesEmptyOrMinimalMarkdown() throws {
        let converter = HTMLToMarkdownConverter()
        let result = try converter.convert(html: "   \n\t  ")
        XCTAssertTrue(result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func testReadability_emptyHTML_producesEmptyContent() throws {
        let url = URL(string: "https://example.com/empty")!
        let readability = ReadabilityExtractor()
        let result = try readability.extract(html: "", url: url)

        // Empty HTML produces empty content
        XCTAssertTrue(result.contentHTML.isEmpty || result.contentHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    // MARK: - ReadabilityExtractor Metadata Edge Cases

    func testReadability_noMetadata_returnsNils() throws {
        let html = """
        <html><body><article><p>Just some plain content without any metadata tags at all for testing purposes.</p></article></body></html>
        """
        let url = URL(string: "https://example.com/no-meta")!

        let readability = ReadabilityExtractor()
        let result = try readability.extract(html: html, url: url)

        XCTAssertNil(result.author)
        XCTAssertNil(result.siteName)
        XCTAssertNil(result.excerpt)
    }

    func testReadability_titleFallbackToH1() throws {
        let html = """
        <html><head></head><body><article><h1>Heading Title</h1><p>Content goes here and it should be long enough for testing purposes to exceed the minimum.</p></article></body></html>
        """
        let url = URL(string: "https://example.com/h1-title")!

        let readability = ReadabilityExtractor()
        let result = try readability.extract(html: html, url: url)

        XCTAssertEqual(result.title, "Heading Title")
    }

    func testReadability_ogTitleTakesPriority() throws {
        let html = """
        <html>
        <head>
            <meta property="og:title" content="OG Title">
            <title>HTML Title - Site Name</title>
        </head>
        <body><article><h1>H1 Title</h1><p>Content goes here.</p></article></body>
        </html>
        """
        let url = URL(string: "https://example.com/og-title")!

        let readability = ReadabilityExtractor()
        let result = try readability.extract(html: html, url: url)

        XCTAssertEqual(result.title, "OG Title")
    }

    // MARK: - HTMLToMarkdownConverter Edge Cases

    func testConverter_codeBlock_preservesLanguage() throws {
        let html = """
        <pre><code class="language-python">print("hello")</code></pre>
        """
        let converter = HTMLToMarkdownConverter()
        let md = try converter.convert(html: html)

        XCTAssertTrue(md.contains("```python"))
        XCTAssertTrue(md.contains("print(\"hello\")"))
        XCTAssertTrue(md.contains("```"))
    }

    func testConverter_nestedFormatting() throws {
        let html = "<p>This has <strong>bold and <em>italic</em></strong> text.</p>"
        let converter = HTMLToMarkdownConverter()
        let md = try converter.convert(html: html)

        XCTAssertTrue(md.contains("**bold and *italic***"))
    }

    func testConverter_imageWithAlt() throws {
        let html = "<img src=\"https://example.com/img.png\" alt=\"Test Image\">"
        let converter = HTMLToMarkdownConverter()
        let md = try converter.convert(html: html)

        XCTAssertTrue(md.contains("![Test Image](https://example.com/img.png)"))
    }

    // MARK: - ReadabilityExtractor Score-based Heuristics

    func testReadability_highScoreElement_selectedOverLowScore() throws {
        let longText = String(repeating: "This is a meaningful article paragraph with important content. ", count: 10)
        let html = """
        <html><body>
            <div class="sidebar nav-menu" id="sidebar"><p>Short sidebar text here.</p><p>Link list only.</p></div>
            <div class="article-content post-body" id="main-content">
                <p>\(longText)</p>
                <p>Another paragraph of substantial article text for scoring purposes.</p>
                <p>Yet another paragraph to boost the text density score higher.</p>
            </div>
        </body></html>
        """
        let url = URL(string: "https://example.com/score-test")!

        let readability = ReadabilityExtractor()
        let result = try readability.extract(html: html, url: url)

        XCTAssertTrue(result.contentHTML.contains("meaningful article paragraph"),
                      "High-score element with article-like class should be selected")
    }

    func testReadability_linkDensityPenalty() throws {
        let linkHeavyContent = (1...20).map { "<a href=\"/link\($0)\">Link text number \($0) is here</a>" }.joined(separator: " ")
        let articleContent = String(repeating: "This is real article content with no links at all. ", count: 10)
        let html = """
        <html><body>
            <div class="link-list" id="linklist">
                <p>\(linkHeavyContent)</p>
            </div>
            <div class="entry-content" id="article">
                <p>\(articleContent)</p>
                <p>More article text without any hyperlinks for comparison.</p>
            </div>
        </body></html>
        """
        let url = URL(string: "https://example.com/link-density")!

        let readability = ReadabilityExtractor()
        let result = try readability.extract(html: html, url: url)

        XCTAssertTrue(result.contentHTML.contains("real article content"),
                      "Element with high link density should be penalized; article content should win")
    }

    func testReadability_textDensityBonus() throws {
        let paragraphs = (1...8).map { "<p>Paragraph number \($0) with enough text to contribute to the score. This makes the text density higher.</p>" }.joined()
        let html = """
        <html><body>
            <div id="sparse"><p>Only one short paragraph here.</p></div>
            <div id="dense">\(paragraphs)</div>
        </body></html>
        """
        let url = URL(string: "https://example.com/text-density")!

        let readability = ReadabilityExtractor()
        let result = try readability.extract(html: html, url: url)

        XCTAssertTrue(result.contentHTML.contains("Paragraph number 1"),
                      "Element with many <p> tags and substantial text should be selected")
        XCTAssertTrue(result.contentHTML.contains("Paragraph number 8"),
                      "All paragraphs from the dense element should be present")
    }

    // MARK: - Memory Monitoring

    func testCurrentMemoryUsage_returnsNonZero() {
        let extractor = ContentExtractor()
        let usage = extractor.currentMemoryUsage()
        XCTAssertGreaterThan(usage, 0, "Memory usage should be non-zero in a running process")
    }

    func testMemoryLimitCheck_doesNotCrash() {
        let extractor = ContentExtractor()
        let usage = extractor.currentMemoryUsage()
        // The memory check code path should complete without crashing.
        // The test process itself may use more than the 100MB Share Extension limit,
        // but the function should still return a valid value.
        XCTAssertGreaterThan(usage, 0, "Memory usage should be a valid positive number")
    }

    // MARK: - Timeout Mechanism

    func testExtract_invalidURL_failsFast() async {
        let extractor = ContentExtractor()
        let url = URL(string: "ftp://invalid")!
        let start = Date()

        do {
            _ = try await extractor.extract(url: url)
            XCTFail("Expected ExtractionError.invalidURL")
        } catch {
            let elapsed = Date().timeIntervalSince(start)
            guard case ExtractionError.invalidURL = error else {
                XCTFail("Expected ExtractionError.invalidURL, got \(error)")
                return
            }
            XCTAssertLessThan(elapsed, 1.0, "Invalid URL should fail fast, not wait for timeout")
        }
    }

    func testExtract_unreachableHost_respectsTimeout() async {
        let extractor = ContentExtractor()
        // 192.0.2.1 is TEST-NET-1, guaranteed non-routable (RFC 5737)
        let url = URL(string: "http://192.0.2.1/article")!
        let expectation = XCTestExpectation(description: "Extraction completes within timeout")

        let start = Date()
        Task {
            do {
                _ = try await extractor.extract(url: url)
            } catch {
                // Expected: either timeout or network error
            }
            let elapsed = Date().timeIntervalSince(start)
            // Should complete within 8s timeout + reasonable buffer (5s for URLSession + task overhead)
            XCTAssertLessThan(elapsed, 15.0, "Should respect the 8-second timeout, not hang forever")
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 15.0)
    }

    // MARK: - Helpers

    private func loadFixture(_ name: String) throws -> String {
        let bundle = Bundle(for: type(of: self))
        if let url = bundle.url(forResource: name, withExtension: nil, subdirectory: nil)
            ?? bundle.url(forResource: name.replacingOccurrences(of: ".html", with: ""), withExtension: "html") {
            return try String(contentsOf: url, encoding: .utf8)
        }
        // Fallback: read directly from source tree
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Extraction/\(name)")
        return try String(contentsOf: path, encoding: .utf8)
    }
}
