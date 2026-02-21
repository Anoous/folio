import Foundation
import SwiftData

final class DataManager {
    static let shared = DataManager()

    private init() {}

    /// All SwiftData model types
    static let modelTypes: [any PersistentModel.Type] = [
        Article.self,
        Tag.self,
        Category.self,
    ]

    static let schema = Schema(modelTypes)

    /// Create a shared ModelContainer using App Group for main app and Share Extension
    @MainActor
    func createSharedContainer() throws -> ModelContainer {
        let config = ModelConfiguration(
            "Folio",
            schema: Self.schema,
            groupContainer: .identifier("group.com.folio.app")
        )
        let container = try ModelContainer(for: Self.schema, configurations: [config])
        preloadCategories(in: container.mainContext)
        return container
    }

    /// Create an in-memory ModelContainer for previews and testing
    @MainActor
    static func createInMemoryContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        shared.preloadCategories(in: container.mainContext)
        return container
    }

    // MARK: - Default Categories

    static let defaultCategories: [(slug: String, nameZH: String, nameEN: String, icon: String)] = [
        ("tech", "技术", "Technology", "cpu"),
        ("business", "商业", "Business", "chart.bar"),
        ("science", "科学", "Science", "atom"),
        ("culture", "文化", "Culture", "book"),
        ("lifestyle", "生活", "Lifestyle", "heart"),
        ("news", "时事", "News", "newspaper"),
        ("education", "学习", "Education", "graduationcap"),
        ("design", "设计", "Design", "paintbrush"),
        ("other", "其他", "Other", "ellipsis.circle"),
    ]

    func preloadCategories(in context: ModelContext) {
        let descriptor = FetchDescriptor<Category>()
        let existingCount = (try? context.fetchCount(descriptor)) ?? 0
        guard existingCount == 0 else { return }

        for (index, cat) in Self.defaultCategories.enumerated() {
            let category = Category(slug: cat.slug, nameZH: cat.nameZH, nameEN: cat.nameEN, icon: cat.icon, sortOrder: index)
            context.insert(category)
        }

        try? context.save()
    }
}
