import Foundation
import SwiftData

/// Tracks article deletions that haven't been synced to the server yet.
/// Written when user deletes an article while offline; consumed when network becomes available.
@Model
final class PendingDeletion {
    var serverID: String
    var deletedAt: Date

    init(serverID: String, deletedAt: Date = Date()) {
        self.serverID = serverID
        self.deletedAt = deletedAt
    }
}
