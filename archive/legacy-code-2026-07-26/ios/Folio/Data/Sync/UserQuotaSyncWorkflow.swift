import Foundation

@MainActor
final class UserQuotaSyncWorkflow {
    typealias QuotaWriter = @MainActor (_ monthlyQuota: Int, _ currentMonthCount: Int, _ isPro: Bool) -> Void
    typealias EpochChecker = @MainActor (_ epoch: Int) -> Void

    private let apiClient: APIClient
    private let quotaWriter: QuotaWriter
    private let epochChecker: EpochChecker

    init(
        apiClient: APIClient,
        quotaWriter: @escaping QuotaWriter = { monthlyQuota, currentMonthCount, isPro in
            SharedDataManager.syncQuotaFromServer(
                monthlyQuota: monthlyQuota,
                currentMonthCount: currentMonthCount,
                isPro: isPro
            )
        },
        epochChecker: @escaping EpochChecker = { _ in }
    ) {
        self.apiClient = apiClient
        self.quotaWriter = quotaWriter
        self.epochChecker = epochChecker
    }

    func syncUserQuota() async {
        do {
            let response = try await apiClient.refreshAuth()
            let user = response.user
            let isPro = user.subscription != AppConstants.subscriptionFree
            quotaWriter(user.monthlyQuota, user.currentMonthCount, isPro)

            if let epoch = user.syncEpoch {
                epochChecker(epoch)
            }
        } catch {
            FolioLogger.sync.error("quota sync failed: \(error)")
        }
    }
}
