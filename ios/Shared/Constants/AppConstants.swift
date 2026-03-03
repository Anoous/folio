import Foundation

enum AppConstants {
    /// App Group identifier，App 和 Share Extension 共享数据的唯一通道。
    /// 修改此值必须同步更新 Folio.entitlements 和 ShareExtension.entitlements。
    static let appGroupIdentifier = "group.com.folio.app"

    /// Keychain service name
    static let keychainServiceName = "com.folio.app"

    /// Onboarding 完成状态 key（UserDefaults.standard）
    static let onboardingCompletedKey = "hasCompletedOnboarding"
}
