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
    func testNetworkAvailable_triggerProcessing() async throws {
        let a = Article(url: "https://example.com/pending")
        a.status = .pending
        context.insert(a)
        try context.save()

        let manager = OfflineQueueManager(context: context)
        var processCalled = false
        manager.onProcessPending = { articles in
            processCalled = true
            return Dictionary(uniqueKeysWithValues: articles.map { ($0.id, true) })
        }

        await manager.processPendingArticles()
        XCTAssertTrue(processCalled)
    }

    @MainActor
    func testProcessPending_updatesStatus() async throws {
        let a = Article(url: "https://example.com/pending")
        a.status = .pending
        context.insert(a)
        try context.save()

        let manager = OfflineQueueManager(context: context)
        manager.onProcessPending = { articles in
            Dictionary(uniqueKeysWithValues: articles.map { ($0.id, true) })
        }

        await manager.processPendingArticles()
        XCTAssertNotEqual(a.status, .pending)
        XCTAssertEqual(a.status, .processing)
    }

    @MainActor
    func testProcessFailed_keepsStatusForRetry() async throws {
        let a = Article(url: "https://example.com/fail")
        a.status = .pending
        context.insert(a)
        try context.save()

        let manager = OfflineQueueManager(context: context)
        manager.onProcessPending = { articles in
            Dictionary(uniqueKeysWithValues: articles.map { ($0.id, false) })
        }

        await manager.processPendingArticles()
        // Transient failures keep original status for retry, not marked as failed
        XCTAssertEqual(a.status, .pending)
    }

    @MainActor
    func testBackgroundTaskRegistration() {
        XCTAssertEqual(OfflineQueueManager.backgroundTaskIdentifier, "com.folio.article-processing")
    }
}
