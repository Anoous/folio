import XCTest
import SwiftData
@testable import Folio

private final class ArticlePullSyncWorkflowMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (Data, HTTPURLResponse))?
    nonisolated(unsafe) static var requestURLs: [URL] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let url = request.url {
            Self.requestURLs.append(url)
        }
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

final class ArticlePullSyncWorkflowTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var apiClient: APIClient!
    private var cursorStore: ArticleSyncCursorStore!
    private var keychainManager: KeyChainManager!
    private var userDefaultsSuiteName: String!
    private var userDefaults: UserDefaults!
    private let baseURL = URL(string: "https://test.folio.app")!

    @MainActor
    override func setUp() {
        super.setUp()
        container = try! DataManager.createInMemoryContainer()
        context = container.mainContext

        keychainManager = KeyChainManager(service: "com.folio.article-pull-sync-tests.\(UUID())")
        try? keychainManager.clearTokens()
        try? keychainManager.saveTokens(access: "test-token", refresh: "test-refresh")

        userDefaultsSuiteName = "com.folio.article-pull-sync-tests.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: userDefaultsSuiteName)
        userDefaults.removePersistentDomain(forName: userDefaultsSuiteName)
        cursorStore = ArticleSyncCursorStore(userDefaults: userDefaults)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ArticlePullSyncWorkflowMockURLProtocol.self]
        apiClient = APIClient(
            baseURL: baseURL,
            keychainManager: keychainManager,
            session: URLSession(configuration: config)
        )

        ArticlePullSyncWorkflowMockURLProtocol.requestHandler = nil
        ArticlePullSyncWorkflowMockURLProtocol.requestURLs = []
    }

    override func tearDown() {
        ArticlePullSyncWorkflowMockURLProtocol.requestHandler = nil
        ArticlePullSyncWorkflowMockURLProtocol.requestURLs = []
        if let userDefaultsSuiteName {
            userDefaults?.removePersistentDomain(forName: userDefaultsSuiteName)
        }
        try? keychainManager.clearTokens()
        keychainManager = nil
        apiClient = nil
        cursorStore = nil
        userDefaults = nil
        userDefaultsSuiteName = nil
        container = nil
        context = nil
        super.tearDown()
    }

    private func makeResponse(statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: baseURL, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    }

    private func articleListJSON(
        articleIDs: [String],
        total: Int,
        serverTime: String = "2025-04-01T00:00:00Z",
        syncEpoch: Int = 1
    ) -> Data {
        let articles = articleIDs.map { articleJSON(id: $0) }.joined(separator: ",")
        return """
        {
          "data": [\(articles)],
          "pagination": {"page": 1, "per_page": 50, "total": \(total)},
          "server_time": "\(serverTime)",
          "sync_epoch": \(syncEpoch)
        }
        """.data(using: .utf8)!
    }

    private func articleJSON(id: String) -> String {
        """
        {
          "id":"\(id)",
          "url":"https://example.com/\(id)",
          "title":"Article \(id)",
          "author":null,
          "site_name":"Example",
          "favicon_url":null,
          "cover_image_url":null,
          "markdown_content":"# \(id)",
          "language":"en",
          "category_id":null,
          "summary":null,
          "key_points":[],
          "ai_confidence":null,
          "source_type":"web",
          "fetch_error":null,
          "retry_count":0,
          "word_count":100,
          "is_favorite":false,
          "is_archived":false,
          "read_progress":0,
          "last_read_at":null,
          "published_at":null,
          "status":"ready",
          "created_at":"2025-04-01T00:00:00Z",
          "updated_at":"2025-04-01T00:00:00Z",
          "deleted_at":null,
          "category":null,
          "tags":[]
        }
        """
    }

    private func queryValue(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == name }?
            .value
    }

    private func fetchedArticles() throws -> [Article] {
        try context.fetch(FetchDescriptor<Article>())
    }

    private func isoDate(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    @MainActor
    func testFullSyncFetchesAllPagesReconcilesOrphansAndAdvancesCursor() async throws {
        let orphan = Article(url: "https://example.com/orphan", title: "Orphan")
        orphan.serverID = "server-old"
        orphan.syncState = .synced
        context.insert(orphan)
        try context.save()

        ArticlePullSyncWorkflowMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/articles")
            let page = self.queryValue("page", in: try XCTUnwrap(request.url))
            switch page {
            case "1":
                return (
                    self.articleListJSON(
                        articleIDs: ["server-1"],
                        total: 2,
                        serverTime: "2025-04-01T00:00:00Z",
                        syncEpoch: 7
                    ),
                    self.makeResponse(statusCode: 200)
                )
            case "2":
                return (
                    self.articleListJSON(
                        articleIDs: ["server-2"],
                        total: 2,
                        serverTime: "2025-04-01T00:00:10Z",
                        syncEpoch: 7
                    ),
                    self.makeResponse(statusCode: 200)
                )
            default:
                XCTFail("Unexpected page: \(page ?? "nil")")
                return (Data(), self.makeResponse(statusCode: 500))
            }
        }

        let workflow = ArticlePullSyncWorkflow(apiClient: apiClient, context: context, cursorStore: cursorStore)
        await workflow.fullSync()

        let serverIDs = try fetchedArticles().compactMap(\.serverID)
        XCTAssertEqual(Set(serverIDs), ["server-1", "server-2"])
        XCTAssertEqual(ArticlePullSyncWorkflowMockURLProtocol.requestURLs.count, 2)
        XCTAssertEqual(cursorStore.lastEpoch, 7)
        XCTAssertEqual(cursorStore.lastSyncedAt, isoDate("2025-04-01T00:00:10Z"))
    }

    @MainActor
    func testIncrementalSyncUsesCursorAndAdvancesServerTime() async throws {
        let since = isoDate("2025-04-01T00:00:00Z")
        cursorStore.lastSyncedAt = since
        cursorStore.lastEpoch = 7

        ArticlePullSyncWorkflowMockURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            XCTAssertEqual(url.path, "/api/v1/articles")
            XCTAssertEqual(self.queryValue("updated_since", in: url), "2025-04-01T00:00:00Z")
            return (
                self.articleListJSON(
                    articleIDs: ["server-3"],
                    total: 1,
                    serverTime: "2025-04-02T00:00:00Z",
                    syncEpoch: 7
                ),
                self.makeResponse(statusCode: 200)
            )
        }

        let workflow = ArticlePullSyncWorkflow(apiClient: apiClient, context: context, cursorStore: cursorStore)
        await workflow.incrementalSync()

        XCTAssertEqual(try fetchedArticles().first?.serverID, "server-3")
        XCTAssertEqual(ArticlePullSyncWorkflowMockURLProtocol.requestURLs.count, 1)
        XCTAssertEqual(cursorStore.lastSyncedAt, isoDate("2025-04-02T00:00:00Z"))
    }

    @MainActor
    func testIncrementalSyncEpochChangePurgesSyncedArticlesAndFallsBackToFullSync() async throws {
        cursorStore.lastSyncedAt = isoDate("2025-04-01T00:00:00Z")
        cursorStore.lastEpoch = 1

        let stale = Article(url: "https://example.com/stale", title: "Stale")
        stale.serverID = "server-stale"
        stale.syncState = .synced
        context.insert(stale)

        let pendingUpload = Article(url: "https://example.com/local", title: "Local")
        pendingUpload.syncState = .pendingUpload
        context.insert(pendingUpload)
        try context.save()

        ArticlePullSyncWorkflowMockURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            if self.queryValue("updated_since", in: url) != nil {
                return (
                    self.articleListJSON(
                        articleIDs: [],
                        total: 0,
                        serverTime: "2025-04-02T00:00:00Z",
                        syncEpoch: 2
                    ),
                    self.makeResponse(statusCode: 200)
                )
            }

            return (
                self.articleListJSON(
                    articleIDs: ["server-new"],
                    total: 1,
                    serverTime: "2025-04-03T00:00:00Z",
                    syncEpoch: 2
                ),
                self.makeResponse(statusCode: 200)
            )
        }

        let workflow = ArticlePullSyncWorkflow(apiClient: apiClient, context: context, cursorStore: cursorStore)
        await workflow.incrementalSync()

        let articles = try fetchedArticles()
        XCTAssertNil(articles.first { $0.serverID == "server-stale" })
        XCTAssertNotNil(articles.first { $0.url == "https://example.com/local" })
        XCTAssertNotNil(articles.first { $0.serverID == "server-new" })
        XCTAssertEqual(ArticlePullSyncWorkflowMockURLProtocol.requestURLs.count, 2)
        XCTAssertNotNil(queryValue("updated_since", in: ArticlePullSyncWorkflowMockURLProtocol.requestURLs[0]))
        XCTAssertNil(queryValue("updated_since", in: ArticlePullSyncWorkflowMockURLProtocol.requestURLs[1]))
        XCTAssertEqual(cursorStore.lastEpoch, 2)
        XCTAssertEqual(cursorStore.lastSyncedAt, isoDate("2025-04-03T00:00:00Z"))
    }
}
