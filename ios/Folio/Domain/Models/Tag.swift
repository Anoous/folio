import Foundation
import SwiftData

@Model
final class Tag {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var name: String
    var isAIGenerated: Bool
    var articleCount: Int
    var articles: [Article]
    var createdAt: Date
    var serverID: String?

    init(name: String, isAIGenerated: Bool = false) {
        self.id = UUID()
        self.name = name
        self.isAIGenerated = isAIGenerated
        self.articleCount = 0
        self.articles = []
        self.createdAt = Date()
        self.serverID = nil
    }
}
