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
    var highlights: [HighlightDTO] = []

    /// Words per minute for reading time estimation.
    private static let wordsPerMinute: Double = 250

    /// Minimum progress change (1%) before persisting to disk.
    private static let progressPersistThreshold: Double = 0.01
    /// Last progress value that was actually persisted to disk.
    private var lastPersistedProgress: Double = 0.0

    // MARK: - Initialization

    init(article: Article, context: ModelContext, isAuthenticated: Bool = false, apiClient: APIClient = .shared) {
        self.article = article
        self.context = context
        self.isAuthenticated = isAuthenticated
        self.apiClient = apiClient
        self.readingProgress = article.readProgress
        self.lastPersistedProgress = article.readProgress
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

    /// If the article has no local content, try server first, then fall back to client extraction.
    func fetchContentIfNeeded() async {
        guard article.markdownContent == nil else { return }

        isLoadingContent = true
        contentLoadError = nil

        // Try server fetch first
        if isAuthenticated, let serverID = article.serverID {
            do {
                let dto = try await apiClient.getArticle(id: serverID)
                article.updateFromDTO(dto)
                ModelContext.safeSave(context)
                calculateWordCount()
                FolioLogger.network.info("reader: content fetched from server for \(serverID)")
                isLoadingContent = false
                return
            } catch {
                FolioLogger.network.error("reader: server fetch failed — \(serverID) — \(error)")
            }
        }

        // Fall back to client-side extraction
        if let urlString = article.url, let url = URL(string: urlString) {
            do {
                let result = try await ContentExtractor().extract(url: url)
                article.markdownContent = result.markdownContent
                article.wordCount = result.wordCount
                if let t = result.title, article.title == nil { article.title = t }
                if let a = result.author { article.author = a }
                if let s = result.siteName { article.siteName = s }
                if let e = result.excerpt, article.summary == nil { article.summary = e }
                article.extractionSource = .client
                article.clientExtractedAt = Date()
                article.status = .clientReady
                ModelContext.safeSave(context)
                calculateWordCount()
                FolioLogger.data.info("reader: client extraction succeeded for \(url.absoluteString)")
                isLoadingContent = false
                return
            } catch {
                FolioLogger.data.error("reader: client extraction failed — \(error)")
                contentLoadError = error.localizedDescription
            }
        } else if article.sourceType == .manual {
            contentLoadError = String(localized: "reader.noContent", defaultValue: "Content not available")
        } else {
            contentLoadError = String(localized: "reader.invalidURL", defaultValue: "Invalid URL")
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

        // Only persist to disk when the progress changed by at least 1%
        // or reached 100%, to avoid writing on every scroll frame.
        let delta = clamped - lastPersistedProgress
        if delta >= Self.progressPersistThreshold || clamped >= 1.0 {
            article.markPendingUpdateIfNeeded()
            ModelContext.safeSave(context)
            lastPersistedProgress = clamped
        }
    }

    /// Flush any un-persisted progress (e.g., on view disappear).
    func persistProgressIfNeeded() {
        guard readingProgress > lastPersistedProgress else { return }
        article.markPendingUpdateIfNeeded()
        ModelContext.safeSave(context)
        lastPersistedProgress = readingProgress
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
        ModelContext.safeSave(context)

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
        article.url.flatMap { URL(string: $0) }
    }

    // MARK: - Toast

    func showToastMessage(_ message: String, icon: String? = nil) {
        toastMessage = message
        toastIcon = icon
        showToast = true
    }

    // MARK: - Highlights

    func fetchHighlights() async {
        guard let serverID = article.serverID else { return }
        do {
            let response = try await apiClient.getHighlights(articleID: serverID)
            highlights = response.data
        } catch {
            // Silent failure — highlights are non-critical
        }
    }

    func createHighlight(text: String, startOffset: Int, endOffset: Int) {
        guard let serverID = article.serverID else { return }
        Task {
            do {
                let dto = try await apiClient.createHighlight(
                    articleID: serverID, text: text,
                    startOffset: startOffset, endOffset: endOffset
                )
                await MainActor.run {
                    highlights.append(dto)
                }
            } catch {
                await MainActor.run {
                    showToastMessage(
                        String(localized: "highlight.saveFailed", defaultValue: "高亮保存失败"),
                        icon: "exclamationmark.triangle.fill"
                    )
                }
            }
        }
    }

    func deleteHighlight(id: String) {
        highlights.removeAll { $0.id == id }
        Task {
            do {
                try await apiClient.deleteHighlight(id: id)
            } catch {
                // Silent — already removed from UI
            }
        }
    }
}
