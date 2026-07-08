import XCTest
import SwiftData
import UIKit
@testable import Folio

final class ContentIntakeWorkflowTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var userDefaults: UserDefaults!
    private var suiteName: String!

    @MainActor
    override func setUp() {
        super.setUp()
        container = try! DataManager.createInMemoryContainer()
        context = container.mainContext
        suiteName = "com.folio.content-intake-tests.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults.set(30, forKey: SharedDataManager.monthlyQuotaKey)
    }

    override func tearDown() {
        if let suiteName {
            userDefaults?.removePersistentDomain(forName: suiteName)
        }
        userDefaults = nil
        suiteName = nil
        context = nil
        container = nil
        super.tearDown()
    }

    @MainActor
    func testSaveURLOwnsQuotaIndexFlagAndSyncTrigger() throws {
        let searchIndexer = SearchIndexCoordinator(searchManager: try FTS5SearchManager(inMemory: true))
        var syncRequested = false
        let workflow = ContentIntakeWorkflow(
            context: context,
            userDefaults: userDefaults,
            onArticleIndexed: { searchIndexer.sync($0) },
            onArticleUpdated: { searchIndexer.sync($0) },
            onSaveCompleted: {
                self.userDefaults.set(true, forKey: AppConstants.shareExtensionDidSaveKey)
            },
            onSyncRequested: { syncRequested = true }
        )

        let result = workflow.saveURL("https://example.com/swift")

        guard case .saved(let receipt) = result else {
            return XCTFail("Expected saved result")
        }
        XCTAssertEqual(receipt.article.url, "https://example.com/swift")
        XCTAssertEqual(SharedDataManager.currentMonthCount(userDefaults: userDefaults), 1)
        XCTAssertTrue(userDefaults.bool(forKey: AppConstants.shareExtensionDidSaveKey))
        XCTAssertTrue(syncRequested)
        XCTAssertEqual(try searchIndexer.searchManager.search(query: "example").count, 1)
    }

    @MainActor
    func testDuplicateURLDoesNotIncrementQuotaOrRequestSync() throws {
        let workflow = ContentIntakeWorkflow(context: context, userDefaults: userDefaults)
        _ = workflow.saveURL("https://example.com/dupe")
        var syncRequested = false
        let secondWorkflow = ContentIntakeWorkflow(
            context: context,
            userDefaults: userDefaults,
            onSyncRequested: { syncRequested = true }
        )

        let result = secondWorkflow.saveURL("https://example.com/dupe")

        guard case .duplicate(let receipt) = result else {
            return XCTFail("Expected duplicate result")
        }
        XCTAssertEqual(receipt.displayName, "example.com")
        XCTAssertEqual(SharedDataManager.currentMonthCount(userDefaults: userDefaults), 1)
        XCTAssertFalse(syncRequested)
    }

    @MainActor
    func testBackgroundOCRCompletesEvenWhenScreenshotArticleWasDeleted() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("folio-content-intake-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let ocrStarted = expectation(description: "OCR started")
        let ocrCompleted = expectation(description: "OCR completion callback")
        let syncRequested = expectation(description: "sync requested")
        var ocrContinuation: CheckedContinuation<String?, Error>?
        let workflow = ContentIntakeWorkflow(
            context: context,
            userDefaults: userDefaults,
            imageStorageURLProvider: { tempDirectory },
            imageOCRExtractor: { _ in
                try await withCheckedThrowingContinuation { continuation in
                    ocrContinuation = continuation
                    ocrStarted.fulfill()
                }
            },
            onSyncRequested: {
                syncRequested.fulfill()
            }
        )

        let result = workflow.saveScreenshotWithBackgroundOCR(Self.testImage()) {
            ocrCompleted.fulfill()
        }
        guard case .saved(let receipt) = result else {
            return XCTFail("Expected screenshot save to start")
        }
        context.delete(receipt.article)
        try context.save()

        await fulfillment(of: [ocrStarted], timeout: 1)
        ocrContinuation?.resume(returning: "OCR text after deletion")
        await fulfillment(of: [ocrCompleted, syncRequested], timeout: 1)
    }

    private static func testImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }
}
