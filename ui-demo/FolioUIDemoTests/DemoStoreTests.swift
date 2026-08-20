import XCTest
@testable import FolioUIDemo

@MainActor
final class DemoStoreTests: XCTestCase {
    func testFreshSignInStartsEmptyAndAcceptedCaptureIsDeduplicated() throws {
        let store = DemoStore()
        store.signIn(email: "reader@example.com")

        XCTAssertTrue(store.articles.isEmpty)
        XCTAssertEqual(store.accountEmail, "reader@example.com")

        let url = try XCTUnwrap(URL(string: "https://example.com/first"))
        XCTAssertEqual(
            store.captureURL(url),
            .success(.accepted(host: "example.com"))
        )
        XCTAssertEqual(store.articles.count, 1)
        XCTAssertEqual(store.articles.first?.status, .accepted)

        XCTAssertEqual(
            store.captureURL(url),
            .success(.duplicate(host: "example.com"))
        )
        XCTAssertEqual(store.articles.count, 1)
    }

    func testCaptureFailuresNeverCreateInvisibleLocalItems() throws {
        let store = DemoStore()
        store.signIn()
        let url = try XCTUnwrap(URL(string: "https://example.com/failure"))

        store.isOnline = false
        XCTAssertEqual(store.captureURL(url), .failure(.offline))
        XCTAssertTrue(store.articles.isEmpty)

        store.isOnline = true
        store.isCapacityFull = true
        XCTAssertEqual(store.captureURL(url), .failure(.capacityFull))
        XCTAssertTrue(store.articles.isEmpty)

        store.isCapacityFull = false
        store.shouldTimeoutNextCapture = true
        XCTAssertEqual(store.captureURL(url), .failure(.timeout))
        XCTAssertTrue(store.articles.isEmpty)
    }

    func testDeleteUndoAndSignInRestoreExistingLibrary() throws {
        let store = DemoStore()
        store.signIn()
        let url = try XCTUnwrap(URL(string: "https://example.com/restore"))
        _ = store.captureURL(url)
        let article = try XCTUnwrap(store.articles.first)

        store.deleteArticle(article)
        XCTAssertTrue(store.articles.isEmpty)
        XCTAssertEqual(store.pendingDeletion?.article.id, article.id)

        store.undoDeletion()
        XCTAssertEqual(store.articles.map(\.id), [article.id])

        store.signOut()
        XCTAssertFalse(store.isSignedIn)
        XCTAssertEqual(store.articles.count, 1)

        store.signIn()
        XCTAssertTrue(store.isSignedIn)
        XCTAssertEqual(store.articles.map(\.id), [article.id])
    }
}
