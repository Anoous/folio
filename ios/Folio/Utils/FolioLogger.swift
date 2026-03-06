import os

enum FolioLogger {
    static let network = Logger(subsystem: "com.folio.app", category: "network")
    static let sync = Logger(subsystem: "com.folio.app", category: "sync")
    static let data = Logger(subsystem: "com.folio.app", category: "data")
    static let auth = Logger(subsystem: "com.folio.app", category: "auth")
}
