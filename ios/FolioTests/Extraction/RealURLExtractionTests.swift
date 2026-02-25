import XCTest
@testable import Folio

/// Integration tests that verify the client-side content extraction pipeline
/// (HTMLFetcher -> ReadabilityExtractor -> HTMLToMarkdownConverter) using REAL URLs
/// from various sources.
///
/// **Requirements**:
/// - Network access is required. Tests will fail or be skipped if the network is unavailable.
/// - These tests depend on external websites; content may change or sites may block requests.
///   When a test fails due to external factors (not a bug in our code), the assertion documents
///   the observed behavior rather than hard-failing.
/// - Each test has a generous timeout to accommodate real network latency.
///
/// **Note on memory limit bypass**:
/// `ContentExtractor.extract(url:)` includes a 100MB memory guard designed for the Share
/// Extension (120MB limit). The test host process (Folio.app in simulator) typically exceeds
/// 100MB, so these tests call the pipeline components directly:
///   HTMLFetcher -> ReadabilityExtractor -> HTMLToMarkdownConverter -> countWords
/// This tests the same extraction logic without the memory guard that would always trip
/// in the test environment.
final class RealURLExtractionTests: XCTestCase {

    // MARK: - Helper

    /// Runs the full extraction pipeline (HTMLFetcher -> ReadabilityExtractor ->
    /// HTMLToMarkdownConverter) on a real URL and verifies basic quality thresholds.
    ///
    /// This bypasses `ContentExtractor.extract(url:)` to avoid the 100MB memory guard
    /// that always trips in the test host process. The extraction logic tested is identical.
    private func extractAndVerify(
        url: URL,
        minContentLength: Int = 200,
        minWordCount: Int = 50,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> ExtractionResult {
        // Step 1: Fetch HTML
        let fetcher = HTMLFetcher()
        let html = try await fetcher.fetch(url: url)

        // Step 2: Extract content using readability
        let readabilityExtractor = ReadabilityExtractor()
        let readability = try readabilityExtractor.extract(html: html, url: url)

        // Step 3: Convert HTML to Markdown
        let converter = HTMLToMarkdownConverter()
        let markdown = try converter.convert(html: readability.contentHTML)

        // Step 4: Count words (using ContentExtractor's countWords for CJK support)
        let contentExtractor = ContentExtractor()
        let wordCount = contentExtractor.countWords(markdown)

        let result = ExtractionResult(
            title: readability.title,
            author: readability.author,
            siteName: readability.siteName,
            excerpt: readability.excerpt,
            markdownContent: markdown,
            wordCount: wordCount,
            extractedAt: Date()
        )

        // Basic quality checks
        XCTAssertFalse(
            result.markdownContent.isEmpty,
            "Content should not be empty for \(url)",
            file: file, line: line
        )
        XCTAssertGreaterThan(
            result.markdownContent.count, minContentLength,
            "Content too short (\(result.markdownContent.count) chars) for \(url)",
            file: file, line: line
        )
        XCTAssertGreaterThan(
            result.wordCount, minWordCount,
            "Word count too low (\(result.wordCount)) for \(url)",
            file: file, line: line
        )

        // Diagnostic output
        print("--- [\(url.host ?? "unknown")] ---")
        print("  Title:     \(result.title ?? "nil")")
        print("  Author:    \(result.author ?? "nil")")
        print("  SiteName:  \(result.siteName ?? "nil")")
        print("  Excerpt:   \(String(result.excerpt?.prefix(120) ?? "nil"))")
        print("  WordCount: \(result.wordCount)")
        print("  Content length: \(result.markdownContent.count) chars")
        print("  Preview:   \(String(result.markdownContent.prefix(300)))...")
        print("---")

        return result
    }

    /// Runs the extraction pipeline without quality assertions. Used for tests where
    /// low-quality or failed extraction is acceptable (YouTube, example.com, etc.).
    private func extractRaw(url: URL) async throws -> ExtractionResult {
        let fetcher = HTMLFetcher()
        let html = try await fetcher.fetch(url: url)

        let readabilityExtractor = ReadabilityExtractor()
        let readability = try readabilityExtractor.extract(html: html, url: url)

        let converter = HTMLToMarkdownConverter()
        let markdown = try converter.convert(html: readability.contentHTML)

        let contentExtractor = ContentExtractor()
        let wordCount = contentExtractor.countWords(markdown)

        return ExtractionResult(
            title: readability.title,
            author: readability.author,
            siteName: readability.siteName,
            excerpt: readability.excerpt,
            markdownContent: markdown,
            wordCount: wordCount,
            extractedAt: Date()
        )
    }

    // MARK: - 1. English Blog Post

    func testExtract_englishBlog() async throws {
        let url = URL(string: "https://blog.golang.org/using-go-modules")!

        do {
            let result = try await extractAndVerify(url: url)

            // Go blog posts should have a meaningful title
            XCTAssertNotNil(result.title, "Go blog should have a title")
            XCTAssertGreaterThan(result.markdownContent.count, 500,
                                 "Go blog post should have substantial content")
            XCTAssertGreaterThan(result.wordCount, 100,
                                 "Go blog post should have >100 words")
        } catch {
            // The Go blog may redirect or change structure. Document the failure.
            print("testExtract_englishBlog failed with error: \(error)")
            print("This may be due to URL redirect or site structure change.")
            throw error
        }
    }

    // MARK: - 2. GitHub Blog / Documentation

    func testExtract_githubBlog() async throws {
        let url = URL(string: "https://github.blog/engineering/the-technology-behind-githubs-new-code-search/")!

        do {
            let result = try await extractAndVerify(url: url)

            // GitHub blog should have a meaningful title
            XCTAssertNotNil(result.title, "GitHub blog should have a title")
            if let title = result.title {
                XCTAssertTrue(
                    title.lowercased().contains("code search") || title.lowercased().contains("github"),
                    "Title should be related to code search or GitHub, got: \(title)"
                )
            }

            // Expect markdown headings in a well-structured blog post
            let hasHeadings = result.markdownContent.contains("## ") || result.markdownContent.contains("# ")
            XCTAssertTrue(hasHeadings,
                          "GitHub blog post should contain markdown headings")
        } catch {
            print("testExtract_githubBlog failed with error: \(error)")
            print("GitHub blog may have changed URL or structure.")
            throw error
        }
    }

    // MARK: - 3. Medium-style Article

    func testExtract_mediumArticle() async throws {
        // Medium aggressively blocks automated requests and uses JS rendering.
        // This test documents the expected behavior rather than hard-failing.
        let url = URL(string: "https://medium.com/@anandsr21/a-beginners-guide-to-ios-development-in-2024-6b5e7e5e5c5a")!

        do {
            let result = try await extractAndVerify(url: url, minContentLength: 100, minWordCount: 20)
            print("Medium extraction succeeded — title: \(result.title ?? "nil"), words: \(result.wordCount)")
        } catch {
            // Medium commonly blocks or returns minimal content for non-browser requests.
            // Document this as expected behavior rather than crashing.
            print("Medium extraction failed (expected — Medium often blocks automated requests): \(error)")
            // Do NOT re-throw: Medium blocking is documented and expected
        }
    }

    // MARK: - 4. Chinese Content

    func testExtract_chineseBlog() async throws {
        // ruanyifeng.com serves static HTML (unlike sspai.com which is a JS SPA).
        // Ruan Yifeng's weekly newsletter is a well-known, stable Chinese tech blog.
        let url = URL(string: "https://www.ruanyifeng.com/blog/2023/12/weekly-issue-283.html")!

        do {
            let result = try await extractAndVerify(url: url, minContentLength: 100, minWordCount: 30)

            // Word count should use CJK counting (each character = 1 word)
            XCTAssertGreaterThan(result.wordCount, 30,
                                 "Chinese content should have meaningful word count via CJK counting")

            // Content should be non-empty and contain Chinese characters
            let hasChinese = result.markdownContent.unicodeScalars.contains { scalar in
                let v = scalar.value
                return v >= 0x4E00 && v <= 0x9FFF
            }
            XCTAssertTrue(hasChinese, "Chinese blog content should contain CJK characters")

            print("Chinese extraction — title: \(result.title ?? "nil"), words: \(result.wordCount)")
        } catch {
            print("testExtract_chineseBlog failed with error: \(error)")
            print("ruanyifeng.com may have changed structure or blocked the request.")
            throw error
        }
    }

    // MARK: - 5. Wikipedia Article (Well-Structured HTML)

    func testExtract_wikipedia() async throws {
        let url = URL(string: "https://en.wikipedia.org/wiki/Swift_(programming_language)")!

        do {
            let result = try await extractAndVerify(url: url)

            // Wikipedia has excellent structure — expect good extraction
            XCTAssertNotNil(result.title, "Wikipedia article should have a title")
            if let title = result.title {
                XCTAssertTrue(
                    title.lowercased().contains("swift"),
                    "Title should mention Swift, got: \(title)"
                )
            }

            // Wikipedia articles are long — expect substantial content
            XCTAssertGreaterThan(result.markdownContent.count, 1000,
                                 "Wikipedia article should have >1000 chars of content")
            XCTAssertGreaterThan(result.wordCount, 200,
                                 "Wikipedia article should have >200 words")

            // Should have site name
            if let siteName = result.siteName {
                XCTAssertTrue(
                    siteName.lowercased().contains("wikipedia"),
                    "Site name should mention Wikipedia, got: \(siteName)"
                )
            }
        } catch {
            print("testExtract_wikipedia failed with error: \(error)")
            throw error
        }
    }

    // MARK: - 6. Static Example Page (Minimal Content)

    func testExtract_exampleDotCom() async throws {
        // example.com has very minimal content — this tests graceful handling
        let url = URL(string: "https://example.com")!

        do {
            let result = try await extractRaw(url: url)

            // example.com has very little content. If extraction succeeds, verify it doesn't crash.
            print("example.com extraction succeeded — content length: \(result.markdownContent.count), words: \(result.wordCount)")

            // example.com content is minimal but should produce something
            // The page has a heading "Example Domain" and a short paragraph
            XCTAssertFalse(result.markdownContent.isEmpty,
                           "example.com should produce some content")
        } catch {
            // example.com is minimal — contentTooShort or any graceful error is acceptable
            print("example.com extraction error (acceptable for minimal page): \(error)")
        }
    }

    // MARK: - 7. YouTube Link (JS-Heavy, Low Quality Expected)

    func testExtract_youtube_lowQuality() async throws {
        // YouTube pages are JS-heavy; static HTML extraction will produce low-quality results.
        // This test documents the expected behavior and verifies the pipeline doesn't crash.
        let url = URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!

        do {
            let result = try await extractRaw(url: url)

            // If it succeeds at all, just document results
            print("YouTube extraction succeeded — title: \(result.title ?? "nil"), words: \(result.wordCount)")
            print("YouTube content preview: \(String(result.markdownContent.prefix(300)))...")

            // YouTube extraction quality is expected to be low
            // Just verify the pipeline completed without crash
        } catch {
            // YouTube may fail in many ways — all are acceptable for JS-heavy pages
            print("YouTube extraction failed (expected — JS-heavy page): \(error)")
        }
    }

    // MARK: - 8. News Site

    func testExtract_bbcNews() async throws {
        let url = URL(string: "https://www.bbc.com/news/technology-67988517")!

        do {
            let result = try await extractAndVerify(url: url, minContentLength: 200, minWordCount: 50)

            // BBC articles should have a title
            XCTAssertNotNil(result.title, "BBC article should have a title")

            // BBC News should have author or site name
            let hasAttribution = result.author != nil || result.siteName != nil
            if !hasAttribution {
                print("Note: BBC article missing both author and siteName (may have changed page structure)")
            }

            print("BBC extraction — title: \(result.title ?? "nil"), author: \(result.author ?? "nil")")
        } catch {
            // BBC article URLs can go stale or BBC may serve different content to automated requests.
            // Document but don't hard-fail.
            print("BBC extraction failed (article may have moved or BBC blocks automated requests): \(error)")
        }
    }
}
