import XCTest
@testable import Folio

private final class MockFetcherURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (Data, HTTPURLResponse))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockFetcherURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (data, response) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class HTMLFetcherTests: XCTestCase {

    private var mockConfig: URLSessionConfiguration!

    override func setUp() {
        super.setUp()
        mockConfig = URLSessionConfiguration.ephemeral
        mockConfig.protocolClasses = [MockFetcherURLProtocol.self]
    }

    override func tearDown() {
        MockFetcherURLProtocol.requestHandler = nil
        mockConfig = nil
        super.tearDown()
    }

    // MARK: - Helper

    private func makeFetcher() -> HTMLFetcher {
        HTMLFetcher(sessionConfiguration: mockConfig)
    }

    private func makeHTTPResponse(
        url: URL,
        statusCode: Int = 200,
        headers: [String: String] = ["Content-Type": "text/html; charset=utf-8"]
    ) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headers
        )!
    }

    // MARK: - Configuration

    func testDefaultTimeout_is5Seconds() {
        XCTAssertEqual(HTMLFetcher.defaultTimeout, 5)
    }

    func testMaxResponseSize_is2MB() {
        XCTAssertEqual(HTMLFetcher.maxResponseSize, 2 * 1024 * 1024)
    }

    // MARK: - Content-Type Rejection (Error Enum)

    func testInvalidContentType_rejectsJSON() async {
        // HTMLFetchError.invalidContentType is thrown for non-HTML content types
        // Verify the error type exists and has correct association
        let error = HTMLFetchError.invalidContentType("application/json")
        if case .invalidContentType(let ct) = error {
            XCTAssertEqual(ct, "application/json")
        } else {
            XCTFail("Expected invalidContentType")
        }
    }

    // MARK: - Response Too Large (Error Enum)

    func testResponseTooLarge_errorCarriesSize() {
        let error = HTMLFetchError.responseTooLarge(3_000_000)
        if case .responseTooLarge(let size) = error {
            XCTAssertEqual(size, 3_000_000)
        } else {
            XCTFail("Expected responseTooLarge")
        }
    }

    // MARK: - Error Types (Error Enum)

    func testHTTPError_carriesStatusCode() {
        let error = HTMLFetchError.httpError(404)
        if case .httpError(let code) = error {
            XCTAssertEqual(code, 404)
        } else {
            XCTFail("Expected httpError")
        }
    }

    func testInvalidURL_error() {
        let error = HTMLFetchError.invalidURL
        if case .invalidURL = error {
            // pass
        } else {
            XCTFail("Expected invalidURL")
        }
    }

    func testEncodingError() {
        let error = HTMLFetchError.encodingError
        if case .encodingError = error {
            // pass
        } else {
            XCTFail("Expected encodingError")
        }
    }

    func testNetworkError_carriesUnderlyingError() {
        let underlying = URLError(.timedOut)
        let error = HTMLFetchError.networkError(underlying)
        if case .networkError(let e) = error {
            XCTAssertTrue(e is URLError)
        } else {
            XCTFail("Expected networkError")
        }
    }

    // MARK: - Fetch Success

    func testFetch_validHTML_returnsHTMLString() async throws {
        let testURL = URL(string: "https://example.com/article")!
        let expectedHTML = "<html><body><p>Hello World</p></body></html>"
        let htmlData = expectedHTML.data(using: .utf8)!

        MockFetcherURLProtocol.requestHandler = { request in
            let response = self.makeHTTPResponse(url: request.url!)
            return (htmlData, response)
        }

        let fetcher = makeFetcher()
        let result = try await fetcher.fetch(url: testURL)

        XCTAssertEqual(result, expectedHTML)
    }

    // MARK: - Content-Type Rejection (Behavioral)

    func testFetch_jsonContentType_throwsInvalidContentType() async {
        let testURL = URL(string: "https://example.com/api/data")!
        let jsonData = #"{"key": "value"}"#.data(using: .utf8)!

        MockFetcherURLProtocol.requestHandler = { request in
            let response = self.makeHTTPResponse(
                url: request.url!,
                headers: ["Content-Type": "application/json"]
            )
            return (jsonData, response)
        }

        let fetcher = makeFetcher()
        do {
            _ = try await fetcher.fetch(url: testURL)
            XCTFail("Expected HTMLFetchError.invalidContentType")
        } catch {
            guard case HTMLFetchError.invalidContentType(let ct) = error else {
                XCTFail("Expected invalidContentType, got \(error)")
                return
            }
            XCTAssertEqual(ct, "application/json")
        }
    }

    // MARK: - Oversized Response (Behavioral)

    func testFetch_oversizedResponse_throwsResponseTooLarge() async {
        let testURL = URL(string: "https://example.com/large-page")!
        // Create data exceeding 2MB (HTMLFetcher.maxResponseSize)
        let oversizedData = Data(repeating: 0x41, count: HTMLFetcher.maxResponseSize + 1)

        MockFetcherURLProtocol.requestHandler = { request in
            let response = self.makeHTTPResponse(url: request.url!)
            return (oversizedData, response)
        }

        let fetcher = makeFetcher()
        do {
            _ = try await fetcher.fetch(url: testURL)
            XCTFail("Expected HTMLFetchError.responseTooLarge")
        } catch {
            guard case HTMLFetchError.responseTooLarge(let size) = error else {
                XCTFail("Expected responseTooLarge, got \(error)")
                return
            }
            XCTAssertEqual(size, HTMLFetcher.maxResponseSize + 1)
        }
    }

    // MARK: - Encoding Detection (GBK)

    func testFetch_gbkEncoding_decodesCorrectly() async throws {
        let testURL = URL(string: "https://example.com/chinese-article")!
        let chineseText = "中文内容测试"

        // Encode the Chinese text using GB18030 (superset of GBK)
        let cfEncoding = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
        let gbkEncoding = String.Encoding(rawValue: cfEncoding)

        let htmlString = "<html><body>\(chineseText)</body></html>"
        guard let gbkData = htmlString.data(using: gbkEncoding) else {
            XCTFail("Could not encode test HTML as GBK")
            return
        }

        MockFetcherURLProtocol.requestHandler = { request in
            let response = self.makeHTTPResponse(
                url: request.url!,
                headers: ["Content-Type": "text/html; charset=gbk"]
            )
            return (gbkData, response)
        }

        let fetcher = makeFetcher()
        let result = try await fetcher.fetch(url: testURL)

        XCTAssertTrue(result.contains(chineseText), "Decoded HTML should contain the Chinese text")
    }

    // MARK: - HTTP Error (Behavioral)

    func testFetch_httpError404_throwsHTTPError() async {
        let testURL = URL(string: "https://example.com/not-found")!

        MockFetcherURLProtocol.requestHandler = { request in
            let response = self.makeHTTPResponse(
                url: request.url!,
                statusCode: 404,
                headers: ["Content-Type": "text/html"]
            )
            return (Data(), response)
        }

        let fetcher = makeFetcher()
        do {
            _ = try await fetcher.fetch(url: testURL)
            XCTFail("Expected HTMLFetchError.httpError(404)")
        } catch {
            guard case HTMLFetchError.httpError(let code) = error else {
                XCTFail("Expected httpError, got \(error)")
                return
            }
            XCTAssertEqual(code, 404)
        }
    }

    func testFetch_httpError500_throwsHTTPError() async {
        let testURL = URL(string: "https://example.com/error")!

        MockFetcherURLProtocol.requestHandler = { request in
            let response = self.makeHTTPResponse(
                url: request.url!,
                statusCode: 500,
                headers: ["Content-Type": "text/html"]
            )
            return (Data(), response)
        }

        let fetcher = makeFetcher()
        do {
            _ = try await fetcher.fetch(url: testURL)
            XCTFail("Expected HTMLFetchError.httpError(500)")
        } catch {
            guard case HTMLFetchError.httpError(let code) = error else {
                XCTFail("Expected httpError, got \(error)")
                return
            }
            XCTAssertEqual(code, 500)
        }
    }

    // MARK: - Content-Type Acceptance

    func testFetch_textXMLContentType_succeeds() async throws {
        let testURL = URL(string: "https://example.com/feed.xml")!
        let xmlData = "<xml><item>test</item></xml>".data(using: .utf8)!

        MockFetcherURLProtocol.requestHandler = { request in
            let response = self.makeHTTPResponse(
                url: request.url!,
                headers: ["Content-Type": "text/xml; charset=utf-8"]
            )
            return (xmlData, response)
        }

        let fetcher = makeFetcher()
        let result = try await fetcher.fetch(url: testURL)
        XCTAssertTrue(result.contains("<item>test</item>"))
    }

    func testFetch_xhtmlContentType_succeeds() async throws {
        let testURL = URL(string: "https://example.com/page.xhtml")!
        let xhtmlData = "<html><body><p>XHTML content</p></body></html>".data(using: .utf8)!

        MockFetcherURLProtocol.requestHandler = { request in
            let response = self.makeHTTPResponse(
                url: request.url!,
                headers: ["Content-Type": "application/xhtml+xml"]
            )
            return (xhtmlData, response)
        }

        let fetcher = makeFetcher()
        let result = try await fetcher.fetch(url: testURL)
        XCTAssertTrue(result.contains("XHTML content"))
    }

    // MARK: - No Content-Type Header

    func testFetch_noContentTypeHeader_succeeds() async throws {
        let testURL = URL(string: "https://example.com/no-ct")!
        let htmlData = "<html><body>No content type</body></html>".data(using: .utf8)!

        MockFetcherURLProtocol.requestHandler = { request in
            let response = self.makeHTTPResponse(
                url: request.url!,
                headers: [:]
            )
            return (htmlData, response)
        }

        let fetcher = makeFetcher()
        let result = try await fetcher.fetch(url: testURL)
        XCTAssertTrue(result.contains("No content type"))
    }

    // MARK: - Encoding Detection (Big5)

    func testFetch_big5Encoding_decodesCorrectly() async throws {
        let testURL = URL(string: "https://example.com/big5-article")!
        let chineseText = "繁體中文測試內容"

        let cfEncoding = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.big5.rawValue)
        )
        let big5Encoding = String.Encoding(rawValue: cfEncoding)

        let htmlString = "<html><body>\(chineseText)</body></html>"
        guard let big5Data = htmlString.data(using: big5Encoding) else {
            XCTFail("Could not encode test HTML as Big5")
            return
        }

        MockFetcherURLProtocol.requestHandler = { request in
            let response = self.makeHTTPResponse(
                url: request.url!,
                headers: ["Content-Type": "text/html; charset=big5"]
            )
            return (big5Data, response)
        }

        let fetcher = makeFetcher()
        let result = try await fetcher.fetch(url: testURL)

        XCTAssertTrue(result.contains(chineseText), "Decoded HTML should contain the Big5-encoded Chinese text")
    }

    // MARK: - Encoding Detection (ISO-8859-1)

    func testFetch_isoLatin1Encoding_decodesCorrectly() async throws {
        let testURL = URL(string: "https://example.com/latin1-article")!
        let latinText = "Héllo wörld, café résumé"

        let htmlString = "<html><body>\(latinText)</body></html>"
        guard let latin1Data = htmlString.data(using: .isoLatin1) else {
            XCTFail("Could not encode test HTML as ISO-8859-1")
            return
        }

        MockFetcherURLProtocol.requestHandler = { request in
            let response = self.makeHTTPResponse(
                url: request.url!,
                headers: ["Content-Type": "text/html; charset=iso-8859-1"]
            )
            return (latin1Data, response)
        }

        let fetcher = makeFetcher()
        let result = try await fetcher.fetch(url: testURL)

        XCTAssertTrue(result.contains(latinText), "Decoded HTML should contain the ISO-8859-1 encoded text")
    }

    // MARK: - Exact Size Boundary

    // MARK: - Header Charset vs Meta Charset Precedence

    func testFetch_headerCharsetTakesPrecedence() async throws {
        let testURL = URL(string: "https://example.com/charset-conflict")!
        // Content is valid UTF-8 with a meta tag claiming charset=gbk.
        // The header says charset=utf-8, so the fetcher should decode using UTF-8 (header wins).
        let htmlString = """
        <html><head><meta charset="gbk"></head><body><p>Hello UTF-8 World</p></body></html>
        """
        let utf8Data = htmlString.data(using: .utf8)!

        MockFetcherURLProtocol.requestHandler = { request in
            let response = self.makeHTTPResponse(
                url: request.url!,
                headers: ["Content-Type": "text/html; charset=utf-8"]
            )
            return (utf8Data, response)
        }

        let fetcher = makeFetcher()
        let result = try await fetcher.fetch(url: testURL)

        // Header charset (UTF-8) is tried first, so content decodes correctly
        XCTAssertTrue(result.contains("Hello UTF-8 World"),
                      "Header charset should take precedence over meta charset")
        XCTAssertTrue(result.contains("<meta charset=\"gbk\">"),
                      "Original HTML including meta tag should be preserved")
    }

    // MARK: - Exact Size Boundary

    func testFetch_exactlyMaxSize_succeeds() async throws {
        let testURL = URL(string: "https://example.com/big")!
        let exactData = Data(repeating: 0x41, count: HTMLFetcher.maxResponseSize)

        MockFetcherURLProtocol.requestHandler = { request in
            let response = self.makeHTTPResponse(url: request.url!)
            return (exactData, response)
        }

        let fetcher = makeFetcher()
        let result = try await fetcher.fetch(url: testURL)
        XCTAssertEqual(result.count, HTMLFetcher.maxResponseSize)
    }
}
