import Foundation
import SwiftData

// MARK: - Article ↔ ArticleDTO Mapping

extension Article {
    /// Update local article fields from a server DTO and mark as synced.
    func updateFromDTO(_ dto: ArticleDTO) {
        serverID = dto.id
        url = dto.url
        title = dto.title
        author = dto.author
        siteName = dto.siteName
        faviconURL = dto.faviconUrl
        coverImageURL = dto.coverImageUrl
        if let content = dto.markdownContent {
            markdownContent = content
        }
        summary = dto.summary
        keyPoints = dto.keyPoints ?? []
        aiConfidence = dto.aiConfidence ?? 0
        statusRaw = dto.status
        sourceTypeRaw = dto.sourceType
        fetchError = dto.fetchError
        retryCount = dto.retryCount
        isFavorite = dto.isFavorite
        isArchived = dto.isArchived
        readProgress = max(readProgress, dto.readProgress)
        if let serverDate = dto.lastReadAt {
            if let localDate = lastReadAt {
                lastReadAt = max(localDate, serverDate)
            } else {
                lastReadAt = serverDate
            }
        }
        publishedAt = dto.publishedAt
        wordCount = dto.wordCount
        language = dto.language
        updatedAt = dto.updatedAt
        syncState = .synced
    }

    /// Create a new local Article from a server DTO.
    static func fromDTO(_ dto: ArticleDTO) -> Article {
        let article = Article(
            url: dto.url,
            title: dto.title,
            author: dto.author,
            siteName: dto.siteName,
            sourceType: SourceType(rawValue: dto.sourceType) ?? .web
        )
        article.serverID = dto.id
        article.faviconURL = dto.faviconUrl
        article.coverImageURL = dto.coverImageUrl
        article.markdownContent = dto.markdownContent
        article.summary = dto.summary
        article.keyPoints = dto.keyPoints ?? []
        article.aiConfidence = dto.aiConfidence ?? 0
        article.statusRaw = dto.status
        article.fetchError = dto.fetchError
        article.retryCount = dto.retryCount
        article.isFavorite = dto.isFavorite
        article.isArchived = dto.isArchived
        article.readProgress = dto.readProgress
        article.lastReadAt = dto.lastReadAt
        article.publishedAt = dto.publishedAt
        article.wordCount = dto.wordCount
        article.language = dto.language
        article.createdAt = dto.createdAt
        article.updatedAt = dto.updatedAt
        article.syncState = .synced
        return article
    }
}

// MARK: - Tag ↔ TagDTO Mapping

extension Tag {
    /// Update local tag fields from a server DTO.
    func updateFromDTO(_ dto: TagDTO) {
        serverID = dto.id
        name = dto.name
        isAIGenerated = dto.isAiGenerated
        articleCount = dto.articleCount
    }

    /// Create a new local Tag from a server DTO.
    static func fromDTO(_ dto: TagDTO) -> Tag {
        let tag = Tag(name: dto.name, isAIGenerated: dto.isAiGenerated)
        tag.serverID = dto.id
        tag.articleCount = dto.articleCount
        tag.createdAt = dto.createdAt
        return tag
    }
}

// MARK: - Category ↔ CategoryDTO Mapping

extension Folio.Category {
    /// Update local category fields from a server DTO (matches by slug).
    func updateFromDTO(_ dto: CategoryDTO) {
        serverID = dto.id
        nameZH = dto.nameZh
        nameEN = dto.nameEn
        if let icon = dto.icon {
            self.icon = icon
        }
        sortOrder = dto.sortOrder
    }
}
