// MARK: - Network Layer
import Foundation

// MARK: - APIError

enum APIError: Error, Equatable {
    case invalidURL
    case encodingFailed
    case decodingFailed(String)
    case unauthorized
    case forbidden
    case notFound
    case quotaExceeded
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
}

// MARK: Articles

struct SubmitArticleRequest: Encodable {
    let url: String
    let tagIds: [String]?
}

struct SubmitArticleResponse: Decodable {
    let articleId: String
    let taskId: String
}

struct ArticleDTO: Decodable {
    let id: String
    let url: String
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
    let url: String
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
}

// MARK: - APIClient

final class APIClient {
    static let shared = APIClient()

    private let baseURL: URL
    private let session: URLSession
    private let keychainManager: KeyChainManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let refreshCoordinator = RefreshCoordinator()

    #if DEBUG
    static let defaultBaseURL = URL(string: "http://localhost:8080")!
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

            let iso8601 = ISO8601DateFormatter()
            iso8601.formatOptions = [.withInternetDateTime]
            if let date = iso8601.date(from: string) {
                return date
            }

            let iso8601Fractional = ISO8601DateFormatter()
            iso8601Fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso8601Fractional.date(from: string) {
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
        case 429:
            throw APIError.quotaExceeded
        default:
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

        guard let url = URL(string: "\(baseURL)/api/v1/auth/refresh") else {
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
            try? keychainManager.clearTokens()
            throw APIError.unauthorized
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            try? keychainManager.clearTokens()
            throw APIError.unauthorized
        }

        let authResponse = try decoder.decode(AuthResponse.self, from: data)
        try keychainManager.saveTokens(access: authResponse.accessToken, refresh: authResponse.refreshToken)
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

    func loginDev() async throws -> AuthResponse {
        let response: AuthResponse = try await request(
            method: "POST",
            path: "/api/v1/auth/dev",
            requiresAuth: false
        )
        try keychainManager.saveTokens(access: response.accessToken, refresh: response.refreshToken)
        return response
    }

    // MARK: - Articles

    func submitArticle(url: String, tagIds: [String] = []) async throws -> SubmitArticleResponse {
        let body = SubmitArticleRequest(url: url, tagIds: tagIds.isEmpty ? nil : tagIds)
        return try await request(method: "POST", path: "/api/v1/articles", body: body)
    }

    func listArticles(
        page: Int = 1,
        perPage: Int = 20,
        category: String? = nil,
        status: String? = nil,
        favorite: Bool? = nil
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
