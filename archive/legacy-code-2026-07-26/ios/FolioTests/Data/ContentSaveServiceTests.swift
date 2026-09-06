import XCTest
import SwiftData
import UIKit
@testable import Folio

final class ContentSaveServiceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var searchIndexer: SearchIndexCoordinator!

    @MainActor
    override func setUp() {
        super.setUp()
        container = try! DataManager.createInMemoryContainer()
        context = container.mainContext
        searchIndexer = SearchIndexCoordinator(searchManager: try! FTS5SearchManager(inMemory: true))
    }

    override func tearDown() {
        searchIndexer = nil
        container = nil
        context = nil
        super.tearDown()
    }

    @MainActor
    func testSaveScreenshot_updatesSearchIndexAfterOCR() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let service = ContentSaveService(
            context: context,
            syncService: nil,
            searchIndexCoordinator: searchIndexer,
            imageStorageURLProvider: { tempDir },
            imageOCRExtractor: { _ in
                "Swift concurrency keeps UI state predictable."
            }
        )

        let image = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24)).image { rendererContext in
            UIColor.white.setFill()
            rendererContext.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
        }

        let completed = expectation(description: "ocr complete")
        let result = service.saveScreenshot(image) {
            completed.fulfill()
        }
        guard case .success = result else {
            return XCTFail("Expected screenshot save to succeed")
        }

        await fulfillment(of: [completed], timeout: 2.0)

        let results = try searchIndexer.searchManager.search(query: "predictable")
        XCTAssertEqual(results.count, 1)

        let articles = try context.fetch(FetchDescriptor<Article>())
        XCTAssertEqual(articles.count, 1)
        XCTAssertEqual(articles.first?.markdownContent, "Swift concurrency keeps UI state predictable.")
    }
}
