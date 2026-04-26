import XCTest
import SwiftData
@testable import Folio

private final class ArticleSyncWorkflowMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (Data, HTTPURLResponse))?
    nonisolated(unsafe) static var requestPaths: [String] = []
    nonisolated(unsafe) static var lastRequestBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private func requestBodyData() -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }
        stream.open()
        defer { stream.close() }

        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        var data = Data()
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read > 0 {
                data.append(buffer, count: read)
            } else {
                break
            }
        }
        return data
    }

    override func startLoading() {
        Self.requestPaths.append(request.url?.path ?? "")
        Self.lastRequestBody = requestBodyData()

        guard let handler = Self.requestHandler else {
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

final class ArticleSyncWorkflowTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var apiClient: APIClient!
    private var keychainManager: KeyChainManager!
    private let baseURL = URL(string: "https://test.folio.app")!

    @MainActor
    override func setUp() {
        super.setUp()
        container = try! DataManager.createInMemoryContainer()
        context = container.mainContext

        keychainManager = KeyChainManager(service: "com.folio.article-sync-workflow-tests.\(UUID())")
        try? keychainManager.clearTokens()
        try? keychainManager.saveTokens(access: "test-token", refresh: "test-refresh")

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ArticleSyncWorkflowMockURLProtocol.self]
        apiClient = APIClient(
            baseURL: baseURL,
            keychainManager: keychainManager,
            session: URLSession(configuration: config)
        )

        ArticleSyncWorkflowMockURLProtocol.requestHandler = nil
        ArticleSyncWorkflowMockURLProtocol.requestPaths = []
        ArticleSyncWorkflowMockURLProtocol.lastRequestBody = nil
    }

    override func tearDown() {
        ArticleSyncWorkflowMockURLProtocol.requestHandler = nil
        ArticleSyncWorkflowMockURLProtocol.requestPaths = []
        ArticleSyncWorkflowMockURLProtocol.lastRequestBody = nil
        try? keychainManager.clearTokens()
        keychainManager = nil
        apiClient = nil
        container = nil
        context = nil
        super.tearDown()
    }

    private func makeResponse(statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: baseURL, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    }

    private func submitResponse(articleID: String = "server-art-1", taskID: String = "task-1") -> Data {
        """
        {"article_id": "\(articleID)", "task_id": "\(taskID)"}
        """.data(using: .utf8)!
    }

    private func lastJSONBody() throws -> [String: Any] {
        let data = try XCTUnwrap(ArticleSyncWorkflowMockURLProtocol.lastRequestBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @MainActor
    func testTextOnlyArticleUsesManualContentRoute() async throws {
        ArticleSyncWorkflowMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/articles/manual")
            return (self.submitResponse(), self.makeResponse(statusCode: 202))
        }

        let article = Article(url: nil, sourceType: .voice)
        article.markdownContent = "Voice transcript"
        article.title = "Voice"
        context.insert(article)
        try context.save()

        let workflow = ArticleSyncWorkflow(apiClient: apiClient, context: context)
        let result = await workflow.submitPendingArticles([article])

        XCTAssertEqual(result[article.id], true)
        XCTAssertEqual(ArticleSyncWorkflowMockURLProtocol.requestPaths, ["/api/v1/articles/manual"])
        XCTAssertEqual(article.serverID, "server-art-1")
        XCTAssertEqual(article.syncState, .synced)

        let body = try lastJSONBody()
        XCTAssertEqual(body["content"] as? String, "Voice transcript")
        XCTAssertEqual(body["source_type"] as? String, SourceType.voice.rawValue)
        XCTAssertEqual(body["client_id"] as? String, article.id.uuidString)
    }

    @MainActor
    func testClientExtractedURLUsesEnrichedArticleRoute() async throws {
        ArticleSyncWorkflowMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/articles")
            return (self.submitResponse(), self.makeResponse(statusCode: 202))
        }

        let article = Article(url: "https://example.com/enriched", sourceType: .web)
        article.title = "Client Title"
        article.author = "Client Author"
        article.siteName = "Example"
        article.markdownContent = "Client markdown"
        article.wordCount = 2
        article.extractionSource = .client
        context.insert(article)
        try context.save()

        let workflow = ArticleSyncWorkflow(apiClient: apiClient, context: context)
        let result = await workflow.submitPendingArticles([article])

        XCTAssertEqual(result[article.id], true)
        XCTAssertEqual(ArticleSyncWorkflowMockURLProtocol.requestPaths, ["/api/v1/articles"])

        let body = try lastJSONBody()
        XCTAssertEqual(body["url"] as? String, "https://example.com/enriched")
        XCTAssertEqual(body["title"] as? String, "Client Title")
        XCTAssertEqual(body["author"] as? String, "Client Author")
        XCTAssertEqual(body["site_name"] as? String, "Example")
        XCTAssertEqual(body["markdown_content"] as? String, "Client markdown")
        XCTAssertEqual(body["word_count"] as? Int, 2)
    }

    @MainActor
    func testTextOnlyArticleWithoutContentFailsBeforeNetwork() async throws {
        ArticleSyncWorkflowMockURLProtocol.requestHandler = { _ in
            XCTFail("Missing text content should not hit the network")
            return (Data(), self.makeResponse(statusCode: 500))
        }

        let article = Article(url: nil, sourceType: .screenshot)
        article.status = .clientReady
        context.insert(article)
        try context.save()

        let workflow = ArticleSyncWorkflow(apiClient: apiClient, context: context)
        let result = await workflow.submitPendingArticles([article])

        XCTAssertEqual(result[article.id], false)
        XCTAssertEqual(ArticleSyncWorkflowMockURLProtocol.requestPaths, [])
        XCTAssertEqual(article.status, .failed)
        XCTAssertEqual(article.fetchError, "No content to submit")
    }
}
