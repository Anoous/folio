import XCTest
import SwiftData
@testable import Folio

private final class ArticleProcessingSyncWorkflowMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (Data, HTTPURLResponse))?
    nonisolated(unsafe) static var requestPaths: [String] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestPaths.append(request.url?.path ?? "")

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

final class ArticleProcessingSyncWorkflowTests: XCTestCase {
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

        keychainManager = KeyChainManager(service: "com.folio.article-processing-sync-tests.\(UUID())")
        try? keychainManager.clearTokens()
        try? keychainManager.saveTokens(access: "test-token", refresh: "test-refresh")

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ArticleProcessingSyncWorkflowMockURLProtocol.self]
        apiClient = APIClient(
            baseURL: baseURL,
            keychainManager: keychainManager,
            session: URLSession(configuration: config)
        )

        ArticleProcessingSyncWorkflowMockURLProtocol.requestHandler = nil
        ArticleProcessingSyncWorkflowMockURLProtocol.requestPaths = []
    }

    override func tearDown() {
        ArticleProcessingSyncWorkflowMockURLProtocol.requestHandler = nil
        ArticleProcessingSyncWorkflowMockURLProtocol.requestPaths = []
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

    private func taskJSON(
        id: String = "task-1",
        status: String,
        articleID: String? = nil,
        errorMessage: String? = nil
    ) -> Data {
        """
        {
          "id": "\(id)",
          "url": "https://example.com/article",
          "status": "\(status)",
          "article_id": \(articleID.map { "\"\($0)\"" } ?? "null"),
          "error_message": \(errorMessage.map { "\"\($0)\"" } ?? "null"),
          "retry_count": 0,
          "created_at": "2025-01-01T00:00:00Z",
          "updated_at": "2025-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!
    }

    private func articleJSON(id: String, url: String, title: String, status: String = "ready") -> Data {
        """
        {
          "id": "\(id)",
          "url": "\(url)",
          "title": "\(title)",
          "author": null,
          "site_name": "Example",
          "favicon_url": null,
          "cover_image_url": null,
          "markdown_content": "Processed content",
          "language": "en",
          "category_id": null,
          "summary": null,
          "key_points": [],
          "ai_confidence": null,
          "source_type": "web",
          "fetch_error": null,
          "retry_count": 0,
          "word_count": 100,
          "is_favorite": false,
          "is_archived": false,
          "read_progress": 0,
          "last_read_at": null,
          "published_at": null,
          "status": "\(status)",
          "created_at": "2025-01-01T00:00:00Z",
          "updated_at": "2025-01-01T00:00:00Z",
          "deleted_at": null,
          "category": null,
          "tags": []
        }
        """.data(using: .utf8)!
    }

    @MainActor
    private func makeWorkflow(pollMaxAttempts: Int = 1) -> ArticleProcessingSyncWorkflow {
        ArticleProcessingSyncWorkflow(
            apiClient: apiClient,
            context: context,
            pollMaxAttempts: pollMaxAttempts,
            pollInterval: .zero,
            sleep: { _ in }
        )
    }

    @MainActor
    func testPollSubmittedArticleDoneFetchesAndUpdatesLocalArticle() async throws {
        let article = Article(url: "https://example.com/pending")
        article.status = .processing
        context.insert(article)
        try context.save()

        ArticleProcessingSyncWorkflowMockURLProtocol.requestHandler = { request in
            switch request.url?.path {
            case "/api/v1/tasks/task-1":
                return (
                    self.taskJSON(status: AppConstants.TaskStatus.done, articleID: "server-art-1"),
                    self.makeResponse(statusCode: 200)
                )
            case "/api/v1/articles/server-art-1":
                return (
                    self.articleJSON(
                        id: "server-art-1",
                        url: "https://example.com/pending",
                        title: "Processed Article"
                    ),
                    self.makeResponse(statusCode: 200)
                )
            default:
                XCTFail("Unexpected request: \(request.url?.path ?? "")")
                return (Data(), self.makeResponse(statusCode: 500))
            }
        }

        await makeWorkflow().pollSubmittedArticle(taskID: "task-1", articleLocalID: article.id)

        XCTAssertEqual(
            ArticleProcessingSyncWorkflowMockURLProtocol.requestPaths,
            ["/api/v1/tasks/task-1", "/api/v1/articles/server-art-1"]
        )
        XCTAssertEqual(article.serverID, "server-art-1")
        XCTAssertEqual(article.title, "Processed Article")
        XCTAssertEqual(article.status, .ready)
    }

    @MainActor
    func testPollSubmittedArticleFailedMarksArticleFailed() async throws {
        let article = Article(url: "https://example.com/failed")
        article.status = .processing
        context.insert(article)
        try context.save()

        ArticleProcessingSyncWorkflowMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/tasks/task-1")
            return (
                self.taskJSON(status: AppConstants.TaskStatus.failed, errorMessage: "Crawler failed"),
                self.makeResponse(statusCode: 200)
            )
        }

        await makeWorkflow().pollSubmittedArticle(taskID: "task-1", articleLocalID: article.id)

        XCTAssertEqual(ArticleProcessingSyncWorkflowMockURLProtocol.requestPaths, ["/api/v1/tasks/task-1"])
        XCTAssertEqual(article.status, .failed)
        XCTAssertEqual(article.fetchError, "Crawler failed")
    }

    @MainActor
    func testPollSubmittedArticleTimeoutMarksArticleFailed() async throws {
        let article = Article(url: "https://example.com/timeout")
        article.status = .processing
        context.insert(article)
        try context.save()

        ArticleProcessingSyncWorkflowMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/tasks/task-1")
            return (
                self.taskJSON(status: AppConstants.TaskStatus.queued),
                self.makeResponse(statusCode: 200)
            )
        }

        await makeWorkflow(pollMaxAttempts: 2)
            .pollSubmittedArticle(taskID: "task-1", articleLocalID: article.id)

        XCTAssertEqual(
            ArticleProcessingSyncWorkflowMockURLProtocol.requestPaths,
            ["/api/v1/tasks/task-1", "/api/v1/tasks/task-1"]
        )
        XCTAssertEqual(article.status, .failed)
        XCTAssertEqual(article.fetchError, "Processing timed out")
    }

    @MainActor
    func testRefreshProcessingArticlesUpdatesProcessingAndClientReadyArticles() async throws {
        let processing = Article(url: "https://example.com/processing")
        processing.serverID = "server-processing"
        processing.status = .processing
        context.insert(processing)

        let clientReady = Article(url: "https://example.com/client-ready")
        clientReady.serverID = "server-client-ready"
        clientReady.status = .clientReady
        context.insert(clientReady)

        let noServerID = Article(url: "https://example.com/no-server-id")
        noServerID.status = .processing
        context.insert(noServerID)

        let ready = Article(url: "https://example.com/ready")
        ready.serverID = "server-ready"
        ready.status = .ready
        ready.title = "Already Ready"
        context.insert(ready)

        try context.save()

        ArticleProcessingSyncWorkflowMockURLProtocol.requestHandler = { request in
            switch request.url?.path {
            case "/api/v1/articles/server-processing":
                return (
                    self.articleJSON(
                        id: "server-processing",
                        url: "https://example.com/processing",
                        title: "Finished Processing"
                    ),
                    self.makeResponse(statusCode: 200)
                )
            case "/api/v1/articles/server-client-ready":
                return (
                    self.articleJSON(
                        id: "server-client-ready",
                        url: "https://example.com/client-ready",
                        title: "Finished Client Ready"
                    ),
                    self.makeResponse(statusCode: 200)
                )
            default:
                XCTFail("Unexpected request: \(request.url?.path ?? "")")
                return (Data(), self.makeResponse(statusCode: 500))
            }
        }

        await makeWorkflow().refreshProcessingArticles()

        XCTAssertEqual(Set(ArticleProcessingSyncWorkflowMockURLProtocol.requestPaths), [
            "/api/v1/articles/server-processing",
            "/api/v1/articles/server-client-ready"
        ])
        XCTAssertEqual(processing.title, "Finished Processing")
        XCTAssertEqual(processing.status, .ready)
        XCTAssertEqual(clientReady.title, "Finished Client Ready")
        XCTAssertEqual(clientReady.status, .ready)
        XCTAssertNil(noServerID.title)
        XCTAssertEqual(ready.title, "Already Ready")
    }
}
