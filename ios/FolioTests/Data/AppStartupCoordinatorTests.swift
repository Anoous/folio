import XCTest
@testable import Folio

final class AppStartupCoordinatorTests: XCTestCase {

    @MainActor
    func testRun_retriesPendingVerificationsBeforeStartingTransactionListener() async {
        var events: [String] = []

        let coordinator = AppStartupCoordinator(
            fetchProducts: {
                events.append("fetchProducts")
            },
            checkEntitlements: {
                events.append("checkEntitlements")
            },
            retryPendingVerifications: {
                events.append("retryPendingVerifications")
            },
            listenForTransactions: {
                events.append("listenForTransactions")
                return Task {}
            }
        )

        await coordinator.run()

        XCTAssertEqual(
            events,
            [
                "fetchProducts",
                "checkEntitlements",
                "retryPendingVerifications",
                "listenForTransactions",
            ]
        )
    }
}
