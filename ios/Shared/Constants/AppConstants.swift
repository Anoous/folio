import Foundation

enum AppConstants {
    /// App Group identifier，App 和 Share Extension 共享数据的唯一通道。
    /// 修改此值必须同步更新 Folio.entitlements 和 ShareExtension.entitlements。
    static let appGroupIdentifier = "group.com.7WSH9CR7KS.folio.app"

    /// Keychain service name
    static let keychainServiceName = "com.folio.app"

    /// Onboarding 完成状态 key（UserDefaults.standard）
    static let onboardingCompletedKey = "hasCompletedOnboarding"

    /// Share Extension 写入新文章后置 true，主 App 前台恢复时检查并刷新。
    static let shareExtensionDidSaveKey = "shareExtensionDidSave"
}
