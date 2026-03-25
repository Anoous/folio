import Foundation

enum AppConstants {
    /// App Group identifier，App 和 Share Extension 共享数据的唯一通道。
    /// 修改此值必须同步更新 Folio.entitlements 和 ShareExtension.entitlements。
    static let appGroupIdentifier = "group.com.7WSH9CR7KS.folio.app"

    /// Bundle identifier, used for Keychain service name, logger subsystem, etc.
    static let bundleIdentifier = "com.folio.app"

    /// Keychain service name
    static let keychainServiceName = bundleIdentifier

    /// Onboarding 完成状态 key（UserDefaults.standard）
    static let onboardingCompletedKey = "hasCompletedOnboarding"

    /// Share Extension 写入新文章后置 true，主 App 前台恢复时检查并刷新。
    static let shareExtensionDidSaveKey = "shareExtensionDidSave"

    /// Search history key (UserDefaults.standard)
    static let searchHistoryKey = "folio_search_history"

    /// Key for tracking if the user has been prompted for push notifications.
    static let hasRequestedNotificationsKey = "has_requested_notifications"

    /// Key for storing dismissed milestone IDs (comma-separated).
    static let dismissedMilestonesKey = "dismissed_milestones"

    // MARK: - Subscription

    /// StoreKit product identifiers.
    static let proYearlyProductID = "com.folio.app.pro.yearly"
    static let proMonthlyProductID = "com.folio.app.pro.monthly"

    /// Free tier subscription identifier (matches server domain.SubscriptionFree).
    static let subscriptionFree = "free"

    /// Pro tier subscription identifier (matches server domain.SubscriptionPro).
    static let subscriptionPro = "pro"

    /// Legacy pro_plus tier — treated as "pro" on the client side.
    static let subscriptionProPlus = "pro_plus"

    // MARK: - Task Status

    /// Server task status values (matches server domain.TaskStatus* constants).
    enum TaskStatus {
        static let done = "done"
        static let failed = "failed"
        static let queued = "queued"
        static let crawling = "crawling"
        static let aiProcessing = "ai_processing"
    }
}
