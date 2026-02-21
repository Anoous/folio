import Foundation
import SwiftData

@Model
final class Category {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var slug: String
    var nameZH: String
    var nameEN: String
    var icon: String
    var sortOrder: Int
    var articleCount: Int
    var createdAt: Date
    var serverID: String?

    var localizedName: String {
        Locale.current.language.languageCode?.identifier == "zh" ? nameZH : nameEN
    }

    init(slug: String, nameZH: String, nameEN: String, icon: String, sortOrder: Int = 0) {
        self.id = UUID()
        self.slug = slug
        self.nameZH = nameZH
        self.nameEN = nameEN
        self.icon = icon
        self.sortOrder = sortOrder
        self.articleCount = 0
        self.createdAt = Date()
        self.serverID = nil
    }
}
