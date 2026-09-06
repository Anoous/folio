import StoreKit
import SwiftUI

@Observable
@MainActor
class SubscriptionManager {
    var products: [Product] = []
    var purchasedProductIDs: Set<String> = []
    var isPro: Bool { !purchasedProductIDs.isEmpty }
    var isLoading = false
    var errorMessage: String?

    private let productIDs = [
        AppConstants.proYearlyProductID,
        AppConstants.proMonthlyProductID
    ]

    var yearlyProduct: Product? { products.first { $0.id.contains("yearly") } }
    var monthlyProduct: Product? { products.first { $0.id.contains("monthly") } }

    func fetchProducts() async {
        do {
            products = try await Product.products(for: productIDs)
                .sorted { $0.price > $1.price } // yearly first
        } catch {
            // Products not available (no StoreKit config / not in App Store Connect yet)
        }
    }

    func purchase(_ product: Product) async {
        isLoading = true
        errorMessage = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                let serverOK = await verifyWithServer(transactionID: transaction.id, productID: product.id)
                purchasedProductIDs.insert(product.id)
                if !serverOK {
                    savePendingVerification(transactionID: transaction.id, productID: product.id)
                }
                await transaction.finish()
            case .pending:
                errorMessage = nil // Awaiting approval
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = "购买失败，请重试"
        }
        isLoading = false
    }

    func checkEntitlements() async {
        var ids: Set<String> = []
        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result) {
                ids.insert(transaction.productID)
            }
        }
        purchasedProductIDs = ids
    }

    func listenForTransactions() -> Task<Void, Never> {
        Task.detached {
            for await result in Transaction.updates {
                if let transaction = try? self.checkVerified(result) {
                    let serverOK = await self.verifyWithServer(transactionID: transaction.id, productID: transaction.productID)
                    _ = await MainActor.run {
                        self.purchasedProductIDs.insert(transaction.productID)
                    }
                    if !serverOK {
                        await MainActor.run {
                            self.savePendingVerification(transactionID: transaction.id, productID: transaction.productID)
                        } as Void
                    }
                    await transaction.finish()
                }
            }
        }
    }

    func restorePurchases() async {
        isLoading = true
        try? await AppStore.sync()
        await checkEntitlements()
        isLoading = false
    }

    nonisolated private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value): return value
        case .unverified: throw StoreError.verificationFailed
        }
    }

    private func verifyWithServer(transactionID: UInt64, productID: String) async -> Bool {
        for attempt in 0..<3 {
            do {
                _ = try await APIClient.shared.verifySubscription(
                    transactionID: transactionID,
                    productID: productID
                )
                return true
            } catch {
                FolioLogger.auth.error("server verification attempt \(attempt + 1) failed: \(error)")
                if attempt < 2 {
                    try? await Task.sleep(for: .seconds(Double(1 << attempt)))
                }
            }
        }
        return false
    }

    enum StoreError: Error {
        case verificationFailed
    }

    // MARK: - Pending Server Verification

    private struct PendingVerification: Codable {
        let transactionID: UInt64
        let productID: String
    }

    private static let pendingVerificationsKey = "pendingServerVerifications"

    private func savePendingVerification(transactionID: UInt64, productID: String) {
        var pending = Self.loadPendingVerifications()
        pending.append(PendingVerification(transactionID: transactionID, productID: productID))
        if let data = try? JSONEncoder().encode(pending) {
            UserDefaults.standard.set(data, forKey: Self.pendingVerificationsKey)
        }
    }

    private static func loadPendingVerifications() -> [PendingVerification] {
        guard let data = UserDefaults.standard.data(forKey: pendingVerificationsKey),
              let items = try? JSONDecoder().decode([PendingVerification].self, from: data)
        else { return [] }
        return items
    }

    func retryPendingVerifications() async {
        let pending = Self.loadPendingVerifications()
        guard !pending.isEmpty else { return }
        var remaining: [PendingVerification] = []
        for item in pending {
            let ok = await verifyWithServer(transactionID: item.transactionID, productID: item.productID)
            if !ok { remaining.append(item) }
        }
        if let data = try? JSONEncoder().encode(remaining) {
            UserDefaults.standard.set(data, forKey: Self.pendingVerificationsKey)
        }
    }
}
