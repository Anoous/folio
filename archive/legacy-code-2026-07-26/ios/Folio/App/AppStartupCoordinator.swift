import Foundation

@MainActor
struct AppStartupCoordinator {
    let fetchProducts: () async -> Void
    let checkEntitlements: () async -> Void
    let retryPendingVerifications: () async -> Void
    let listenForTransactions: () -> Task<Void, Never>

    func run() async {
        await fetchProducts()
        await checkEntitlements()
        await retryPendingVerifications()
        _ = listenForTransactions()
    }
}
