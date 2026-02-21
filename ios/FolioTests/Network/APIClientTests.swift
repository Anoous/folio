import XCTest
@testable import Folio

// MARK: - Mock URL Protocol

private final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (Data, HTTPURLResponse))?
    nonisolated(unsafe) static var lastRequestBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // Capture body from httpBody or httpBodyStream (URLSession converts httpBody to stream)
        if let body = request.httpBody {
            MockURLProtocol.lastRequestBody = body
        } else if let stream = request.httpBodyStream {
            stream.open()
            let bufferSize = 4096
            var data = Data()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer {
                buffer.deallocate()
                stream.close()
            }
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: bufferSize)
                if read > 0 {
                    data.append(buffer, count: read)
                } else {
                    break
                }
            }
            MockURLProtocol.lastRequestBody = data
        } else {
            MockURLProtocol.lastRequestBody = nil
        }

        guard let handler = MockURLProtocol.requestHandler else {
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

// MARK: - Tests

final class APIClientTests: XCTestCase {

    private var client: APIClient!
    private var keychainManager: KeyChainManager!
    private let baseURL = URL(string: "https://test.folio.app")!

    override func setUp() {
        super.setUp()
        keychainManager = KeyChainManager(service: "com.folio.app.api-tests")
        try? keychainManager.clearTokens()

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        client = APIClient(baseURL: baseURL, keychainManager: keychainManager, session: session)
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        MockURLProtocol.lastRequestBody = nil
        try? keychainManager.clearTokens()
        keychainManager = nil
        client = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeResponse(statusCode: Int, url: URL? = nil) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url ?? baseURL,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    private func authResponseJSON() -> Data {
        """
        {
            "access_token": "new_access",
            "refresh_token": "new_refresh",
            "expires_in": 7200,
            "user": {
                "id": "user-1",
                "subscription": "free",
                "monthly_quota": 30,
                "current_month_count": 0,
                "preferred_language": "zh-Hans",
                "created_at": "2025-01-01T00:00:00Z",
                "updated_at": "2025-01-01T00:00:00Z"
            }
        }
        """.data(using: .utf8)!
    }

    // MARK: - Success Requests

    func testLoginWithApple_decodesResponse() async throws {
        MockURLProtocol.requestHandler = { _ in
            (self.authResponseJSON(), self.makeResponse(statusCode: 200))
        }

        let response = try await client.loginWithApple(identityToken: "id_token", email: "a@b.com", nickname: "Test")
        XCTAssertEqual(response.accessToken, "new_access")
        XCTAssertEqual(response.refreshToken, "new_refresh")
        XCTAssertEqual(response.expiresIn, 7200)
        XCTAssertEqual(response.user.id, "user-1")
        XCTAssertEqual(keychainManager.accessToken, "new_access")
        XCTAssertEqual(keychainManager.refreshToken, "new_refresh")
    }

    func testLoginDev_decodesResponse() async throws {
        MockURLProtocol.requestHandler = { _ in
            (self.authResponseJSON(), self.makeResponse(statusCode: 200))
        }

        let response = try await client.loginDev()
        XCTAssertEqual(response.accessToken, "new_access")
        XCTAssertEqual(keychainManager.accessToken, "new_access")
    }

    func testSubmitArticle_returns202() async throws {
        try keychainManager.saveTokens(access: "token", refresh: "r")
        let json = """
        {"article_id": "art-1", "task_id": "task-1"}
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { _ in
            (json, self.makeResponse(statusCode: 202))
        }

        let response = try await client.submitArticle(url: "https://example.com")
        XCTAssertEqual(response.articleId, "art-1")
        XCTAssertEqual(response.taskId, "task-1")
    }

    func testListArticles_decodesPaginated() async throws {
        try keychainManager.saveTokens(access: "token", refresh: "r")
        let json = """
        {
            "data": [{
                "id": "a1",
                "url": "https://example.com",
                "word_count": 500,
                "status": "ready",
                "source_type": "web",
                "retry_count": 0,
                "is_favorite": false,
                "is_archived": false,
                "read_progress": 0.0,
                "created_at": "2025-01-01T00:00:00Z",
                "updated_at": "2025-01-01T00:00:00Z"
            }],
            "pagination": {"page": 1, "per_page": 20, "total": 1}
        }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { _ in
            (json, self.makeResponse(statusCode: 200))
        }

        let response = try await client.listArticles()
        XCTAssertEqual(response.data.count, 1)
        XCTAssertEqual(response.data[0].id, "a1")
        XCTAssertEqual(response.pagination.total, 1)
    }

    func testGetArticle_decodesFullDetail() async throws {
        try keychainManager.saveTokens(access: "token", refresh: "r")
        let json = """
        {
            "id": "a1",
            "url": "https://example.com",
            "title": "Test Article",
            "word_count": 1000,
            "status": "ready",
            "source_type": "web",
            "retry_count": 0,
            "is_favorite": true,
            "is_archived": false,
            "read_progress": 0.5,
            "created_at": "2025-01-01T00:00:00Z",
            "updated_at": "2025-01-01T00:00:00Z",
            "category": {
                "id": "c1",
                "slug": "tech",
                "name_zh": "科技",
                "name_en": "Technology",
                "sort_order": 1,
                "created_at": "2025-01-01T00:00:00Z"
            },
            "tags": [{
                "id": "t1",
                "name": "Swift",
                "is_ai_generated": true,
                "article_count": 5,
                "created_at": "2025-01-01T00:00:00Z"
            }]
        }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { _ in
            (json, self.makeResponse(statusCode: 200))
        }

        let article = try await client.getArticle(id: "a1")
        XCTAssertEqual(article.title, "Test Article")
        XCTAssertEqual(article.category?.slug, "tech")
        XCTAssertEqual(article.tags?.count, 1)
        XCTAssertEqual(article.tags?[0].name, "Swift")
    }

    func testGetTask_decodesStatus() async throws {
        try keychainManager.saveTokens(access: "token", refresh: "r")
        let json = """
        {
            "id": "task-1",
            "article_id": "art-1",
            "url": "https://example.com",
            "status": "done",
            "retry_count": 0,
            "created_at": "2025-01-01T00:00:00Z",
            "updated_at": "2025-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { _ in
            (json, self.makeResponse(statusCode: 200))
        }

        let task = try await client.getTask(id: "task-1")
        XCTAssertEqual(task.id, "task-1")
        XCTAssertEqual(task.status, "done")
        XCTAssertEqual(task.articleId, "art-1")
    }

    func testListCategories_decodesArray() async throws {
        try keychainManager.saveTokens(access: "token", refresh: "r")
        let json = """
        {
            "data": [{
                "id": "c1",
                "slug": "tech",
                "name_zh": "科技",
                "name_en": "Technology",
                "sort_order": 1,
                "created_at": "2025-01-01T00:00:00Z"
            }],
            "pagination": {"page": 1, "per_page": 20, "total": 1}
        }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { _ in
            (json, self.makeResponse(statusCode: 200))
        }

        let response = try await client.listCategories()
        XCTAssertEqual(response.data.count, 1)
        XCTAssertEqual(response.data[0].nameZh, "科技")
    }

    // MARK: - Error Handling

    func testRequest_403_throwsForbidden() async {
        try? keychainManager.saveTokens(access: "token", refresh: "r")
        MockURLProtocol.requestHandler = { _ in
            (Data(), self.makeResponse(statusCode: 403))
        }

        do {
            _ = try await client.getArticle(id: "x")
            XCTFail("Should throw")
        } catch {
            XCTAssertEqual(error as? APIError, .forbidden)
        }
    }

    func testRequest_404_throwsNotFound() async {
        try? keychainManager.saveTokens(access: "token", refresh: "r")
        MockURLProtocol.requestHandler = { _ in
            (Data(), self.makeResponse(statusCode: 404))
        }

        do {
            _ = try await client.getArticle(id: "x")
            XCTFail("Should throw")
        } catch {
            XCTAssertEqual(error as? APIError, .notFound)
        }
    }

    func testRequest_429_throwsQuotaExceeded() async {
        try? keychainManager.saveTokens(access: "token", refresh: "r")
        MockURLProtocol.requestHandler = { _ in
            (Data(), self.makeResponse(statusCode: 429))
        }

        do {
            _ = try await client.getArticle(id: "x")
            XCTFail("Should throw")
        } catch {
            XCTAssertEqual(error as? APIError, .quotaExceeded)
        }
    }

    func testRequest_500_throwsServerError() async {
        try? keychainManager.saveTokens(access: "token", refresh: "r")
        MockURLProtocol.requestHandler = { _ in
            (Data(), self.makeResponse(statusCode: 500))
        }

        do {
            _ = try await client.getArticle(id: "x")
            XCTFail("Should throw")
        } catch {
            XCTAssertEqual(error as? APIError, .serverError(500))
        }
    }

    // MARK: - Auth Header

    func testAuthEndpoints_noBearerToken() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (self.authResponseJSON(), self.makeResponse(statusCode: 200))
        }

        _ = try await client.loginDev()
        XCTAssertNil(capturedRequest?.value(forHTTPHeaderField: "Authorization"))
    }

    func testProtectedEndpoints_sendBearerToken() async throws {
        try keychainManager.saveTokens(access: "my_token", refresh: "r")
        let json = """
        {"data": [], "pagination": {"page": 1, "per_page": 20, "total": 0}}
        """.data(using: .utf8)!

        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (json, self.makeResponse(statusCode: 200))
        }

        _ = try await client.listTags()
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer my_token")
    }

    // MARK: - Token Refresh

    func testRequest_401_refreshThenRetry() async throws {
        try keychainManager.saveTokens(access: "expired", refresh: "valid_refresh")
        let articleJSON = """
        {
            "data": [],
            "pagination": {"page": 1, "per_page": 20, "total": 0}
        }
        """.data(using: .utf8)!

        var callCount = 0
        MockURLProtocol.requestHandler = { request in
            callCount += 1
            let path = request.url?.path ?? ""

            // First call: original request returns 401
            if callCount == 1 {
                return (Data(), self.makeResponse(statusCode: 401))
            }
            // Second call: refresh token request
            if path.contains("auth/refresh") {
                return (self.authResponseJSON(), self.makeResponse(statusCode: 200))
            }
            // Third call: retry original request
            return (articleJSON, self.makeResponse(statusCode: 200))
        }

        _ = try await client.listTags()
        XCTAssertEqual(keychainManager.accessToken, "new_access")
        XCTAssertEqual(keychainManager.refreshToken, "new_refresh")
        XCTAssertGreaterThanOrEqual(callCount, 3)
    }

    func testRequest_401_refreshFails_clearsTokens() async {
        try? keychainManager.saveTokens(access: "expired", refresh: "bad_refresh")

        var callCount = 0
        MockURLProtocol.requestHandler = { request in
            callCount += 1
            if callCount == 1 {
                return (Data(), self.makeResponse(statusCode: 401))
            }
            // Refresh fails with 403
            return (Data(), self.makeResponse(statusCode: 403))
        }

        do {
            let _: ListResponse<TagDTO> = try await client.listTags()
            XCTFail("Should throw")
        } catch {
            XCTAssertNil(keychainManager.accessToken)
            XCTAssertNil(keychainManager.refreshToken)
        }
    }

    func testRequest_401_refreshFails_throwsUnauthorized() async {
        try? keychainManager.saveTokens(access: "expired", refresh: "bad_refresh")

        var callCount = 0
        MockURLProtocol.requestHandler = { request in
            callCount += 1
            if callCount == 1 {
                return (Data(), self.makeResponse(statusCode: 401))
            }
            return (Data(), self.makeResponse(statusCode: 403))
        }

        do {
            let _: ListResponse<TagDTO> = try await client.listTags()
            XCTFail("Should throw")
        } catch {
            XCTAssertEqual(error as? APIError, .unauthorized)
        }
    }

    // MARK: - Encoding

    func testSnakeCaseEncoding() async throws {
        MockURLProtocol.requestHandler = { _ in
            (self.authResponseJSON(), self.makeResponse(statusCode: 200))
        }

        _ = try await client.loginWithApple(identityToken: "tok", email: nil, nickname: nil)
        let body = MockURLProtocol.lastRequestBody.flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        }
        XCTAssertNotNil(body?["identity_token"])
    }

    func testUpdateArticle_omitsNilFields() async throws {
        try keychainManager.saveTokens(access: "token", refresh: "r")
        let statusJSON = """
        {"status": "ok"}
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { _ in
            (statusJSON, self.makeResponse(statusCode: 200))
        }

        let req = UpdateArticleRequest(isFavorite: true, isArchived: nil, readProgress: nil)
        try await client.updateArticle(id: "a1", request: req)
        let body = MockURLProtocol.lastRequestBody.flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        }
        XCTAssertNotNil(body?["is_favorite"])
        XCTAssertNil(body?["is_archived"])
        XCTAssertNil(body?["read_progress"])
    }
}
