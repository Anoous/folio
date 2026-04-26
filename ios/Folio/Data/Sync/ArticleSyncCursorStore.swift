import Foundation

final class ArticleSyncCursorStore {
    private static let lastSyncedAtKey = "com.folio.lastSyncedAt"
    private static let lastEpochKey = "com.folio.lastSyncEpoch"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .appGroup) {
        self.userDefaults = userDefaults
    }

    var lastSyncedAt: Date? {
        get { userDefaults.object(forKey: Self.lastSyncedAtKey) as? Date }
        set {
            if let newValue {
                userDefaults.set(newValue, forKey: Self.lastSyncedAtKey)
            } else {
                userDefaults.removeObject(forKey: Self.lastSyncedAtKey)
            }
        }
    }

    var lastEpoch: Int {
        get { userDefaults.integer(forKey: Self.lastEpochKey) }
        set { userDefaults.set(newValue, forKey: Self.lastEpochKey) }
    }
}
