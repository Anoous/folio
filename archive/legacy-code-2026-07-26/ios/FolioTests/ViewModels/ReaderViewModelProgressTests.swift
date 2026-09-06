import XCTest
import SwiftData
@testable import Folio

final class ReaderViewModelProgressTests: XCTestCase {

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
    func testInitialProgress_zero() throws {
        let article = Article(url: "https://example.com", title: "New")
        context.insert(article)
        try context.save()

        let vm = ReaderViewModel(article: article, context: context)
        XCTAssertEqual(vm.readingProgress, 0)
    }

    @MainActor
    func testUpdateProgress_savesToModel() throws {
        let article = Article(url: "https://example.com", title: "Read")
        context.insert(article)
        try context.save()

        let vm = ReaderViewModel(article: article, context: context)
        vm.updateReadingProgress(0.5)
        XCTAssertEqual(article.readProgress, 0.5, accuracy: 0.01)
    }

    @MainActor
    func testProgress_clampedTo0And1() throws {
        let article = Article(url: "https://example.com", title: "Clamp")
        context.insert(article)
        try context.save()

        let vm = ReaderViewModel(article: article, context: context)

        vm.updateReadingProgress(-0.5)
        XCTAssertEqual(article.readProgress, 0)

        vm.updateReadingProgress(1.5)
        XCTAssertEqual(article.readProgress, 1.0)
    }

    @MainActor
    func testScrollToBottom_marksComplete() throws {
        let article = Article(url: "https://example.com", title: "Complete")
        context.insert(article)
        try context.save()

        let vm = ReaderViewModel(article: article, context: context)
        vm.updateReadingProgress(1.0)
        XCTAssertEqual(article.readProgress, 1.0)
    }

    @MainActor
    func testRestorePosition_onReopen() throws {
        let article = Article(url: "https://example.com", title: "Restore")
        article.readProgress = 0.6
        context.insert(article)
        try context.save()

        let vm = ReaderViewModel(article: article, context: context)
        XCTAssertEqual(vm.readingProgress, 0.6, accuracy: 0.01)
    }

    @MainActor
    func testLastReadAt_updatedOnScroll() throws {
        let article = Article(url: "https://example.com", title: "Scroll")
        context.insert(article)
        try context.save()
        XCTAssertNil(article.lastReadAt)

        let vm = ReaderViewModel(article: article, context: context)
        vm.updateReadingProgress(0.3)
        XCTAssertNotNil(article.lastReadAt)
    }

    @MainActor
    func testPersistProgressIfNeeded_flushesSubThresholdProgress() throws {
        let article = Article(url: "https://example.com", title: "Flush")
        article.serverID = "server-1"
        article.syncState = .synced
        context.insert(article)
        try context.save()

        let vm = ReaderViewModel(article: article, context: context)
        // Update with small delta (0.005) — below the 1% persist threshold
        // This sets readingProgress but does NOT call safeSave
        vm.updateReadingProgress(0.005)
        XCTAssertEqual(vm.readingProgress, 0.005, accuracy: 0.001)
        // syncState should still be synced (not persisted yet)
        XCTAssertEqual(article.syncState, .synced)

        // persistProgressIfNeeded should flush it
        vm.persistProgressIfNeeded()
        XCTAssertEqual(article.syncState, .pendingUpdate)
    }

    @MainActor
    func testPersistProgressIfNeeded_noopWhenAlreadyPersisted() throws {
        let article = Article(url: "https://example.com", title: "Noop")
        context.insert(article)
        try context.save()

        let vm = ReaderViewModel(article: article, context: context)
        // Update above threshold — will be persisted immediately
        vm.updateReadingProgress(0.5)
        // Now call persist — should be a no-op since lastPersistedProgress == readingProgress
        vm.persistProgressIfNeeded()
        // No crash, no side effects
        XCTAssertEqual(article.readProgress, 0.5, accuracy: 0.01)
    }

    @MainActor
    func testUpdateProgress_marksSyncedArticlePendingUpdate() throws {
        let article = Article(url: "https://example.com", title: "Sync me")
        article.serverID = "server-1"
        article.syncState = .synced
        context.insert(article)
        try context.save()

        let vm = ReaderViewModel(article: article, context: context)
        vm.updateReadingProgress(0.3)

        XCTAssertEqual(article.syncState, .pendingUpdate)
    }
}
