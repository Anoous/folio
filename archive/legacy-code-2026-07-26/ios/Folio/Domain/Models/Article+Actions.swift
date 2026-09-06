import Foundation
import SwiftData

extension Article {
    func markPendingUpdateIfNeeded(for field: ArticleDirtyField, at timestamp: Date = .now) {
        guard serverID != nil else { return }
        guard syncState != .pendingUpload else { return }

        var fields = dirtyFields
        fields.insert(field)
        dirtyFields = fields
        setFieldUpdatedAt(timestamp, for: field)
        syncState = .pendingUpdate
        updatedAt = timestamp
    }

    func clearPendingUpdateIfNeeded(for field: ArticleDirtyField) {
        var fields = dirtyFields
        fields.remove(field)
        dirtyFields = fields

        guard syncState != .pendingUpload else { return }
        syncState = fields.isEmpty ? .synced : .pendingUpdate
    }

    /// Marks this article as having local changes that still need server sync.
    func markAsRead(in context: ModelContext) {
        if readProgress == 0 { readProgress = 0.01 }
        lastReadAt = Date()
        markPendingUpdateIfNeeded(for: .readProgress)
        ModelContext.safeSave(context)
    }

}
