import Foundation
import SwiftData

// MARK: - Article ↔ ArticleDTO Mapping

extension Article {
    /// Update local article fields from a server DTO and mark as synced.
    /// Only overwrites string fields when the server value is non-nil,
    /// preserving client-extracted data if the server hasn't finished processing.
    func updateFromDTO(_ dto: ArticleDTO, preserving dirtyFields: Set<ArticleDirtyField> = []) {
        func maxDate(_ lhs: Date, _ rhs: Date) -> Date {
            max(lhs, rhs)
        }

        let preservedDirtyFields = dirtyFields.isEmpty ? pendingDirtyFields : dirtyFields
        var remainingDirtyFields = preservedDirtyFields
        serverID = dto.id
        url = dto.url
        if let v = dto.title { title = v }
        if let v = dto.author { author = v }
        if let v = dto.siteName { siteName = v }
        if let v = dto.faviconUrl { faviconURL = v }
        if let v = dto.coverImageUrl { coverImageURL = v }
        if let content = dto.markdownContent, !content.isEmpty {
            markdownContent = content
            extractionSource = .server
        }
        if let v = dto.summary { summary = v }
        keyPoints = dto.keyPoints ?? keyPoints
        aiConfidence = dto.aiConfidence ?? aiConfidence
        statusRaw = dto.status
        sourceTypeRaw = dto.sourceType
        fetchError = dto.fetchError
        retryCount = dto.retryCount

        let serverFavoriteUpdatedAt = dto.favoriteUpdatedAt ?? dto.updatedAt
        let localFavoriteUpdatedAt = effectiveFieldUpdatedAt(for: .favorite)
        if !remainingDirtyFields.contains(.favorite) {
            isFavorite = dto.isFavorite
            favoriteUpdatedAt = serverFavoriteUpdatedAt
        } else if dto.isFavorite == isFavorite {
            favoriteUpdatedAt = maxDate(localFavoriteUpdatedAt, serverFavoriteUpdatedAt)
            remainingDirtyFields.remove(.favorite)
        } else if localFavoriteUpdatedAt <= serverFavoriteUpdatedAt {
            isFavorite = dto.isFavorite
            favoriteUpdatedAt = serverFavoriteUpdatedAt
            remainingDirtyFields.remove(.favorite)
        } else {
            favoriteUpdatedAt = localFavoriteUpdatedAt
        }

        let serverArchivedUpdatedAt = dto.archivedUpdatedAt ?? dto.updatedAt
        let localArchivedUpdatedAt = effectiveFieldUpdatedAt(for: .archived)
        if !remainingDirtyFields.contains(.archived) {
            isArchived = dto.isArchived
            archivedUpdatedAt = serverArchivedUpdatedAt
        } else if dto.isArchived == isArchived {
            archivedUpdatedAt = maxDate(localArchivedUpdatedAt, serverArchivedUpdatedAt)
            remainingDirtyFields.remove(.archived)
        } else if localArchivedUpdatedAt <= serverArchivedUpdatedAt {
            isArchived = dto.isArchived
            archivedUpdatedAt = serverArchivedUpdatedAt
            remainingDirtyFields.remove(.archived)
        } else {
            archivedUpdatedAt = localArchivedUpdatedAt
        }

        let localReadProgress = readProgress
        let localReadProgressUpdatedAt = effectiveFieldUpdatedAt(for: .readProgress)
        let serverReadProgressUpdatedAt = dto.readProgressUpdatedAt ?? dto.lastReadAt ?? dto.updatedAt
        readProgress = max(localReadProgress, dto.readProgress)
        readProgressUpdatedAt = maxDate(localReadProgressUpdatedAt, serverReadProgressUpdatedAt)
        if let serverDate = dto.lastReadAt {
            lastReadAt = lastReadAt.map { max($0, serverDate) } ?? serverDate
        }
        if !remainingDirtyFields.contains(.readProgress) || dto.readProgress >= localReadProgress || dto.readProgress == localReadProgress {
            remainingDirtyFields.remove(.readProgress)
        }
        self.dirtyFields = remainingDirtyFields
        syncState = remainingDirtyFields.isEmpty ? .synced : .pendingUpdate
        if let v = dto.publishedAt { publishedAt = v }
        if dto.wordCount > 0 { wordCount = dto.wordCount }
        if let v = dto.language { language = v }
        updatedAt = dto.updatedAt
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
        article.favoriteUpdatedAt = dto.favoriteUpdatedAt ?? dto.updatedAt
        article.archivedUpdatedAt = dto.archivedUpdatedAt ?? dto.updatedAt
        article.readProgressUpdatedAt = dto.readProgressUpdatedAt ?? dto.lastReadAt ?? dto.updatedAt
        article.lastReadAt = dto.lastReadAt
        article.publishedAt = dto.publishedAt
        article.wordCount = dto.wordCount
        article.language = dto.language
        article.createdAt = dto.createdAt
        article.updatedAt = dto.updatedAt
        article.syncState = .synced
        article.dirtyFields = []
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
