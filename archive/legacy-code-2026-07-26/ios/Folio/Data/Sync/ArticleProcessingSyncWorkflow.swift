import Foundation
import SwiftData

@MainActor
final class ArticleProcessingSyncWorkflow {
    typealias Sleep = @Sendable (Duration) async throws -> Void

    private let apiClient: APIClient
    private let context: ModelContext
    private let searchIndexCoordinator: SearchIndexCoordinator
    private let pollMaxAttempts: Int
    private let pollInterval: Duration
    private let sleep: Sleep
    private var pollingTasks: [UUID: Task<Void, Never>] = [:]

    init(
        apiClient: APIClient,
        context: ModelContext,
        searchIndexCoordinator: SearchIndexCoordinator? = nil,
        pollMaxAttempts: Int = 10,
        pollInterval: Duration = .seconds(5),
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) }
    ) {
        self.apiClient = apiClient
        self.context = context
        self.searchIndexCoordinator = searchIndexCoordinator ?? .shared
        self.pollMaxAttempts = pollMaxAttempts
        self.pollInterval = pollInterval
        self.sleep = sleep
    }

    func startPolling(taskID: String, articleLocalID: UUID) {
        pollingTasks[articleLocalID]?.cancel()
        pollingTasks[articleLocalID] = Task { [weak self] in
            await self?.pollSubmittedArticle(taskID: taskID, articleLocalID: articleLocalID)
        }
    }

    func cancelPollingTasks() {
        for task in pollingTasks.values {
            task.cancel()
        }
        pollingTasks.removeAll()
    }

    func pollSubmittedArticle(taskID: String, articleLocalID: UUID) async {
        defer {
            pollingTasks.removeValue(forKey: articleLocalID)
        }

        for _ in 0..<pollMaxAttempts {
            do {
                try await sleep(pollInterval)
            } catch is CancellationError {
                FolioLogger.sync.debug("task polling cancelled during sleep: \(taskID)")
                return
            } catch {
                FolioLogger.sync.debug("task polling sleep failed: \(error) — task \(taskID)")
                return
            }

            guard !Task.isCancelled else {
                FolioLogger.sync.debug("task polling cancelled before request: \(taskID)")
                return
            }

            do {
                let task = try await apiClient.getTask(id: taskID)

                switch task.status {
                case AppConstants.TaskStatus.done:
                    FolioLogger.sync.info("task done: \(taskID)")
                    if let articleID = task.articleId {
                        await fetchAndUpdateArticle(serverID: articleID, localID: articleLocalID)
                    }
                    return
                case AppConstants.TaskStatus.failed:
                    FolioLogger.sync.error("task failed: \(taskID) — \(task.errorMessage ?? "unknown")")
                    updateArticleStatus(localID: articleLocalID, status: .failed, error: task.errorMessage)
                    return
                case AppConstants.TaskStatus.queued,
                     AppConstants.TaskStatus.crawling,
                     AppConstants.TaskStatus.aiProcessing:
                    continue
                default:
                    continue
                }
            } catch {
                guard !Task.isCancelled else {
                    FolioLogger.sync.debug("task polling cancelled after request: \(taskID)")
                    return
                }
                FolioLogger.sync.debug("poll network error: \(error) — task \(taskID)")
                continue
            }
        }

        FolioLogger.sync.error("task polling timed out: \(taskID)")
        updateArticleStatus(localID: articleLocalID, status: .failed, error: "Processing timed out")
    }

    func refreshProcessingArticles() async {
        let processingRaw = ArticleStatus.processing.rawValue
        let clientReadyRaw = ArticleStatus.clientReady.rawValue
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> {
                $0.statusRaw == processingRaw || $0.statusRaw == clientReadyRaw
            }
        )
        guard let processing = try? context.fetch(descriptor), !processing.isEmpty else { return }

        FolioLogger.sync.debug("fetching \(processing.count) processing articles")
        let merger = ArticleMerger(context: context)
        for article in processing {
            guard let serverID = article.serverID else { continue }
            do {
                let dto = try await apiClient.getArticle(id: serverID)
                article.updateFromDTO(dto)
                try merger.resolveRelationships(for: article, from: dto)
            } catch {
                continue
            }
        }
        try? context.save()
    }

    private func fetchAndUpdateArticle(serverID: String, localID: UUID) async {
        do {
            let dto = try await apiClient.getArticle(id: serverID)

            let articleRepo = ArticleRepository(context: context)
            guard let article = try articleRepo.fetchByID(localID) else { return }

            article.updateFromDTO(dto)

            let merger = ArticleMerger(context: context)
            try merger.resolveRelationships(for: article, from: dto)

            try context.save()
            searchIndexCoordinator.sync(article)
        } catch {
            FolioLogger.sync.error("fetch article detail failed: \(serverID) — \(error)")
        }
    }

    private func updateArticleStatus(localID: UUID, status: ArticleStatus, error: String?) {
        let articleRepo = ArticleRepository(context: context)
        guard let article = try? articleRepo.fetchByID(localID) else { return }
        article.status = status
        article.fetchError = error
        article.updatedAt = Date()
        try? context.save()
    }
}
