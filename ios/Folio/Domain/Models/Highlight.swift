import Foundation
import SwiftData

@Model
final class Highlight {
    @Attribute(.unique) var id: UUID
    var serverID: String?
    var articleID: UUID
    var text: String
    var startOffset: Int
    var endOffset: Int
    var color: String
    var createdAt: Date
    var isSynced: Bool

    init(id: UUID = UUID(), serverID: String? = nil, articleID: UUID,
         text: String, startOffset: Int, endOffset: Int,
         color: String = "accent", isSynced: Bool = false) {
        self.id = id
        self.serverID = serverID
        self.articleID = articleID
        self.text = text
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.color = color
        self.createdAt = Date()
        self.isSynced = isSynced
    }
}
