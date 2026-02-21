import XCTest
@testable import Folio

final class KeyChainManagerTests: XCTestCase {

    private var manager: KeyChainManager!

    override func setUp() {
        super.setUp()
        manager = KeyChainManager(service: "com.folio.app.tests")
        try? manager.clearTokens()
    }

    override func tearDown() {
        try? manager.clearTokens()
        manager = nil
        super.tearDown()
    }

    func testSaveTokens_storesBothTokens() throws {
        try manager.saveTokens(access: "a_token", refresh: "r_token")
        XCTAssertNotNil(manager.accessToken)
        XCTAssertNotNil(manager.refreshToken)
    }

    func testAccessToken_nilWhenEmpty() {
        XCTAssertNil(manager.accessToken)
    }

    func testRefreshToken_nilWhenEmpty() {
        XCTAssertNil(manager.refreshToken)
    }

    func testSaveTokens_overwritesPrevious() throws {
        try manager.saveTokens(access: "old_access", refresh: "old_refresh")
        try manager.saveTokens(access: "new_access", refresh: "new_refresh")
        XCTAssertEqual(manager.accessToken, "new_access")
        XCTAssertEqual(manager.refreshToken, "new_refresh")
    }

    func testClearTokens_removesBoth() throws {
        try manager.saveTokens(access: "a", refresh: "r")
        try manager.clearTokens()
        XCTAssertNil(manager.accessToken)
        XCTAssertNil(manager.refreshToken)
    }

    func testClearTokens_whenEmpty_succeeds() throws {
        XCTAssertNoThrow(try manager.clearTokens())
    }

    func testSaveAndRetrieve_accessToken() throws {
        try manager.saveTokens(access: "my_access_123", refresh: "r")
        XCTAssertEqual(manager.accessToken, "my_access_123")
    }

    func testSaveAndRetrieve_refreshToken() throws {
        try manager.saveTokens(access: "a", refresh: "my_refresh_456")
        XCTAssertEqual(manager.refreshToken, "my_refresh_456")
    }
}
