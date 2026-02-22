import XCTest
@testable import Folio

final class QuotaCheckTests: XCTestCase {

    private var testDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        testDefaults = UserDefaults(suiteName: "com.folio.test.quota")!
        testDefaults.removePersistentDomain(forName: "com.folio.test.quota")
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: "com.folio.test.quota")
        testDefaults = nil
        super.tearDown()
    }

    func testFreeUser_underQuota() {
        for i in 0..<29 {
            testDefaults.set(i, forKey: SharedDataManager.quotaKey())
            XCTAssertTrue(SharedDataManager.canSave(isPro: false, userDefaults: testDefaults))
        }
    }

    func testFreeUser_atQuota() {
        testDefaults.set(29, forKey: SharedDataManager.quotaKey())
        XCTAssertTrue(SharedDataManager.canSave(isPro: false, userDefaults: testDefaults))
    }

    func testFreeUser_overQuota() {
        testDefaults.set(30, forKey: SharedDataManager.quotaKey())
        XCTAssertFalse(SharedDataManager.canSave(isPro: false, userDefaults: testDefaults))
    }

    func testProUser_noQuotaLimit() {
        testDefaults.set(100, forKey: SharedDataManager.quotaKey())
        XCTAssertTrue(SharedDataManager.canSave(isPro: true, userDefaults: testDefaults))
    }

    func testQuotaResets_onNewMonth() {
        let lastMonth = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
        let lastMonthKey = SharedDataManager.quotaKey(for: lastMonth)
        testDefaults.set(30, forKey: lastMonthKey)

        let currentCount = SharedDataManager.currentMonthCount(userDefaults: testDefaults)
        XCTAssertEqual(currentCount, 0, "Current month should start at 0")
    }

    func testQuotaKey_includesYearMonth() {
        let key = SharedDataManager.quotaKey()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        let expected = "quota_\(formatter.string(from: Date()))"
        XCTAssertEqual(key, expected)
    }

    // MARK: - incrementQuota Tests

    func testIncrementQuota_incrementsCount() {
        XCTAssertEqual(SharedDataManager.currentMonthCount(userDefaults: testDefaults), 0)
        SharedDataManager.incrementQuota(userDefaults: testDefaults)
        XCTAssertEqual(SharedDataManager.currentMonthCount(userDefaults: testDefaults), 1)
    }

    func testIncrementQuota_multipleCalls() {
        for _ in 0..<5 {
            SharedDataManager.incrementQuota(userDefaults: testDefaults)
        }
        XCTAssertEqual(SharedDataManager.currentMonthCount(userDefaults: testDefaults), 5)
    }

    func testIncrementQuota_thenCanSave_fails() {
        for _ in 0..<30 {
            SharedDataManager.incrementQuota(userDefaults: testDefaults)
        }
        XCTAssertFalse(SharedDataManager.canSave(isPro: false, userDefaults: testDefaults))
    }
}
