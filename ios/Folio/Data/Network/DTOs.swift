// MARK: - DTO Types
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
    case conflict
    case serverError(Int)
    case networkError(String)
    case serverMessage(String)
}

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
    var sourceType: String?

    enum CodingKeys: String, CodingKey {
        case content, title
        case tagIds = "tag_ids"
        case clientId = "client_id"
        case sourceType = "source_type"
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

// MARK: - RAG Streaming DTOs

enum RAGStreamEvent {
    case sources(RAGSourcesPayload)
    case delta(String)
    case done(RAGDonePayload)
    case error(RAGStreamError)
}

struct RAGSourcesPayload: Codable {
    let sources: [RAGSource]
    let sourceCount: Int
    let conversationId: String
}

struct RAGDonePayload: Codable {
    let citedIndices: [Int]
    let followupSuggestions: [String]
}

struct RAGStreamError: Codable {
    let code: String
    let message: String
}

struct RAGThreadEntry {
    let question: String
    let answer: String
    let sources: [RAGSource]
    let sourceCount: Int
    let citedIndices: [Int]
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
