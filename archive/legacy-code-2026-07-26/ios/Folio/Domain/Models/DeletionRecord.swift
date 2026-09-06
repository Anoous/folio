import Foundation
import SwiftData

/// Anti-resurrection record: prevents fullSync from re-creating articles the user has deleted.
/// Kept for 60 days, then automatically cleaned up.
@Model
final class DeletionRecord {
    @Attribute(.unique) var serverID: String
    var deletedAt: Date

    init(serverID: String, deletedAt: Date = Date()) {
        self.serverID = serverID
        self.deletedAt = deletedAt
    }

    static let retentionDays = 60
}
