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
        "com.folio.app.pro.yearly",
        "com.folio.app.pro.monthly"
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
                // Verify with server
                await verifyWithServer(transactionID: transaction.id, productID: product.id)
                purchasedProductIDs.insert(product.id)
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
                    await self.verifyWithServer(transactionID: transaction.id, productID: transaction.productID)
                    await MainActor.run {
                        self.purchasedProductIDs.insert(transaction.productID)
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

    private func verifyWithServer(transactionID: UInt64, productID: String) async {
        do {
            _ = try await APIClient.shared.verifySubscription(
                transactionID: transactionID,
                productID: productID
            )
        } catch {
            // Server verification failed — still honor local StoreKit verification
        }
    }

    enum StoreError: Error {
        case verificationFailed
    }
}
