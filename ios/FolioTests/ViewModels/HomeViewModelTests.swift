import XCTest
import SwiftData
@testable import Folio

private final class HomeViewModelMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (Data, HTTPURLResponse))?
    nonisolated(unsafe) static var lastRequestBody: Data?
    nonisolated(unsafe) static var lastRequestPath: String?

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
        Self.lastRequestPath = request.url?.path
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

final class HomeViewModelTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private let baseURL = URL(string: "https://test.folio.app")!

    @MainActor
    override func setUp() {
        super.setUp()
        container = try! DataManager.createInMemoryContainer()
        context = container.mainContext
        HomeViewModelMockURLProtocol.requestHandler = nil
        HomeViewModelMockURLProtocol.lastRequestBody = nil
        HomeViewModelMockURLProtocol.lastRequestPath = nil
    }

    override func tearDown() {
        HomeViewModelMockURLProtocol.requestHandler = nil
        HomeViewModelMockURLProtocol.lastRequestBody = nil
        HomeViewModelMockURLProtocol.lastRequestPath = nil
        container = nil
        context = nil
        super.tearDown()
    }

    private func makeAuthenticatedAPIClient() throws -> (APIClient, KeyChainManager) {
        let keychainManager = KeyChainManager(service: "com.folio.homevm-tests.\(UUID())")
        try? keychainManager.clearTokens()
        try keychainManager.saveTokens(access: "test-token", refresh: "test-refresh")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HomeViewModelMockURLProtocol.self]
        let session = URLSession(configuration: configuration)

        let apiClient = APIClient(
            baseURL: baseURL,
            keychainManager: keychainManager,
            session: session
        )

        return (apiClient, keychainManager)
    }

    private func makeResponse(statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: baseURL, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    }

    @MainActor
    private func waitForStatus(
        _ expectedStatus: ArticleStatus,
        article: Article,
        timeoutNanoseconds: UInt64 = 1_000_000_000
    ) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while article.status != expectedStatus {
            if DispatchTime.now().uptimeNanoseconds > deadline {
                XCTFail("Timed out waiting for article status \(expectedStatus.rawValue)")
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    @MainActor
    private func assertTextOnlyRetryUsesManualSubmit(for sourceType: SourceType, content: String) async throws {
        let (apiClient, keychainManager) = try makeAuthenticatedAPIClient()
        defer { try? keychainManager.clearTokens() }

        let submitted = expectation(description: "manual submit for \(sourceType.rawValue)")
        HomeViewModelMockURLProtocol.requestHandler = { request in
            if request.url?.path == "/api/v1/articles/manual" {
                submitted.fulfill()
            }
            let payload = """
            {"article_id": "server-art-1", "task_id": "task-1"}
            """.data(using: .utf8)!
            return (payload, self.makeResponse(statusCode: 202))
        }

        let article = Article(url: nil, title: sourceType.rawValue.capitalized)
        article.sourceType = sourceType
        article.markdownContent = content
        article.status = .failed
        context.insert(article)
        try context.save()

        let viewModel = HomeViewModel(context: context, isAuthenticated: true, apiClient: apiClient)
        viewModel.retryArticle(article)

        await fulfillment(of: [submitted], timeout: 1.0)
        try await waitForStatus(.processing, article: article)

        XCTAssertEqual(HomeViewModelMockURLProtocol.lastRequestPath, "/api/v1/articles/manual")

        let body = try XCTUnwrap(HomeViewModelMockURLProtocol.lastRequestBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["source_type"] as? String, sourceType.rawValue)
        XCTAssertEqual(json["client_id"] as? String, article.id.uuidString)
        XCTAssertEqual(json["content"] as? String, content)
    }

    @MainActor
    func testFetchArticles_returnsAllWhenNoFilter() throws {
        MockDataFactory.populateSampleData(context: context)
        let vm = HomeViewModel(context: context)
        vm.fetchArticles()
        XCTAssertEqual(vm.articles.count, 20) // page size = 20
    }

    @MainActor
    func testFetchArticles_sortedByDateDescending() throws {
        let a1 = Article(url: "https://example.com/1", title: "Old")
        a1.createdAt = Date(timeIntervalSince1970: 1000)
        let a2 = Article(url: "https://example.com/2", title: "New")
        a2.createdAt = Date(timeIntervalSince1970: 2000)
        context.insert(a1)
        context.insert(a2)
        try context.save()

        let vm = HomeViewModel(context: context)
        vm.fetchArticles()
        XCTAssertEqual(vm.articles.first?.title, "New")
        XCTAssertEqual(vm.articles.last?.title, "Old")
    }

    @MainActor
    func testPagination_loadsNextPage() throws {
        // Create 25 articles
        for i in 0..<25 {
            let a = Article(url: "https://example.com/\(i)", title: "Article \(i)")
            a.createdAt = Date(timeIntervalSinceNow: Double(-i) * 3600)
            context.insert(a)
        }
        try context.save()

        let vm = HomeViewModel(context: context)
        vm.fetchArticles()
        XCTAssertEqual(vm.articles.count, 20)

        vm.loadNextPage()
        XCTAssertEqual(vm.articles.count, 25)
    }

    @MainActor
    func testMarkAsRead() throws {
        let a = Article(url: "https://example.com/read", title: "Read me")
        context.insert(a)
        try context.save()
        XCTAssertEqual(a.readProgress, 0)

        let vm = HomeViewModel(context: context)
        vm.markAsRead(a)
        XCTAssertGreaterThan(a.readProgress, 0)
        XCTAssertNotNil(a.lastReadAt)
    }

    // MARK: - Action Method Tests

    @MainActor
    func testToggleFavorite_togglesIsFavorite() throws {
        let a = Article(url: "https://example.com/fav", title: "Fav")
        context.insert(a)
        try context.save()
        XCTAssertFalse(a.isFavorite)

        let vm = HomeViewModel(context: context)
        vm.toggleFavorite(a)
        XCTAssertTrue(a.isFavorite)

        vm.toggleFavorite(a)
        XCTAssertFalse(a.isFavorite)
    }

    @MainActor
    func testToggleFavorite_setsToast() throws {
        let a = Article(url: "https://example.com/fav-toast", title: "Fav Toast")
        context.insert(a)
        try context.save()

        let vm = HomeViewModel(context: context)
        vm.toggleFavorite(a)
        XCTAssertTrue(vm.showToast)
        XCTAssertFalse(vm.toastMessage.isEmpty)
    }

    @MainActor
    func testArchiveArticle_togglesIsArchived() throws {
        let a = Article(url: "https://example.com/archive", title: "Archive")
        context.insert(a)
        try context.save()
        XCTAssertFalse(a.isArchived)

        let vm = HomeViewModel(context: context)
        vm.archiveArticle(a)
        XCTAssertTrue(a.isArchived)

        vm.archiveArticle(a)
        XCTAssertFalse(a.isArchived)
    }

    @MainActor
    func testLoadSpark_storesInsights() async throws {
        let (apiClient, keychainManager) = try makeAuthenticatedAPIClient()
        defer { try? keychainManager.clearTokens() }

        HomeViewModelMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/knowledge/spark")
            let payload = """
            {
              "insights": [
                {
                  "insight": "Insight one",
                  "why_it_matters": "Why one",
                  "source_ids": ["a1", "a2"],
                  "followup_question": "Follow one?"
                }
              ]
            }
            """.data(using: .utf8)!
            return (payload, self.makeResponse(statusCode: 200))
        }

        let vm = HomeViewModel(context: context, isAuthenticated: true, apiClient: apiClient)
        await vm.loadSpark(prompt: "找连接")

        XCTAssertEqual(vm.sparkInsights.count, 1)
        XCTAssertEqual(vm.sparkInsights.first?.insight, "Insight one")
        XCTAssertNil(vm.knowledgeError)
    }

    @MainActor
    func testLoadLearn_storesStudyPack() async throws {
        let (apiClient, keychainManager) = try makeAuthenticatedAPIClient()
        defer { try? keychainManager.clearTokens() }

        HomeViewModelMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/knowledge/learn")
            let payload = """
            {
              "summary": "Learn summary",
              "items": [
                {
                  "type": "concept",
                  "title": "Concept one",
                  "content": "Content one",
                  "source_ids": ["a1"]
                }
              ]
            }
            """.data(using: .utf8)!
            return (payload, self.makeResponse(statusCode: 200))
        }

        let vm = HomeViewModel(context: context, isAuthenticated: true, apiClient: apiClient)
        await vm.loadLearn(prompt: "帮我复习")

        XCTAssertEqual(vm.learnSummary, "Learn summary")
        XCTAssertEqual(vm.learnItems.count, 1)
        XCTAssertEqual(vm.learnItems.first?.title, "Concept one")
        XCTAssertNil(vm.knowledgeError)
    }

    @MainActor
    func testArchiveArticle_setsToast() throws {
        let a = Article(url: "https://example.com/archive-toast", title: "Archive Toast")
        context.insert(a)
        try context.save()

        let vm = HomeViewModel(context: context)
        vm.archiveArticle(a)
        XCTAssertTrue(vm.showToast)
        XCTAssertFalse(vm.toastMessage.isEmpty)
    }

    @MainActor
    func testDeleteArticle_removesFromContext() throws {
        let a = Article(url: "https://example.com/delete", title: "Delete me")
        context.insert(a)
        try context.save()
        let id = a.id

        let vm = HomeViewModel(context: context)
        vm.deleteArticle(a)

        let descriptor = FetchDescriptor<Article>(predicate: #Predicate { $0.id == id })
        let found = try context.fetch(descriptor)
        XCTAssertTrue(found.isEmpty)
    }

    @MainActor
    func testDeleteArticle_setsToast() throws {
        let a = Article(url: "https://example.com/delete-toast", title: "Delete Toast")
        context.insert(a)
        try context.save()

        let vm = HomeViewModel(context: context)
        vm.deleteArticle(a)
        XCTAssertTrue(vm.showToast)
        XCTAssertFalse(vm.toastMessage.isEmpty)
    }

    @MainActor
    func testDeleteArticle_removesFromSearchIndex() throws {
        let searchIndexer = SearchIndexCoordinator(searchManager: try! FTS5SearchManager(inMemory: true))
        let article = Article(url: "https://example.com/search-delete", title: "Delete Search Index")
        context.insert(article)
        try context.save()
        searchIndexer.sync(article)

        XCTAssertEqual(try searchIndexer.searchManager.search(query: "Delete").count, 1)

        let vm = HomeViewModel(context: context, searchIndexCoordinator: searchIndexer)
        vm.deleteArticle(article)

        XCTAssertEqual(try searchIndexer.searchManager.search(query: "Delete").count, 0)
    }

    @MainActor
    func testFetchArticles_emptyDatabase() throws {
        let vm = HomeViewModel(context: context)
        vm.fetchArticles()
        XCTAssertTrue(vm.articles.isEmpty)
    }

    @MainActor
    func testLoadNextPage_noMorePages() throws {
        // Create fewer than page size (20) articles
        for i in 0..<5 {
            let a = Article(url: "https://example.com/small-\(i)", title: "Small \(i)")
            a.createdAt = Date(timeIntervalSinceNow: Double(-i) * 3600)
            context.insert(a)
        }
        try context.save()

        let vm = HomeViewModel(context: context)
        vm.fetchArticles()
        XCTAssertEqual(vm.articles.count, 5)

        // loadNextPage should be a no-op since hasMorePages is false
        vm.loadNextPage()
        XCTAssertEqual(vm.articles.count, 5)
    }

    @MainActor
    func testMarkAsRead_alreadyRead() throws {
        let a = Article(url: "https://example.com/already-read", title: "Already Read")
        a.readProgress = 0.5
        context.insert(a)
        try context.save()

        let vm = HomeViewModel(context: context)
        vm.markAsRead(a)
        // Should NOT reset readProgress to 0.01 since it's already > 0
        XCTAssertEqual(a.readProgress, 0.5)
    }

    @MainActor
    func testRetryArticle_screenshotUsesManualSubmit() async throws {
        try await assertTextOnlyRetryUsesManualSubmit(
            for: .screenshot,
            content: "Screenshot OCR content for retry."
        )
    }

    @MainActor
    func testRetryArticle_voiceUsesManualSubmit() async throws {
        try await assertTextOnlyRetryUsesManualSubmit(
            for: .voice,
            content: "Voice transcript content for retry."
        )
    }
}
