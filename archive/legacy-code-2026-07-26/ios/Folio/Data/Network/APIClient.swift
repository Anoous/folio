// MARK: - Network Layer
import Foundation

// MARK: - Shared ISO8601 Formatters

/// Reusable formatters — `ISO8601DateFormatter` is expensive to create.
private enum ISO8601Formatters {
    static let standard: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

// MARK: - SSE Event Parser

enum SSEEventParser {
    static func parse(eventType: String, data: String) throws -> RAGStreamEvent {
        let jsonData = Data(data.utf8)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            if let date = ISO8601Formatters.fractional.date(from: dateString) { return date }
            if let date = ISO8601Formatters.standard.date(from: dateString) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(dateString)")
        }

        switch eventType {
        case "sources":
            let payload = try decoder.decode(RAGSourcesPayload.self, from: jsonData)
            return .sources(payload)
        case "delta":
            struct DeltaPayload: Codable { let text: String }
            let payload = try decoder.decode(DeltaPayload.self, from: jsonData)
            return .delta(payload.text)
        case "done":
            let payload = try decoder.decode(RAGDonePayload.self, from: jsonData)
            return .done(payload)
        case "error":
            let payload = try decoder.decode(RAGStreamError.self, from: jsonData)
            return .error(payload)
        default:
            throw URLError(.cannotParseResponse)
        }
    }
}

// MARK: - APIClient

final class APIClient: @unchecked Sendable {
    static let shared = APIClient()

    private let baseURL: URL
    private let session: URLSession
    private let keychainManager: KeyChainManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let refreshCoordinator = RefreshCoordinator()

    #if DEBUG
        #if targetEnvironment(simulator)
        static let defaultBaseURL = URL(string: "http://localhost:8080")!
        #else
        // Staging server via Cloudflare Tunnel
        static let defaultBaseURL = URL(string: "https://api.echolore.ai")!
        #endif
    #else
    static let defaultBaseURL = URL(string: "https://api.folio.app")!
    #endif

