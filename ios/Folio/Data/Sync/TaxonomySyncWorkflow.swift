import Foundation
import SwiftData

@MainActor
final class TaxonomySyncWorkflow {
    private let apiClient: APIClient
    private let context: ModelContext

    init(apiClient: APIClient, context: ModelContext) {
        self.apiClient = apiClient
        self.context = context
    }

    func syncCategories() async {
        do {
            let response = try await apiClient.listCategories()
            let categoryRepo = CategoryRepository(context: context)

            for dto in response.data {
                if let existing = try categoryRepo.fetchBySlug(dto.slug) {
                    existing.updateFromDTO(dto)
                } else if let byServerID = try categoryRepo.fetchByServerID(dto.id) {
                    byServerID.updateFromDTO(dto)
                }
            }

            try context.save()
        } catch {
            FolioLogger.sync.error("category sync failed: \(error)")
        }
    }

    func syncTags() async {
        do {
            let response = try await apiClient.listTags()
            let tagRepo = TagRepository(context: context)

            for dto in response.data {
                if let existing = try tagRepo.fetchByServerID(dto.id) {
                    existing.updateFromDTO(dto)
                } else if let byName = try tagRepo.fetchByName(dto.name) {
                    byName.updateFromDTO(dto)
                } else {
                    let newTag = Tag.fromDTO(dto)
                    context.insert(newTag)
                }
            }

            try context.save()
        } catch {
            FolioLogger.sync.error("tag sync failed: \(error)")
        }
    }
}
