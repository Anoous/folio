import os
import SwiftData

enum FolioLogger {
    private static let subsystem = AppConstants.bundleIdentifier

    static let network = Logger(subsystem: subsystem, category: "network")
    static let sync = Logger(subsystem: subsystem, category: "sync")
    static let data = Logger(subsystem: subsystem, category: "data")
    static let auth = Logger(subsystem: subsystem, category: "auth")
}

// MARK: - ModelContext Safe Save

extension ModelContext {
    /// Save the context, logging any errors instead of silently discarding them.
    /// Use this instead of `try? context.save()` so failures are visible in logs.
    @discardableResult
    static func safeSave(_ context: ModelContext, file: String = #fileID, line: Int = #line) -> Bool {
        do {
            try context.save()
            return true
        } catch {
            FolioLogger.data.error("context.save() failed at \(file):\(line) — \(error)")
            return false
        }
    }
}
