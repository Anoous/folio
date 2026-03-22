// MARK: - Network Layer
import Foundation
import os

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

// MARK: - APIError

enum APIError: Error, Equatable {
    case invalidURL
    case encodingFailed
    case decodingFailed(String)
    case unauthorized
    case forbidden
    case notFound
    case quotaExceeded
    case conflict
    case serverError(Int)
    case networkError(String)
    case serverMessage(String)
}

// MARK: - DTO Types

// MARK: Auth

struct AuthResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let user: UserDTO
}

struct UserDTO: Decodable {
    let id: String
    let email: String?
    let nickname: String?
    let avatarUrl: String?
    let subscription: String
    let subscriptionExpiresAt: Date?
    let monthlyQuota: Int
    let currentMonthCount: Int
    let preferredLanguage: String
    let createdAt: Date
    let updatedAt: Date
    let syncEpoch: Int?

    /// Normalizes "pro_plus" → "pro" for client-side display.
    var effectiveSubscription: String {
        subscription == AppConstants.subscriptionProPlus
            ? AppConstants.subscriptionPro
            : subscription
    }

    /// Whether this user has an active Pro (or Pro+) subscription.
    var isPro: Bool {
        effectiveSubscription == AppConstants.subscriptionPro
    }
}

// MARK: Articles

struct SubmitArticleRequest: Encodable {
    let url: String?
    let tagIds: [String]?
    var title: String?
    var author: String?
    var siteName: String?
    var markdownContent: String?
    var wordCount: Int?
}

struct SubmitArticleResponse: Decodable {
    let articleId: String
    let taskId: String
}

struct SubmitManualContentRequest: Encodable {
    let content: String
    var title: String?
    var tagIds: [String]?
    var clientId: String?

    enum CodingKeys: String, CodingKey {
        case content, title
        case tagIds = "tag_ids"
        case clientId = "client_id"
    }
}

struct ArticleDTO: Decodable {
    let id: String
    let url: String?
    let title: String?
    let author: String?
    let siteName: String?
    let faviconUrl: String?
    let coverImageUrl: String?
    let markdownContent: String?
    let wordCount: Int
    let language: String?
    let categoryId: String?
    let summary: String?
    let keyPoints: [String]?
    let aiConfidence: Double?
    let status: String
    let sourceType: String
    let fetchError: String?
    let retryCount: Int
    let isFavorite: Bool
    let isArchived: Bool
    let readProgress: Double
    let lastReadAt: Date?
    let publishedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let category: CategoryDTO?
    let tags: [TagDTO]?
}

struct UpdateArticleRequest: Encodable {
    var isFavorite: Bool?
    var isArchived: Bool?
    var readProgress: Double?
}

// MARK: Tasks

struct CrawlTaskDTO: Decodable {
    let id: String
    let articleId: String?
    let url: String?
    let sourceType: String?
    let status: String
    let errorMessage: String?
    let retryCount: Int
    let createdAt: Date
    let updatedAt: Date
}

// MARK: Tags & Categories

struct TagDTO: Decodable {
    let id: String
    let name: String
    let isAiGenerated: Bool
    let articleCount: Int
    let createdAt: Date
}

struct CategoryDTO: Decodable {
    let id: String
    let slug: String
    let nameZh: String
    let nameEn: String
    let icon: String?
    let sortOrder: Int
    let createdAt: Date
}

struct CreateTagRequest: Encodable {
    let name: String
}

// MARK: Common

struct APIErrorResponse: Decodable {
    let error: String
}

struct StatusResponse: Decodable {
    let status: String
}

struct PaginationDTO: Decodable {
    let page: Int
    let perPage: Int
    let total: Int
}

struct ListResponse<T: Decodable>: Decodable {
    let data: [T]
    let pagination: PaginationDTO
    let serverTime: String?
    let syncEpoch: Int?
}

// MARK: - Highlight DTOs

struct HighlightDTO: Codable {
    let id: String
    let text: String
    let startOffset: Int
    let endOffset: Int
    let color: String
    let createdAt: Date
}

struct CreateHighlightRequest: Codable {
    let text: String
    let startOffset: Int
    let endOffset: Int
}

