import XCTest
import SwiftData
@testable import Folio

final class ClipboardDetectorTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    @MainActor
    override func setUp() {
        super.setUp()
        container = try! DataManager.createInMemoryContainer()
        context = container.mainContext
        UserDefaults.standard.removeObject(forKey: "ignoredClipboardURLs")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "ignoredClipboardURLs")
        container = nil
        context = nil
        super.tearDown()
    }

    @MainActor
    func testDetectsURL_fromPasteboard() {
        UIPasteboard.general.url = URL(string: "https://example.com/clipboard")
        let detector = ClipboardDetector(context: context)
        detector.checkClipboard()
        XCTAssertNotNil(detector.detectedURL)
        XCTAssertEqual(detector.detectedURL?.absoluteString, "https://example.com/clipboard")
        UIPasteboard.general.items = []
    }

    @MainActor
    func testDetectsURL_fromPlainText() {
        UIPasteboard.general.string = "https://example.com/text-url"
        let detector = ClipboardDetector(context: context)
        detector.checkClipboard()
        XCTAssertNotNil(detector.detectedURL)
        UIPasteboard.general.items = []
    }

    @MainActor
    func testIgnoresNonURL() {
        UIPasteboard.general.string = "This is just some text"
        let detector = ClipboardDetector(context: context)
        detector.checkClipboard()
        XCTAssertFalse(detector.shouldShowPrompt)
        UIPasteboard.general.items = []
    }

    @MainActor
    func testAlreadySaved_noPrompt() throws {
        let a = Article(url: "https://example.com/saved")
        context.insert(a)
        try context.save()

        UIPasteboard.general.url = URL(string: "https://example.com/saved")
        let detector = ClipboardDetector(context: context)
        detector.checkClipboard()
        XCTAssertFalse(detector.shouldShowPrompt)
        UIPasteboard.general.items = []
    }

    @MainActor
    func testAlreadyIgnored_noPrompt() {
        UIPasteboard.general.url = URL(string: "https://example.com/ignored")
        let detector = ClipboardDetector(context: context)
        detector.detectedURL = URL(string: "https://example.com/ignored")
        detector.markAsIgnored()

        detector.checkClipboard()
        XCTAssertFalse(detector.shouldShowPrompt)
        UIPasteboard.general.items = []
    }

    @MainActor
    func testMarkAsIgnored() {
        let detector = ClipboardDetector(context: context)
        detector.detectedURL = URL(string: "https://example.com/to-ignore")
        detector.shouldShowPrompt = true

        detector.markAsIgnored()
        XCTAssertFalse(detector.shouldShowPrompt)
        XCTAssertNil(detector.detectedURL)

        let ignored = UserDefaults.standard.stringArray(forKey: "ignoredClipboardURLs") ?? []
        XCTAssertTrue(ignored.contains("https://example.com/to-ignore"))
    }

    @MainActor
    func testEmptyPasteboard_noPrompt() {
        UIPasteboard.general.items = []
        let detector = ClipboardDetector(context: context)
        detector.checkClipboard()
        XCTAssertFalse(detector.shouldShowPrompt)
    }
}
