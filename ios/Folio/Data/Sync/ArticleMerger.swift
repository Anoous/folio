import Foundation
import SwiftData

@MainActor
struct ArticleMerger {
    let context: ModelContext

    /// Resolve or create a local Article from a DTO, then apply category + tag resolution.
    /// Returns the article and whether it was newly created.
    @discardableResult
    func merge(dto: ArticleDTO) throws -> Article {
        let articleRepo = ArticleRepository(context: context)
        let article: Article

        if let existing = try articleRepo.fetchByServerID(dto.id) {
            existing.updateFromDTO(dto)
            article = existing
        } else if let byURL = try articleRepo.fetchByURL(dto.url) {
            byURL.updateFromDTO(dto)
            article = byURL
        } else {
            let newArticle = Article.fromDTO(dto)
            context.insert(newArticle)
            article = newArticle
        }

        try resolveRelationships(for: article, from: dto)
        return article
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
