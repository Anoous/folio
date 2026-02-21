import Foundation
import SwiftData

final class TagRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// Fetch all tags
    func fetchAll(sortBy: SortOrder = .forward) throws -> [Tag] {
        let descriptor = FetchDescriptor<Tag>(
            sortBy: [SortDescriptor(\.name, order: sortBy)]
        )
        return try context.fetch(descriptor)
    }

    /// Fetch popular tags ordered by article count
    func fetchPopular(limit: Int = 10) throws -> [Tag] {
        var descriptor = FetchDescriptor<Tag>(
            sortBy: [SortDescriptor(\.articleCount, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    /// Find existing tag by name or create a new one
    @discardableResult
    func findOrCreate(name: String, isAIGenerated: Bool = false) throws -> Tag {
        let descriptor = FetchDescriptor<Tag>(
            predicate: #Predicate { $0.name == name }
        )
        if let existing = try context.fetch(descriptor).first {
            return existing
        }

        let tag = Tag(name: name, isAIGenerated: isAIGenerated)
        context.insert(tag)
        try context.save()
        return tag
    }

    /// Fetch tag by server ID
    func fetchByServerID(_ serverID: String) throws -> Tag? {
        let descriptor = FetchDescriptor<Tag>(
            predicate: #Predicate { $0.serverID == serverID }
        )
        return try context.fetch(descriptor).first
    }

    /// Fetch tag by name
    func fetchByName(_ name: String) throws -> Tag? {
        let descriptor = FetchDescriptor<Tag>(
            predicate: #Predicate { $0.name == name }
        )
        return try context.fetch(descriptor).first
    }

    /// Delete a tag
    func delete(_ tag: Tag) throws {
        context.delete(tag)
        try context.save()
    }
}
