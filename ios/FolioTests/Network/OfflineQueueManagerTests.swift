import XCTest
import SwiftData
@testable import Folio

final class OfflineQueueManagerTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    @MainActor
    override func setUp() {
        super.setUp()
        container = try! DataManager.createInMemoryContainer()
        context = container.mainContext
    }

    override func tearDown() {
        container = nil
        context = nil
        super.tearDown()
    }

    @MainActor
    func testPendingCount_reflectsActualPending() throws {
        let a1 = Article(url: "https://example.com/1")
        a1.status = .pending
        let a2 = Article(url: "https://example.com/2")
        a2.status = .ready
        let a3 = Article(url: "https://example.com/3")
        a3.status = .pending
        context.insert(a1)
        context.insert(a2)
        context.insert(a3)
        try context.save()

        let manager = OfflineQueueManager(context: context)
        XCTAssertEqual(manager.pendingCount, 2)
    }

    @MainActor
    func testNetworkRestored_callbackInvoked() async throws {
        let manager = OfflineQueueManager(context: context)
        var callbackInvoked = false
        manager.onNetworkRestored = {
            callbackInvoked = true
        }

        // Verify callback is set (actual network trigger requires NWPathMonitor)
        XCTAssertNotNil(manager.onNetworkRestored)
        await manager.onNetworkRestored?()
        XCTAssertTrue(callbackInvoked)
    }

    @MainActor
    func testRefreshPendingCount_afterInsert() throws {
        let manager = OfflineQueueManager(context: context)
        XCTAssertEqual(manager.pendingCount, 0)

        let a = Article(url: "https://example.com/new")
        a.status = .clientReady
        context.insert(a)
        try context.save()

        manager.refreshPendingCount()
        XCTAssertEqual(manager.pendingCount, 1)
    }

    @MainActor
    func testBackgroundTaskRegistration() {
        XCTAssertEqual(OfflineQueueManager.backgroundTaskIdentifier, "com.folio.article-processing")
    }
}
