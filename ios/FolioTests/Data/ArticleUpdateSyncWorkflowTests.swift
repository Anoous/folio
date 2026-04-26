import XCTest
import SwiftData
@testable import Folio

private final class ArticleUpdateSyncWorkflowMockURLProtocol: URLProtocol {
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

final class ArticleUpdateSyncWorkflowTests: XCTestCase {
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

        keychainManager = KeyChainManager(service: "com.folio.article-update-sync-workflow-tests.\(UUID())")
        try? keychainManager.clearTokens()
        try? keychainManager.saveTokens(access: "test-token", refresh: "test-refresh")

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ArticleUpdateSyncWorkflowMockURLProtocol.self]
        apiClient = APIClient(
            baseURL: baseURL,
            keychainManager: keychainManager,
            session: URLSession(configuration: config)
        )

        ArticleUpdateSyncWorkflowMockURLProtocol.requestHandler = nil
        ArticleUpdateSyncWorkflowMockURLProtocol.requestPaths = []
        ArticleUpdateSyncWorkflowMockURLProtocol.lastRequestBody = nil
    }

    override func tearDown() {
        ArticleUpdateSyncWorkflowMockURLProtocol.requestHandler = nil
        ArticleUpdateSyncWorkflowMockURLProtocol.requestPaths = []
        ArticleUpdateSyncWorkflowMockURLProtocol.lastRequestBody = nil
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

    private func lastJSONBody() throws -> [String: Any] {
        let data = try XCTUnwrap(ArticleUpdateSyncWorkflowMockURLProtocol.lastRequestBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @MainActor
    func testSyncPendingUpdates_sendsDirtyFieldPatchAndClearsFields() async throws {
        ArticleUpdateSyncWorkflowMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.url?.path, "/api/v1/articles/server-1")
            return (Data(), self.makeResponse(statusCode: 200))
        }

        let article = Article(url: "https://example.com/favorite")
        article.serverID = "server-1"
        article.syncState = .pendingUpdate
        article.isFavorite = true
        article.favoriteUpdatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        article.dirtyFields = [.favorite]
        context.insert(article)
        try context.save()

        let workflow = ArticleUpdateSyncWorkflow(apiClient: apiClient, context: context)
        await workflow.syncPendingUpdates()

        XCTAssertEqual(ArticleUpdateSyncWorkflowMockURLProtocol.requestPaths, ["/api/v1/articles/server-1"])
        let body = try lastJSONBody()
        XCTAssertEqual(body["is_favorite"] as? Bool, true)
        XCTAssertNotNil(body["favorite_updated_at"] as? String)
        XCTAssertNil(body["is_archived"])
        XCTAssertNil(body["read_progress"])
        XCTAssertEqual(article.syncState, .synced)
        XCTAssertTrue(article.dirtyFields.isEmpty)
    }

    @MainActor
    func testSyncPendingUpdates_legacyPendingUpdateSendsReadProgressOnly() async throws {
        ArticleUpdateSyncWorkflowMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/articles/server-legacy")
            return (Data(), self.makeResponse(statusCode: 200))
        }

        let article = Article(url: "https://example.com/legacy")
        article.serverID = "server-legacy"
        article.syncState = .pendingUpdate
        article.readProgress = 0.42
        article.dirtyFields = []
        context.insert(article)
        try context.save()

        let workflow = ArticleUpdateSyncWorkflow(apiClient: apiClient, context: context)
        await workflow.syncPendingUpdates()

        let body = try lastJSONBody()
        XCTAssertEqual(body["read_progress"] as? Double, 0.42)
        XCTAssertNotNil(body["read_progress_updated_at"] as? String)
        XCTAssertNil(body["is_favorite"])
        XCTAssertNil(body["is_archived"])
        XCTAssertEqual(article.syncState, .synced)
    }

    @MainActor
    func testSyncPendingUpdates_notFoundAcceptsServerDeletion() async throws {
        ArticleUpdateSyncWorkflowMockURLProtocol.requestHandler = { _ in
            (Data(), self.makeResponse(statusCode: 404))
        }

        let article = Article(url: "https://example.com/deleted")
        article.serverID = "server-deleted"
        article.syncState = .pendingUpdate
        article.isArchived = true
        article.dirtyFields = [.archived]
        context.insert(article)
        try context.save()

        let workflow = ArticleUpdateSyncWorkflow(apiClient: apiClient, context: context)
        await workflow.syncPendingUpdates()

        XCTAssertEqual(article.syncState, .synced)
        XCTAssertTrue(article.dirtyFields.isEmpty)
    }

    @MainActor
    func testSyncPendingUpdates_withoutServerIDDoesNotSendRequest() async throws {
        ArticleUpdateSyncWorkflowMockURLProtocol.requestHandler = { _ in
            XCTFail("Article without a serverID should not hit the network")
            return (Data(), self.makeResponse(statusCode: 500))
        }

        let article = Article(url: "https://example.com/local-only")
        article.syncState = .pendingUpdate
        article.isFavorite = true
        article.dirtyFields = [.favorite]
        context.insert(article)
        try context.save()

        let workflow = ArticleUpdateSyncWorkflow(apiClient: apiClient, context: context)
        await workflow.syncPendingUpdates()

        XCTAssertEqual(ArticleUpdateSyncWorkflowMockURLProtocol.requestPaths, [])
        XCTAssertEqual(article.syncState, .pendingUpdate)
    }
}
