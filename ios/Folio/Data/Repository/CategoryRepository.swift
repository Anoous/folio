import Foundation
import SwiftData

final class CategoryRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// Fetch all categories
    func fetchAll() throws -> [Folio.Category] {
        let descriptor = FetchDescriptor<Folio.Category>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        return try context.fetch(descriptor)
    }

    /// Fetch category by slug
    func fetchBySlug(_ slug: String) throws -> Folio.Category? {
        let descriptor = FetchDescriptor<Folio.Category>(
            predicate: #Predicate { $0.slug == slug }
        )
        return try context.fetch(descriptor).first
    }

    /// Fetch category by server ID
    func fetchByServerID(_ serverID: String) throws -> Folio.Category? {
        let descriptor = FetchDescriptor<Folio.Category>(
            predicate: #Predicate { $0.serverID == serverID }
        )
        return try context.fetch(descriptor).first
    }
}