struct HighlightsResponse: Codable {
    let data: [HighlightDTO]
}

// MARK: - Echo DTOs

struct EchoCardDTO: Codable {
    let id: String
    let articleId: String
    let articleTitle: String
    let cardType: String
    let question: String
    let answer: String
    let sourceContext: String?
    let nextReviewAt: Date
    let intervalDays: Int
    let reviewCount: Int
}

struct EchoTodayResponse: Codable {
    let data: [EchoCardDTO]
    let remainingToday: Int
    let weeklyCount: Int
    let weeklyLimit: Int?
}

struct EchoReviewRequest: Codable {
    let result: String
    let responseTimeMs: Int?
}

struct EchoReviewResponse: Codable {
    let nextReviewAt: Date
    let intervalDays: Int
    let reviewCount: Int
    let correctCount: Int
    let streak: EchoStreak
}

struct EchoStreak: Codable {
    let weeklyRate: Int
    let consecutiveDays: Int
    let display: String
}

// MARK: - RAG DTOs

struct RAGQueryRequest: Codable {
    let question: String
    let conversationId: String?
}

struct RAGQueryResponse: Codable {
    let answer: String
    let sources: [RAGSource]
    let sourceCount: Int
    let followupSuggestions: [String]
    let conversationId: String
}

struct RAGSource: Codable {
    let articleId: String
    let title: String
    let siteName: String?
    let summary: String?
    let createdAt: Date
    let relevance: Double
}

// MARK: - Stats DTOs

struct MonthlyStatsResponse: Codable {
    let articlesCount: Int
    let insightsCount: Int
    let streakDays: Int
    let topicDistribution: [TopicStat]
    let trendInsight: String?
}

struct TopicStat: Codable {
    let categorySlug: String
    let categoryName: String
    let count: Int
}

struct EchoStatsResponse: Codable {
    let completionRate: Int
    let totalReviews: Int
    let rememberedCount: Int
    let forgottenCount: Int
}

// MARK: Subscription

struct VerifySubscriptionResponse: Decodable {
    let subscription: String
    let expiresAt: Date?
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

    private func request<T: Decodable>(
        method: String,
        path: String,
        queryItems: [URLQueryItem]? = nil,
        body: (any Encodable)? = nil,
        requiresAuth: Bool = true,
        isRetryAfterRefresh: Bool = false
    ) async throws -> T {
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

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw APIError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError("Invalid response")
        }

        switch httpResponse.statusCode {
        case 200...299:
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIError.decodingFailed(error.localizedDescription)
            }
        case 401:
            FolioLogger.network.info("401 unauthorized, attempting refresh — \(path)")
            if !isRetryAfterRefresh {
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
            throw APIError.unauthorized
        case 403:
            throw APIError.forbidden
        case 404:
            throw APIError.notFound
        case 409:
            throw APIError.conflict
        case 429:
            throw APIError.quotaExceeded
        default:
            FolioLogger.network.error("HTTP \(httpResponse.statusCode) — \(method) \(path)")
            if httpResponse.statusCode >= 500 {
                throw APIError.serverError(httpResponse.statusCode)
            }
            if let errorResponse = try? decoder.decode(APIErrorResponse.self, from: data) {
                throw APIError.serverMessage(errorResponse.error)
            }
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    // Variant for void responses (DELETE, PUT that return StatusResponse internally)
    private func requestVoid(
        method: String,
        path: String,
        body: (any Encodable)? = nil
    ) async throws {
        let _: StatusResponse = try await request(method: method, path: path, body: body)
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
            try? keychainManager.clearTokens()
            throw APIError.unauthorized
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            FolioLogger.network.error("token refresh: invalid response")
            try? keychainManager.clearTokens()
            throw APIError.unauthorized
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            FolioLogger.network.error("token refresh failed: HTTP \(httpResponse.statusCode)")
            try? keychainManager.clearTokens()
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

    func submitManualContent(content: String, title: String? = nil, tagIds: [String] = [], clientId: String? = nil) async throws -> SubmitArticleResponse {
        var body = SubmitManualContentRequest(content: content)
        body.title = title
        body.tagIds = tagIds.isEmpty ? nil : tagIds
        body.clientId = clientId
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
