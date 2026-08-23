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

    func testHighlightNoteSearchAndMarkdownExportStayConnectedToSource() throws {
        let store = DemoStore(initialScreen: .library)
        let article = DemoContent.primaryArticle
        let paragraphIndex = 0
        let paragraph = article.originalParagraphs[paragraphIndex] as NSString
        let quote = "可信不是一种感觉，而是一种可验证的体验质量。"
        let range = paragraph.range(of: quote)
        let selection = DemoTextSelection(
            paragraphIndex: paragraphIndex,
            range: range,
            text: quote
        )

        let highlight = try XCTUnwrap(store.addHighlight(to: article, selection: selection))
        store.updateHighlightNote("用于发布前的可信度检查。", highlightID: highlight.id)
        store.updateArticleNote("把证据入口放在答案旁边。", for: article.id)

        store.searchQuery = "可信度检查"
        let noteResult = try XCTUnwrap(store.searchResults.first)
        XCTAssertEqual(noteResult.article.id, article.id)
        XCTAssertEqual(noteResult.paragraphIndex, paragraphIndex)

        store.searchQuery = "证据入口"
        XCTAssertEqual(store.searchResults.first?.article.id, article.id)

        let markdown = store.markdownExport(for: article)
        XCTAssertTrue(markdown.contains("# \(article.title)"))
        XCTAssertTrue(markdown.contains(quote))
        XCTAssertTrue(markdown.contains("用于发布前的可信度检查。"))
        XCTAssertTrue(markdown.contains("把证据入口放在答案旁边。"))
    }

    func testSearchCoversBodyAndAnnotationsWithoutDuplicatingAnArticle() throws {
        let store = DemoStore(initialScreen: .library)

        store.searchQuery = "判断路径"
        XCTAssertEqual(store.searchResults.count, 1)
        XCTAssertEqual(store.searchResults.first?.article.id, DemoContent.primaryArticle.id)

        store.searchQuery = "状态边界过大"
        let bodyResult = try XCTUnwrap(store.searchResults.first)
        XCTAssertEqual(bodyResult.article.title, "SwiftUI 性能优化指南")
        XCTAssertEqual(bodyResult.paragraphIndex, 0)
    }

    func testClearLibraryRemovesHighlightsAndNotes() {
        let store = DemoStore(initialScreen: .library)
        XCTAssertFalse(store.highlights.isEmpty)
        XCTAssertFalse(store.articleNote(for: DemoContent.primaryArticle.id).isEmpty)

        store.clearLibrary()

        XCTAssertTrue(store.highlights.isEmpty)
        XCTAssertTrue(store.articleNote(for: DemoContent.primaryArticle.id).isEmpty)
        XCTAssertTrue(store.searchResults.isEmpty)
    }
}
