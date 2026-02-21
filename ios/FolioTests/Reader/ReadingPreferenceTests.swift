import XCTest
@testable import Folio

final class ReadingPreferenceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "readerFontSize")
        UserDefaults.standard.removeObject(forKey: "readerLineSpacing")
        UserDefaults.standard.removeObject(forKey: "readerTheme")
        UserDefaults.standard.removeObject(forKey: "readerFont")
    }

    func testDefaultFontSize() {
        let fontSize = UserDefaults.standard.double(forKey: "readerFontSize")
        // Should be 0 (unset) which means default 17
        XCTAssertEqual(fontSize, 0, "Unset font size should be 0 (default applies 17)")
    }

    func testDefaultLineSpacing() {
        let spacing = UserDefaults.standard.double(forKey: "readerLineSpacing")
        XCTAssertEqual(spacing, 0, "Unset line spacing should be 0 (default applies 1.6)")
    }

    func testDefaultFont() {
        let font = UserDefaults.standard.string(forKey: "readerFont")
        XCTAssertNil(font, "Default font should be nil (system default)")
    }

    func testPersistFontSize() {
        UserDefaults.standard.set(19.0, forKey: "readerFontSize")
        let stored = UserDefaults.standard.double(forKey: "readerFontSize")
        XCTAssertEqual(stored, 19.0)
    }

    func testPersistLineSpacing() {
        UserDefaults.standard.set(1.8, forKey: "readerLineSpacing")
        let stored = UserDefaults.standard.double(forKey: "readerLineSpacing")
        XCTAssertEqual(stored, 1.8)
    }

    func testPersistTheme() {
        UserDefaults.standard.set("dark", forKey: "readerTheme")
        let stored = UserDefaults.standard.string(forKey: "readerTheme")
        XCTAssertEqual(stored, "dark")
    }
}
