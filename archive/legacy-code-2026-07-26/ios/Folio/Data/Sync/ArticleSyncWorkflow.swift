import Foundation
import SwiftData

@MainActor
final class ArticleSyncWorkflow {
    typealias TaskStartedHandler = (_ localID: UUID, _ taskID: String) -> Void

    private static let textOnlySourceTypes: Set<SourceType> = [.manual, .screenshot, .voice]

    private let apiClient: APIClient
    private let context: ModelContext

    init(apiClient: APIClient, context: ModelContext) {
        self.apiClient = apiClient
        self.context = context
    }

    func submitPendingArticles(
        _ articles: [Article],
        onTaskStarted: TaskStartedHandler? = nil
    ) async -> [UUID: Bool] {
        var results: [UUID: Bool] = [:]

        for article in articles {
            do {
                let response = try await submitForProcessing(article)
                applySubmissionSuccess(article, response: response)
                results[article.id] = true
                FolioLogger.sync.info("article submitted: \(article.url ?? article.sourceType.rawValue)")
                onTaskStarted?(article.id, response.taskId)
            } catch ArticleSyncWorkflowError.missingTextContent {
                markSubmissionFailed(article, message: "No content to submit")
                results[article.id] = false
            } catch let error as APIError {
                switch error {
                case .conflict:
                    article.syncState = .synced
                    article.status = .processing
                    results[article.id] = true
                case .quotaExceeded:
                    FolioLogger.sync.info("quota exceeded for article: \(article.url ?? article.sourceType.rawValue)")
                    markSubmissionFailed(article, message: "Monthly quota exceeded")
                    results[article.id] = false
                default:
                    FolioLogger.sync.error("submit failed: \(error) — \(article.url ?? article.sourceType.rawValue)")
                    results[article.id] = false
                }
            } catch {
                FolioLogger.sync.error("submit failed: \(error) — \(article.url ?? article.sourceType.rawValue)")
                results[article.id] = false
            }
        }

        try? context.save()
        return results
    }

    /// Fetch and submit articles that are pending upload to the server.
    func submitLocalPendingArticles(onTaskStarted: TaskStartedHandler? = nil) async -> [UUID: Bool] {
        let pendingRaw = ArticleStatus.pending.rawValue
        let clientReadyRaw = ArticleStatus.clientReady.rawValue
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { $0.statusRaw == pendingRaw || $0.statusRaw == clientReadyRaw },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        guard let pending = try? context.fetch(descriptor), !pending.isEmpty else { return [:] }

        // Clear stale serverIDs from articles that the merger reset for upload after a server 404.
        for article in pending where article.serverID != nil {
            article.serverID = nil
        }

        FolioLogger.sync.info("submitting \(pending.count) local pending article(s)")
        return await submitPendingArticles(pending, onTaskStarted: onTaskStarted)
    }

    func prepareForRetry(_ article: Article) {
        article.status = .pending
        article.fetchError = nil
        article.retryCount += 1
        article.updatedAt = .now
        ModelContext.safeSave(context)
    }

    func submitRetry(_ article: Article) async {
        do {
            let response = try await submitForProcessing(article)
            applySubmissionSuccess(article, response: response)
            article.status = .processing
        } catch ArticleSyncWorkflowError.missingTextContent {
            markSubmissionFailed(article, message: "No content to submit")
        } catch {
            FolioLogger.sync.error("retryArticle failed: \(error) — \(article.url ?? article.sourceType.rawValue)")
            markSubmissionFailed(
                article,
                message: (error as? UserFacingError)?.userMessage ?? error.localizedDescription
            )
        }
        ModelContext.safeSave(context)
    }

    private func submitForProcessing(_ article: Article) async throws -> SubmitArticleResponse {
        if Self.textOnlySourceTypes.contains(article.sourceType) {
            guard let content = article.markdownContent, !content.isEmpty else {
                throw ArticleSyncWorkflowError.missingTextContent
            }
            return try await apiClient.submitManualContent(
                content: content,
                title: article.title,
                clientId: article.id.uuidString,
                sourceType: article.sourceType.rawValue
            )
        }

        if article.extractionSource == .client {
            return try await apiClient.submitArticle(
                url: article.url,
                title: article.title,
                author: article.author,
                siteName: article.siteName,
                markdownContent: article.markdownContent,
                wordCount: article.wordCount > 0 ? article.wordCount : nil
            )
        }

        return try await apiClient.submitArticle(url: article.url)
    }

    private func applySubmissionSuccess(_ article: Article, response: SubmitArticleResponse) {
        article.serverID = response.articleId
        article.dirtyFields = []
        article.syncState = .synced

        if article.isFavorite {
            article.markPendingUpdateIfNeeded(for: .favorite)
        }
        if article.isArchived {
            article.markPendingUpdateIfNeeded(for: .archived)
        }
        if article.readProgress > 0 {
            article.markPendingUpdateIfNeeded(
                for: .readProgress,
                at: article.lastReadAt ?? article.updatedAt
            )
        }
    }

    private func markSubmissionFailed(_ article: Article, message: String) {
        article.status = .failed
        article.fetchError = message
    }
}

private enum ArticleSyncWorkflowError: Error {
    case missingTextContent
}
