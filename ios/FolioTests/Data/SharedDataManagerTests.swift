import XCTest
import SwiftData
@testable import Folio

final class SharedDataManagerTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var manager: SharedDataManager!

    @MainActor
    override func setUp() {
        super.setUp()
        container = try! DataManager.createInMemoryContainer()
        context = container.mainContext
        manager = SharedDataManager(context: context)
    }

    override func tearDown() {
        manager = nil
        container = nil
        context = nil
        super.tearDown()
    }

    @MainActor
    func testSaveArticle_createsPendingArticle() throws {
        let article = try manager.saveArticle(url: "https://example.com/test")
        XCTAssertEqual(article.url, "https://example.com/test")
        XCTAssertEqual(article.status, .pending)
    }

    @MainActor
    func testSaveArticle_extractsURLFromPlainText() throws {
        let article = try manager.saveArticleFromText("Check this out: https://example.com/link some text")
        XCTAssertEqual(article.url, "https://example.com/link")
    }

    @MainActor
    func testSaveArticle_duplicateURL() throws {
        _ = try manager.saveArticle(url: "https://example.com/dup")
        XCTAssertThrowsError(try manager.saveArticle(url: "https://example.com/dup")) { error in
            XCTAssertTrue(error is SharedDataError)
        }
    }

    @MainActor
    func testSaveArticle_setsSourceType() throws {
        let article = try manager.saveArticle(url: "https://mp.weixin.qq.com/s/abc123")
        XCTAssertEqual(article.sourceType, .wechat)
    }

    @MainActor
    func testSharedContainer_accessible() throws {
        let article = try manager.saveArticle(url: "https://example.com/shared")
        let exists = try manager.existsByURL("https://example.com/shared")
        XCTAssertTrue(exists)
        XCTAssertNotNil(article.id)
    }

    // MARK: - Edge Cases

    @MainActor
    func testSaveArticleFromText_noURL_throwsInvalidInput() throws {
        // Plain text without a valid URL should be rejected
        XCTAssertThrowsError(try manager.saveArticleFromText("just plain text no link")) { error in
            XCTAssertEqual(error as? SharedDataError, .invalidInput)
        }
    }

    @MainActor
    func testSaveArticleFromText_multipleURLs() throws {
        // Should pick the first URL found
        let article = try manager.saveArticleFromText("first https://example.com/first then https://example.com/second")
        XCTAssertEqual(article.url, "https://example.com/first")
    }

    @MainActor
    func testSaveArticle_emptyURL() throws {
        // Empty string is technically accepted (no crash)
        let article = try manager.saveArticle(url: "")
        XCTAssertEqual(article.url, "")
    }

    // MARK: - Quota Sync Tests

    func testSyncQuotaFromServer_updatesWhenServerCountIsHigher() {
        let defaults = UserDefaults(suiteName: "test.quota.\(UUID())")!
        let key = SharedDataManager.quotaKey()
        defaults.set(5, forKey: key)

        SharedDataManager.syncQuotaFromServer(
            monthlyQuota: 30,
            currentMonthCount: 12,
            isPro: false,
            userDefaults: defaults
        )

        XCTAssertEqual(defaults.integer(forKey: key), 12)
    }

    func testSyncQuotaFromServer_doesNotDecreaseLocalCount() {
        let defaults = UserDefaults(suiteName: "test.quota.\(UUID())")!
        let key = SharedDataManager.quotaKey()
        defaults.set(15, forKey: key)

        SharedDataManager.syncQuotaFromServer(
            monthlyQuota: 30,
            currentMonthCount: 10,
            isPro: false,
            userDefaults: defaults
        )

        XCTAssertEqual(defaults.integer(forKey: key), 15)
    }

    func testCanSave_usesServerQuotaWhenAvailable() {
        let defaults = UserDefaults(suiteName: "test.quota.\(UUID())")!
        let key = SharedDataManager.quotaKey()

        defaults.set(35, forKey: key)
        defaults.set(50, forKey: SharedDataManager.monthlyQuotaKey)
        XCTAssertTrue(SharedDataManager.canSave(isPro: false, userDefaults: defaults))

        defaults.set(51, forKey: key)
        XCTAssertFalse(SharedDataManager.canSave(isPro: false, userDefaults: defaults))
    }

    // MARK: - Cross-Module Contract Tests

    /// 验证 syncQuotaFromServer 写入的 isPro key 与 ShareViewController 读取的 key 一致。
    /// 这个测试守护两个模块之间的隐式契约：如果任一方改了 key，测试立即失败。
    func testSyncQuotaFromServer_isProKeyMatchesShareExtensionReadPath() {
        let defaults = UserDefaults(suiteName: "test.contract.\(UUID())")!

        SharedDataManager.syncQuotaFromServer(
            monthlyQuota: 30,
            currentMonthCount: 0,
            isPro: true,
            userDefaults: defaults
        )

        // ShareViewController 通过 SharedDataManager.isProUserKey 读取（原为硬编码 "is_pro_user"）
        let readBack = defaults.bool(forKey: SharedDataManager.isProUserKey)
        XCTAssertTrue(readBack, "syncQuotaFromServer 写入的 isPro key 必须与 ShareExtension 读取路径一致")
    }

    /// 验证 syncQuotaFromServer 写入的 monthlyQuota key 与 canSave 读取的 key 一致。
    func testSyncQuotaFromServer_quotaKeyMatchesCanSaveReadPath() {
        let defaults = UserDefaults(suiteName: "test.contract.\(UUID())")!
        let countKey = SharedDataManager.quotaKey()

        SharedDataManager.syncQuotaFromServer(
            monthlyQuota: 50,
            currentMonthCount: 10,
            isPro: false,
            userDefaults: defaults
        )

        // canSave 内部读取 monthlyQuotaKey，应得到 syncQuotaFromServer 写入的 50
        defaults.set(49, forKey: countKey)
        XCTAssertTrue(SharedDataManager.canSave(isPro: false, userDefaults: defaults),
            "49 < 50 应可保存")

        defaults.set(50, forKey: countKey)
        XCTAssertFalse(SharedDataManager.canSave(isPro: false, userDefaults: defaults),
            "50 >= 50 应拒绝")
    }
}
