import Foundation

struct HomeQuotaSnapshot: Equatable {
    let isAuthenticated: Bool
    let isPro: Bool
    let used: Int
    let monthlyQuota: Int

    var effectiveQuota: Int {
        monthlyQuota > 0 ? monthlyQuota : SharedDataManager.freeMonthlyQuota
    }

    var remaining: Int {
        max(effectiveQuota - used, 0)
    }

    var progress: Double {
        guard effectiveQuota > 0 else { return 0 }
        return min(Double(used) / Double(effectiveQuota), 1)
    }

    var state: HomeQuotaState {
        if !isAuthenticated {
            return .signedOut
        }
        if isPro {
            return .pro
        }
        if used >= effectiveQuota {
            return .exceeded
        }
        if progress >= 0.8 {
            return .warning
        }
        return .available
    }

    init(isAuthenticated: Bool, isPro: Bool, used: Int, monthlyQuota: Int) {
        self.isAuthenticated = isAuthenticated
        self.isPro = isPro
        self.used = max(used, 0)
        self.monthlyQuota = monthlyQuota
    }

    init(user: UserDTO?, isAuthenticated: Bool, userDefaults: UserDefaults = .appGroup) {
        let storedQuota = userDefaults.integer(forKey: SharedDataManager.monthlyQuotaKey)
        let quota = user?.monthlyQuota ?? (storedQuota > 0 ? storedQuota : SharedDataManager.freeMonthlyQuota)
        let count = user?.currentMonthCount ?? SharedDataManager.currentMonthCount(userDefaults: userDefaults)
        let pro = user?.isPro ?? userDefaults.bool(forKey: SharedDataManager.isProUserKey)

        self.init(
            isAuthenticated: isAuthenticated,
            isPro: pro,
            used: count,
            monthlyQuota: quota
        )
    }
}