    init(
        baseURL: URL = APIClient.defaultBaseURL,
        keychainManager: KeyChainManager = .shared,
        session: URLSession? = nil
    ) {
        self.baseURL = baseURL
        self.keychainManager = keychainManager

        if let session {
            self.session = session
        } else {
            self.session = URLSession.shared
        }

        self.encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ISO8601Formatters.fractional.string(from: date))
        }

        self.decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)

            if let date = ISO8601Formatters.standard.date(from: string) {
                return date
            }

            if let date = ISO8601Formatters.fractional.date(from: string) {
                return date
            }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date: \(string)")
        }
    }

    // MARK: - Core Request

    private func makeRequest(
        method: String,
        path: String,
        queryItems: [URLQueryItem]? = nil,
        body: (any Encodable)? = nil,
        requiresAuth: Bool = true
    ) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: true) else {
            throw APIError.invalidURL
        }

        if let queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method

        FolioLogger.network.debug("\(method) \(path)")

        if requiresAuth, let token = keychainManager.accessToken {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do {
                urlRequest.httpBody = try encoder.encode(AnyEncodable(body))
            } catch {
                throw APIError.encodingFailed
            }
        }

        return urlRequest
    }

    private func performDataRequest(_ urlRequest: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.networkError("Invalid response")
            }
            return (data, httpResponse)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(error.localizedDescription)
        }
    }

    private func performByteStreamRequest(_ urlRequest: URLRequest) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        do {
            let (bytes, response) = try await session.bytes(for: urlRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.networkError("Invalid response")
            }
            return (bytes, httpResponse)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(error.localizedDescription)
        }
    }

    private func httpError(statusCode: Int, data: Data) -> APIError {
        switch statusCode {
        case 401:
            return .unauthorized
        case 403:
            return .forbidden
        case 404:
            return .notFound
        case 409:
            return .conflict
        case 429:
            return .quotaExceeded
        default:
            if statusCode >= 500 {
                return .serverError(statusCode)
            }
            if let errorResponse = try? decoder.decode(APIErrorResponse.self, from: data) {
                return .serverMessage(errorResponse.error)
            }
            return .serverError(statusCode)
        }
    }

    private func collectStreamBody(_ bytes: URLSession.AsyncBytes) async throws -> Data {
        var bodyData = Data()
        for try await byte in bytes {
            bodyData.append(byte)
        }
        return bodyData
    }

    private func request<T: Decodable>(
        method: String,
        path: String,
        queryItems: [URLQueryItem]? = nil,
        body: (any Encodable)? = nil,
        requiresAuth: Bool = true,
        isRetryAfterRefresh: Bool = false
    ) async throws -> T {
        let urlRequest = try makeRequest(
            method: method,
            path: path,
            queryItems: queryItems,
            body: body,
            requiresAuth: requiresAuth
        )
        let (data, httpResponse) = try await performDataRequest(urlRequest)

        if (200...299).contains(httpResponse.statusCode) {
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIError.decodingFailed(error.localizedDescription)
            }
        }

        if httpResponse.statusCode == 401, requiresAuth, !isRetryAfterRefresh {
            FolioLogger.network.info("401 unauthorized, attempting refresh — \(path)")
            try await performTokenRefresh()
            return try await request(
                method: method,
                path: path,
                queryItems: queryItems,
                body: body,
                requiresAuth: requiresAuth,
                isRetryAfterRefresh: true
            )
        }

        FolioLogger.network.error("HTTP \(httpResponse.statusCode) — \(method) \(path)")
        throw httpError(statusCode: httpResponse.statusCode, data: data)
    }

    // Variant for void responses (DELETE, PUT).
    // Handles both 200 (with JSON body) and 204 No Content (empty body).
    private func requestVoid(
        method: String,
        path: String,
        body: (any Encodable)? = nil,
        requiresAuth: Bool = true,
        isRetryAfterRefresh: Bool = false
    ) async throws {
        let urlRequest = try makeRequest(
            method: method,
            path: path,
            body: body,
            requiresAuth: requiresAuth
        )
        let (data, httpResponse) = try await performDataRequest(urlRequest)

        if (200...299).contains(httpResponse.statusCode) {
            return // Success — ignore body (handles both 200 and 204)
        }

        if httpResponse.statusCode == 401, requiresAuth, !isRetryAfterRefresh {
            FolioLogger.network.info("401 unauthorized, attempting refresh — \(path)")
            try await performTokenRefresh()
            try await requestVoid(
                method: method,
                path: path,
                body: body,
                requiresAuth: requiresAuth,
                isRetryAfterRefresh: true
            )
            return
        }

        FolioLogger.network.error("HTTP \(httpResponse.statusCode) — \(method) \(path)")
        throw httpError(statusCode: httpResponse.statusCode, data: data)
    }

    // MARK: - Token Refresh

    private func performTokenRefresh() async throws {
        try await refreshCoordinator.refresh { [self] in
            try await refreshTokensInternal()
        }
    }

    private func refreshTokensInternal() async throws {
        guard let refresh = keychainManager.refreshToken else {
            try? keychainManager.clearTokens()
            throw APIError.unauthorized
        }

        let body = ["refresh_token": refresh]

        guard let components = URLComponents(url: baseURL.appendingPathComponent("/api/v1/auth/refresh"), resolvingAgainstBaseURL: true),
              let url = components.url else {
            throw APIError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            // Network error (timeout, no internet, DNS failure) — do NOT clear
            // tokens. The refresh token may still be valid; clearing it would
            // force a full re-login on a transient network blip.
            FolioLogger.network.error("token refresh: network error — \(error.localizedDescription)")
            throw APIError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            FolioLogger.network.error("token refresh: invalid response")
            throw APIError.networkError("Invalid response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            FolioLogger.network.error("token refresh failed: HTTP \(httpResponse.statusCode)")
            // Only clear tokens when the server explicitly rejects them.
            // 5xx errors are transient server issues, not auth failures.
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                try? keychainManager.clearTokens()
            }
            throw APIError.unauthorized
        }

        let authResponse = try decoder.decode(AuthResponse.self, from: data)
        try keychainManager.saveTokens(access: authResponse.accessToken, refresh: authResponse.refreshToken)
        FolioLogger.network.info("token refresh succeeded")
    }

    // MARK: - Auth

    func loginWithApple(identityToken: String, email: String?, nickname: String?) async throws -> AuthResponse {
        struct AppleLoginRequest: Encodable {
            let identityToken: String
            let email: String?
            let nickname: String?
        }
        let body = AppleLoginRequest(identityToken: identityToken, email: email, nickname: nickname)
        let response: AuthResponse = try await request(
            method: "POST",
            path: "/api/v1/auth/apple",
            body: body,
            requiresAuth: false
        )
        try keychainManager.saveTokens(access: response.accessToken, refresh: response.refreshToken)
        return response
    }

    func refreshAuth() async throws -> AuthResponse {
        guard let refresh = keychainManager.refreshToken else {
            throw APIError.unauthorized
        }
        let body = ["refresh_token": refresh]
        let response: AuthResponse = try await request(
            method: "POST",
            path: "/api/v1/auth/refresh",
            body: body,
            requiresAuth: false
        )
        try keychainManager.saveTokens(access: response.accessToken, refresh: response.refreshToken)
        return response
    }

    func logout(refreshToken: String? = nil) async throws {
        guard let refreshToken = refreshToken ?? keychainManager.refreshToken else {
            throw APIError.unauthorized
        }

        let body = ["refresh_token": refreshToken]
        try await requestVoid(
            method: "POST",
            path: "/api/v1/auth/logout",
            body: body,
            requiresAuth: false
        )
    }

    // MARK: - Email Auth

    func sendEmailCode(email: String) async throws {
        struct SendCodeRequest: Encodable {
            let email: String
        }
        struct MessageResponse: Decodable {
            let message: String
        }
        let _: MessageResponse = try await request(
            method: "POST",
            path: "/api/v1/auth/email/code",
            body: SendCodeRequest(email: email),
            requiresAuth: false
        )
    }

    func verifyEmailCode(email: String, code: String) async throws -> AuthResponse {
        struct VerifyCodeRequest: Encodable {
            let email: String
            let code: String
        }
        let response: AuthResponse = try await request(
            method: "POST",
            path: "/api/v1/auth/email/verify",
            body: VerifyCodeRequest(email: email, code: code),
            requiresAuth: false
        )
        try keychainManager.saveTokens(access: response.accessToken, refresh: response.refreshToken)
        return response
    }

    // MARK: - Articles

    func submitArticle(
        url: String?,
        tagIds: [String] = [],
        title: String? = nil,
        author: String? = nil,
        siteName: String? = nil,
        markdownContent: String? = nil,
        wordCount: Int? = nil
    ) async throws -> SubmitArticleResponse {
        var body = SubmitArticleRequest(url: url, tagIds: tagIds.isEmpty ? nil : tagIds)
        body.title = title
        body.author = author
        body.siteName = siteName
        body.markdownContent = markdownContent
        body.wordCount = wordCount
        return try await request(method: "POST", path: "/api/v1/articles", body: body)
    }

    func submitManualContent(content: String, title: String? = nil, tagIds: [String] = [], clientId: String? = nil, sourceType: String? = nil) async throws -> SubmitArticleResponse {
        var body = SubmitManualContentRequest(content: content)
        body.title = title
        body.tagIds = tagIds.isEmpty ? nil : tagIds
        body.clientId = clientId
        body.sourceType = sourceType
        return try await request(method: "POST", path: "/api/v1/articles/manual", body: body)
    }

    func listArticles(
        page: Int = 1,
        perPage: Int = 20,
        category: String? = nil,
        status: String? = nil,
        favorite: Bool? = nil,
        updatedSince: Date? = nil
    ) async throws -> ListResponse<ArticleDTO> {
        var queryItems = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "per_page", value: "\(perPage)")
        ]
        if let category {
            queryItems.append(URLQueryItem(name: "category", value: category))
        }
        if let status {
            queryItems.append(URLQueryItem(name: "status", value: status))
        }
        if let favorite {
            queryItems.append(URLQueryItem(name: "favorite", value: favorite ? "true" : "false"))
        }
        if let updatedSince {
            queryItems.append(URLQueryItem(name: "updated_since", value: ISO8601Formatters.standard.string(from: updatedSince)))
        }
        return try await request(method: "GET", path: "/api/v1/articles", queryItems: queryItems)
    }

    func getArticle(id: String) async throws -> ArticleDTO {
        return try await request(method: "GET", path: "/api/v1/articles/\(id)")
    }

    func updateArticle(id: String, request: UpdateArticleRequest) async throws {
        try await requestVoid(method: "PUT", path: "/api/v1/articles/\(id)", body: request)
    }

    func deleteArticle(id: String) async throws {
        try await requestVoid(method: "DELETE", path: "/api/v1/articles/\(id)")
    }

    // MARK: - Tasks

    func getTask(id: String) async throws -> CrawlTaskDTO {
        return try await request(method: "GET", path: "/api/v1/tasks/\(id)")
    }

    // MARK: - Tags

    func listTags() async throws -> ListResponse<TagDTO> {
        return try await request(method: "GET", path: "/api/v1/tags")
    }

    func createTag(name: String) async throws -> TagDTO {
        return try await request(method: "POST", path: "/api/v1/tags", body: CreateTagRequest(name: name))
    }

    func deleteTag(id: String) async throws {
        try await requestVoid(method: "DELETE", path: "/api/v1/tags/\(id)")
    }

    // MARK: - Categories

    func listCategories() async throws -> ListResponse<CategoryDTO> {
        return try await request(method: "GET", path: "/api/v1/categories")
    }

    // MARK: - Echo

    func getEchoToday(limit: Int = 5) async throws -> EchoTodayResponse {
        return try await request(method: "GET", path: "/api/v1/echo/today", queryItems: [
            URLQueryItem(name: "limit", value: "\(limit)")
        ])
    }

    func submitEchoReview(cardID: String, result: String, responseTimeMs: Int? = nil) async throws -> EchoReviewResponse {
        let body = EchoReviewRequest(result: result, responseTimeMs: responseTimeMs)
        return try await request(method: "POST", path: "/api/v1/echo/\(cardID)/review", body: body)
    }

    // MARK: - Highlights

    func createHighlight(articleID: String, text: String, startOffset: Int, endOffset: Int) async throws -> HighlightDTO {
        let body = CreateHighlightRequest(text: text, startOffset: startOffset, endOffset: endOffset)
        return try await request(method: "POST", path: "/api/v1/articles/\(articleID)/highlights", body: body)
    }

    func getHighlights(articleID: String) async throws -> HighlightsResponse {
        return try await request(method: "GET", path: "/api/v1/articles/\(articleID)/highlights")
    }

    func deleteHighlight(id: String) async throws {
        try await requestVoid(method: "DELETE", path: "/api/v1/highlights/\(id)")
    }

    // MARK: - RAG

    func ragQuery(question: String, conversationId: String? = nil) async throws -> RAGQueryResponse {
        let body = RAGQueryRequest(question: question, conversationId: conversationId)
        return try await request(method: "POST", path: "/api/v1/rag/query", body: body)
    }

    func ragQueryStream(question: String, conversationId: String? = nil) -> AsyncThrowingStream<RAGStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let body = RAGQueryRequest(question: question, conversationId: conversationId)
                    let request = try makeRequest(
                        method: "POST",
                        path: "/api/v1/rag/query/stream",
                        body: body
                    )
                    var (bytes, httpResponse) = try await performByteStreamRequest(request)

                    if httpResponse.statusCode == 401 {
                        FolioLogger.network.info("401 unauthorized, attempting refresh — /api/v1/rag/query/stream")
                        try await performTokenRefresh()
                        let retryRequest = try makeRequest(
                            method: "POST",
                            path: "/api/v1/rag/query/stream",
                            body: body
                        )
                        (bytes, httpResponse) = try await performByteStreamRequest(retryRequest)
                    }

                    if httpResponse.statusCode != 200 {
                        let bodyData = try await collectStreamBody(bytes)
                        FolioLogger.network.error("HTTP \(httpResponse.statusCode) — POST /api/v1/rag/query/stream")
                        throw httpError(statusCode: httpResponse.statusCode, data: bodyData)
                    }

                    try await self.parseSSEStream(bytes, continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            // Cancel the internal task when the consumer stops iterating
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Knowledge

    func knowledgeSpark(prompt: String = "") async throws -> SparkResponse {
        let body = ["prompt": prompt]
        return try await request(method: "POST", path: "/api/v1/knowledge/spark", body: body)
    }

    func knowledgeLearn(prompt: String = "") async throws -> LearnResponse {
        let body = ["prompt": prompt]
        return try await request(method: "POST", path: "/api/v1/knowledge/learn", body: body)
    }

    private func parseSSEStream(
        _ bytes: URLSession.AsyncBytes,
        continuation: AsyncThrowingStream<RAGStreamEvent, Error>.Continuation
    ) async throws {
        var currentEventType: String?
        var currentData: String?

        for try await line in bytes.lines {
            if line.hasPrefix("event: ") {
                // New event starting — emit any pending event first
                if let eventType = currentEventType, let data = currentData {
                    let event = try SSEEventParser.parse(eventType: eventType, data: data)
                    continuation.yield(event)
                }
                currentEventType = String(line.dropFirst(7))
                currentData = nil
            } else if line.hasPrefix("data: ") {
                currentData = String(line.dropFirst(6))
            }
            // Empty lines are ignored — we emit on next "event:" or stream end
        }
        // Emit final pending event when stream ends
        if let eventType = currentEventType, let data = currentData {
            let event = try SSEEventParser.parse(eventType: eventType, data: data)
            continuation.yield(event)
        }

        continuation.finish()
    }

    // MARK: - Subscription

    func verifySubscription(transactionID: UInt64, productID: String) async throws -> VerifySubscriptionResponse {
        struct VerifySubscriptionRequest: Encodable {
            let transactionId: String
            let productId: String
        }
        let body = VerifySubscriptionRequest(
            transactionId: String(transactionID),
            productId: productID
        )
        return try await request(method: "POST", path: "/api/v1/subscription/verify", body: body)
    }

    // MARK: - Device Registration

    struct RegisterDeviceRequest: Codable {
        let token: String
        let platform: String
    }

    func registerDevice(token: String) async throws {
        let body = RegisterDeviceRequest(token: token, platform: "ios")
        let _: StatusResponse = try await request(method: "POST", path: "/api/v1/devices", body: body)
    }

    // MARK: - Stats

    func getMonthlyStats(month: String? = nil) async throws -> MonthlyStatsResponse {
        var queryItems: [URLQueryItem] = []
        if let month { queryItems.append(URLQueryItem(name: "month", value: month)) }
        return try await request(method: "GET", path: "/api/v1/stats/monthly", queryItems: queryItems.isEmpty ? nil : queryItems)
    }

    func getEchoStats(month: String? = nil) async throws -> EchoStatsResponse {
        var queryItems: [URLQueryItem] = []
        if let month { queryItems.append(URLQueryItem(name: "month", value: month)) }
        return try await request(method: "GET", path: "/api/v1/stats/echo", queryItems: queryItems.isEmpty ? nil : queryItems)
    }
}

// MARK: - Refresh Coordinator

private actor RefreshCoordinator {
    private var activeTask: Task<Void, Error>?

    func refresh(using block: @Sendable @escaping () async throws -> Void) async throws {
        if let existing = activeTask {
            return try await existing.value
        }
        let task = Task { try await block() }
        activeTask = task
        defer { activeTask = nil }
        try await task.value
    }
}

// MARK: - AnyEncodable

private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    init(_ wrapped: any Encodable) {
        _encode = { encoder in
            try wrapped.encode(to: encoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
