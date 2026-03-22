import Foundation
import SwiftData

@MainActor
struct ArticleMerger {
    let context: ModelContext

    /// Resolve or create a local Article from a DTO, then apply category + tag resolution.
    /// Returns the article, or nil if the article was deleted (locally or on server).
    @discardableResult
    func merge(dto: ArticleDTO) throws -> Article? {
        let articleRepo = ArticleRepository(context: context)

        // Server says this article is deleted → delete locally + record.
        // Protect genuinely new articles (pendingUpload with no serverID) from deletion.
        // Articles reset by 404 recovery (pendingUpload WITH serverID) can be deleted
        // because the server explicitly marked them as deleted (multi-device delete).
        if dto.deletedAt != nil {
            if let existing = try articleRepo.fetchByServerID(dto.id) {
                let isNewLocalArticle = existing.syncState == .pendingUpload && existing.serverID == nil
                if !isNewLocalArticle {
                    context.delete(existing)
                }
            } else if let url = dto.url, let byURL = try articleRepo.fetchByURL(url) {
                let isNewLocalArticle = byURL.syncState == .pendingUpload && byURL.serverID == nil
                if !isNewLocalArticle {
                    context.delete(byURL)
                }
            }
            recordDeletion(serverID: dto.id)
            return nil
        }

        // Anti-resurrection: skip if we've previously deleted this article locally
        if isDeletedLocally(serverID: dto.id) {
            return nil
        }

        let article: Article

        if let existing = try articleRepo.fetchByServerID(dto.id) {
            existing.updateFromDTO(
                dto,
                preservePendingLocalChanges: existing.syncState == .pendingUpdate
            )
            article = existing
        } else if let url = dto.url, let byURL = try articleRepo.fetchByURL(url) {
            // Don't overwrite genuinely new articles (never uploaded) —
            // just link them to the server record by setting serverID.
            if byURL.syncState == .pendingUpload && byURL.serverID == nil {
                byURL.serverID = dto.id
                byURL.syncState = .synced
                article = byURL
            } else {
                byURL.updateFromDTO(
                    dto,
                    preservePendingLocalChanges: byURL.syncState == .pendingUpdate
                )
                article = byURL
            }
        } else {
            let newArticle = Article.fromDTO(dto)
            context.insert(newArticle)
            article = newArticle
        }

        try resolveRelationships(for: article, from: dto)
        return article
    }

    /// Check if the serverID exists in the DeletionRecord table.
    private func isDeletedLocally(serverID: String) -> Bool {
        let descriptor = FetchDescriptor<DeletionRecord>(
            predicate: #Predicate<DeletionRecord> { $0.serverID == serverID }
        )
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    /// Record a deletion so future syncs don't resurrect this article.
    private func recordDeletion(serverID: String) {
        if !isDeletedLocally(serverID: serverID) {
            context.insert(DeletionRecord(serverID: serverID))
        }
    }

    /// Apply category + tag resolution to an existing article from a DTO.
    func resolveRelationships(for article: Article, from dto: ArticleDTO) throws {
        if let categoryDTO = dto.category {
            let categoryRepo = CategoryRepository(context: context)
            if let localCategory = try categoryRepo.fetchBySlug(categoryDTO.slug) {
                localCategory.updateFromDTO(categoryDTO)
                article.category = localCategory
            }
        }

        if let tagDTOs = dto.tags {
            let tagRepo = TagRepository(context: context)
            var resolvedTags: [Tag] = []
            for tagDTO in tagDTOs {
                if let existing = try tagRepo.fetchByServerID(tagDTO.id) {
                    existing.updateFromDTO(tagDTO)
                    resolvedTags.append(existing)
                } else if let byName = try tagRepo.fetchByName(tagDTO.name) {
                    byName.updateFromDTO(tagDTO)
                    resolvedTags.append(byName)
                } else {
                    let newTag = Tag.fromDTO(tagDTO)
                    context.insert(newTag)
                    resolvedTags.append(newTag)
                }
            }
            article.tags = resolvedTags
        }
    }
}
