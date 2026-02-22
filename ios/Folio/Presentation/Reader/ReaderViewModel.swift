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
    var isLoadingContent: Bool = false
    var contentLoadError: String?

    /// Characters per minute for reading time estimation.
    private static let charsPerMinute: Double = 400

    // MARK: - Initialization

    init(article: Article, context: ModelContext, isAuthenticated: Bool = false, apiClient: APIClient = .shared) {
        self.article = article
        self.context = context
        self.isAuthenticated = isAuthenticated
        self.apiClient = apiClient
        calculateWordCount()
    }

    // MARK: - Word Count & Reading Time

    private func calculateWordCount() {
        let content = article.markdownContent ?? ""
        wordCount = content.count
        estimatedReadTimeMinutes = max(1, Int(ceil(Double(wordCount) / Self.charsPerMinute)))
    }

    // MARK: - Fetch Content from Server

    /// If the article has a serverID but no local content, fetch the full detail.
    func fetchContentIfNeeded() async {
        guard article.markdownContent == nil,
              isAuthenticated,
              let serverID = article.serverID else { return }

        isLoadingContent = true
        contentLoadError = nil

        do {
            let dto = try await apiClient.getArticle(id: serverID)
            article.updateFromDTO(dto)
            try? context.save()
            calculateWordCount()
        } catch {
            contentLoadError = error.localizedDescription
        }

        isLoadingContent = false
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

    // MARK: - Reading Progress (local only)

    func updateReadingProgress(_ progress: Double) {
        let clamped = min(max(progress, 0.0), 1.0)
        guard clamped >= readingProgress else { return }
        readingProgress = clamped
        article.readProgress = clamped
        article.lastReadAt = Date()
        try? context.save()
    }

    // MARK: - Favorite

    func toggleFavorite() {
        let previousValue = article.isFavorite
        article.isFavorite.toggle()
        article.updatedAt = Date()
        try? context.save()

        if article.isFavorite {
            showToastMessage(String(localized: "home.article.favorited", defaultValue: "Added to favorites"), icon: "heart.fill")
        } else {
            showToastMessage(String(localized: "home.article.unfavorited", defaultValue: "Removed from favorites"), icon: "heart")
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
                    article.isFavorite = previousValue
                    article.syncState = .pendingUpdate
                    try? context.save()
                    showToastMessage(String(localized: "home.article.syncFailed", defaultValue: "Sync failed, will retry"), icon: "exclamationmark.icloud")
                }
            }
        }
    }

    // MARK: - Archive

    func archiveArticle() {
        let previousValue = article.isArchived
        article.isArchived.toggle()
        article.updatedAt = Date()
        try? context.save()

        if article.isArchived {
            showToastMessage(String(localized: "home.article.archived", defaultValue: "Archived"), icon: "archivebox.fill")
        } else {
            showToastMessage(String(localized: "home.article.unarchived", defaultValue: "Unarchived"), icon: "archivebox")
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
                    article.isArchived = previousValue
                    article.syncState = .pendingUpdate
                    try? context.save()
                    showToastMessage(String(localized: "home.article.syncFailed", defaultValue: "Sync failed, will retry"), icon: "exclamationmark.icloud")
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
            showToastMessage(String(localized: "reader.noContentToCopy", defaultValue: "No content to copy"), icon: "exclamationmark.triangle")
            return
        }

        UIPasteboard.general.string = content
        showToastMessage(String(localized: "reader.markdownCopied", defaultValue: "Markdown copied"), icon: "doc.on.doc")
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
