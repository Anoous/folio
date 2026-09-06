import XCTest
@testable import Folio

final class HomeQuotaSnapshotTests: XCTestCase {
    func testFreeQuotaAvailable() {
        let snapshot = HomeQuotaSnapshot(
            isAuthenticated: true,
            isPro: false,
            used: 10,
            monthlyQuota: 30
        )

        XCTAssertEqual(snapshot.state, .available)
        XCTAssertEqual(snapshot.remaining, 20)
        XCTAssertEqual(snapshot.progress, 10.0 / 30.0, accuracy: 0.001)
    }

    func testFreeQuotaWarningNearLimit() {
        let snapshot = HomeQuotaSnapshot(
            isAuthenticated: true,
            isPro: false,
            used: 24,
            monthlyQuota: 30
        )

        XCTAssertEqual(snapshot.state, .warning)
        XCTAssertEqual(snapshot.remaining, 6)
    }

    func testFreeQuotaExceeded() {
        let snapshot = HomeQuotaSnapshot(
            isAuthenticated: true,
            isPro: false,
            used: 31,
            monthlyQuota: 30
        )

        XCTAssertEqual(snapshot.state, .exceeded)
        XCTAssertEqual(snapshot.remaining, 0)
        XCTAssertEqual(snapshot.progress, 1)
    }

    func testProOverridesQuota() {
        let snapshot = HomeQuotaSnapshot(
            isAuthenticated: true,
            isPro: true,
            used: 31,
            monthlyQuota: 30
        )

        XCTAssertEqual(snapshot.state, .pro)
    }

    func testSignedOutState() {
        let snapshot = HomeQuotaSnapshot(
            isAuthenticated: false,
            isPro: false,
            used: 0,
            monthlyQuota: 30
        )

        XCTAssertEqual(snapshot.state, .signedOut)
    }

    func testWorkbenchOnlyShowsActionableQuotaStates() {
        let available = HomeQuotaSnapshot(isAuthenticated: true, isPro: false, used: 10, monthlyQuota: 30)
        let warning = HomeQuotaSnapshot(isAuthenticated: true, isPro: false, used: 24, monthlyQuota: 30)
        let exceeded = HomeQuotaSnapshot(isAuthenticated: true, isPro: false, used: 30, monthlyQuota: 30)
        let pro = HomeQuotaSnapshot(isAuthenticated: true, isPro: true, used: 30, monthlyQuota: 30)
        let signedOut = HomeQuotaSnapshot(isAuthenticated: false, isPro: false, used: 0, monthlyQuota: 30)

        XCTAssertFalse(available.shouldShowOnWorkbench)
        XCTAssertTrue(warning.shouldShowOnWorkbench)
        XCTAssertTrue(exceeded.shouldShowOnWorkbench)
        XCTAssertFalse(pro.shouldShowOnWorkbench)
        XCTAssertFalse(signedOut.shouldShowOnWorkbench)
    }

    func testWorkbenchMetricsUseActualZeroCounts() {
        let metrics = HomeWorkbenchMetrics(
            processingCount: 0,
            continueReadingCount: 0,
            askableCount: 0
        )

        XCTAssertEqual(metrics.processingCount, 0)
        XCTAssertEqual(metrics.continueReadingCount, 0)
        XCTAssertEqual(metrics.askableCount, 0)
    }

    func testWorkbenchMetricsAreDerivedWithoutPadding() {
        let metrics = HomeWorkbenchMetrics(
            processingCount: 1,
            continueReadingCount: 2,
            askableCount: 3
        )

        XCTAssertEqual(metrics.processingCount, 1)
        XCTAssertEqual(metrics.continueReadingCount, 2)
        XCTAssertEqual(metrics.askableCount, 3)
    }
}
