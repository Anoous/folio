import Foundation
import os
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

    /// Words per minute for reading time estimation.
    private static let wordsPerMinute: Double = 250

    // MARK: - Initialization

    init(article: Article, context: ModelContext, isAuthenticated: Bool = false, apiClient: APIClient = .shared) {
        self.article = article
        self.context = context
        self.isAuthenticated = isAuthenticated
        self.apiClient = apiClient
        self.readingProgress = article.readProgress
        calculateWordCount()
    }

    // MARK: - Word Count & Reading Time

    private func calculateWordCount() {
        if article.wordCount > 0 {
            wordCount = article.wordCount
        } else {
            let content = article.markdownContent ?? ""
            // Count words: split by whitespace for mixed English/CJK text
            let components = content.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            wordCount = components.count
        }
        estimatedReadTimeMinutes = max(1, Int(ceil(Double(wordCount) / Self.wordsPerMinute)))
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
            FolioLogger.network.info("reader: content fetched for \(serverID)")
        } catch {
            FolioLogger.network.error("reader: fetch content failed — \(serverID) — \(error)")
            contentLoadError = error.localizedDescription
        }

        isLoadingContent = false
    }

    // MARK: - Mark as Read

    func markAsRead() {
        article.markAsRead(in: context)
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
        article.toggleFavoriteWithSync(
            context: context, apiClient: apiClient,
            isAuthenticated: isAuthenticated, showToast: showToastMessage
        )
    }

    // MARK: - Archive

    func archiveArticle() {
        article.toggleArchiveWithSync(
            context: context, apiClient: apiClient,
            isAuthenticated: isAuthenticated, showToast: showToastMessage
        )
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
