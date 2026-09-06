import XCTest
import SwiftData
@testable import Folio

final class BackgroundSyncCoordinatorTests: XCTestCase {

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
    func testPendingArticleCount_countsPendingAndClientReady() throws {
        let pending = Article(url: "https://example.com/pending")
        pending.status = .pending

        let clientReady = Article(content: "Local content")
        clientReady.status = .clientReady

        let ready = Article(url: "https://example.com/ready")
        ready.status = .ready

        context.insert(pending)
        context.insert(clientReady)
        context.insert(ready)
        try context.save()

        XCTAssertEqual(BackgroundSyncCoordinator.pendingArticleCount(in: context), 2)
    }

    @MainActor
    func testPerformPendingSyncIfNeeded_skipsWhenUnauthenticated() async {
        let article = Article(url: "https://example.com/pending")
        article.status = .pending
        context.insert(article)
        try? context.save()

        var syncCalls = 0
        let success = await BackgroundSyncCoordinator.performPendingSyncIfNeeded(
            context: context,
            isAuthenticated: false
        ) {
            syncCalls += 1
        }

        XCTAssertTrue(success)
        XCTAssertEqual(syncCalls, 0)
    }

    @MainActor
    func testPerformPendingSyncIfNeeded_skipsWhenNoPendingArticles() async {
        let article = Article(url: "https://example.com/ready")
        article.status = .ready
        context.insert(article)
        try? context.save()

        var syncCalls = 0
        let success = await BackgroundSyncCoordinator.performPendingSyncIfNeeded(
            context: context,
            isAuthenticated: true
        ) {
            syncCalls += 1
        }

        XCTAssertTrue(success)
        XCTAssertEqual(syncCalls, 0)
    }

    @MainActor
    func testPerformPendingSyncIfNeeded_runsWhenAuthenticatedAndPending() async {
        let article = Article(url: "https://example.com/pending")
        article.status = .pending
        context.insert(article)
        try? context.save()

        var syncCalls = 0
        let success = await BackgroundSyncCoordinator.performPendingSyncIfNeeded(
            context: context,
            isAuthenticated: true
        ) {
            syncCalls += 1
        }

        XCTAssertTrue(success)
        XCTAssertEqual(syncCalls, 1)
    }
}
