import Foundation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class ReaderViewModel {
    // MARK: - Properties

    private(set) var article: Article
    private let context: ModelContext
    private let apiClient: APIClient
    private let isAuthenticated: Bool

    var wordCount: Int = 0
    var estimatedReadTimeMinutes: Int = 0
    var readingProgress: Double = 0.0
    var showToast: Bool = false
    var toastMessage: String = ""
    var toastIcon: String? = nil

    private var progressSyncTask: Task<Void, Never>?

    /// Characters per minute for reading time estimation.
    private static let charsPerMinute: Double = 400

    // MARK: - Initialization

    init(article: Article, context: ModelContext, isAuthenticated: Bool = false, apiClient: APIClient = .shared) {
        self.article = article
        self.context = context
        self.isAuthenticated = isAuthenticated
        self.apiClient = apiClient
        calculateWordCount()
        loadReadingProgress()
    }

    // MARK: - Word Count & Reading Time

    private func calculateWordCount() {
        let content = article.markdownContent ?? ""
        wordCount = content.count
        estimatedReadTimeMinutes = max(1, Int(ceil(Double(wordCount) / Self.charsPerMinute)))
    }

    // MARK: - Mark as Read

    func markAsRead() {
        if article.readProgress == 0 {
            article.readProgress = 0.01
        }
        article.lastReadAt = Date()
        article.updatedAt = Date()
        try? context.save()
    }

    // MARK: - Reading Progress

    func updateReadingProgress(_ progress: Double) {
        let clamped = min(max(progress, 0.0), 1.0)
        readingProgress = clamped
        article.readProgress = clamped
        article.lastReadAt = Date()
        article.updatedAt = Date()
        try? context.save()

        // Debounced server sync (5 seconds)
        progressSyncTask?.cancel()
        progressSyncTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled, isAuthenticated, let serverID = article.serverID else { return }
            try? await apiClient.updateArticle(
                id: serverID,
                request: UpdateArticleRequest(readProgress: clamped)
            )
        }
    }

    private func loadReadingProgress() {
        readingProgress = article.readProgress
    }

    // MARK: - Favorite

    func toggleFavorite() {
        article.isFavorite.toggle()
        article.updatedAt = Date()
        try? context.save()

        if article.isFavorite {
            showToastMessage("Added to favorites", icon: "heart.fill")
        } else {
            showToastMessage("Removed from favorites", icon: "heart")
        }

        if isAuthenticated, let serverID = article.serverID {
            Task {
                do {
                    try await apiClient.updateArticle(
                        id: serverID,
                        request: UpdateArticleRequest(isFavorite: article.isFavorite)
                    )
                    article.syncState = .synced
                } catch {
                    article.syncState = .pendingUpdate
                }
            }
        }
    }

    // MARK: - Archive

    func archiveArticle() {
        article.isArchived.toggle()
        article.updatedAt = Date()
        try? context.save()

        if article.isArchived {
            showToastMessage("Archived", icon: "archivebox.fill")
        } else {
            showToastMessage("Unarchived", icon: "archivebox")
        }

        if isAuthenticated, let serverID = article.serverID {
            Task {
                do {
                    try await apiClient.updateArticle(
                        id: serverID,
                        request: UpdateArticleRequest(isArchived: article.isArchived)
                    )
                    article.syncState = .synced
                } catch {
                    article.syncState = .pendingUpdate
                }
            }
        }
    }

    // MARK: - Delete

    func deleteArticle() {
        let serverID = article.serverID

        context.delete(article)
        try? context.save()

        if isAuthenticated, let serverID {
            Task { try? await apiClient.deleteArticle(id: serverID) }
        }
    }

    // MARK: - Copy Markdown

    func copyMarkdown() {
        guard let content = article.markdownContent else {
            showToastMessage("No content to copy", icon: "exclamationmark.triangle")
            return
        }

        UIPasteboard.general.string = content
        showToastMessage("Markdown copied", icon: "doc.on.doc")
    }

    // MARK: - Share

    func shareURL() -> URL? {
        URL(string: article.url)
    }

    // MARK: - Toast

    private func showToastMessage(_ message: String, icon: String? = nil) {
        toastMessage = message
        toastIcon = icon
        showToast = true
    }
}
