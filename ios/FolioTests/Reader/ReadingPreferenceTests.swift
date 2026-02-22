import XCTest
@testable import Folio

final class ReadingPreferenceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "reader_fontSize")
        UserDefaults.standard.removeObject(forKey: "reader_lineSpacing")
        UserDefaults.standard.removeObject(forKey: "reader_theme")
        UserDefaults.standard.removeObject(forKey: "reader_fontFamily")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "reader_fontSize")
        UserDefaults.standard.removeObject(forKey: "reader_lineSpacing")
        UserDefaults.standard.removeObject(forKey: "reader_theme")
        UserDefaults.standard.removeObject(forKey: "reader_fontFamily")
        super.tearDown()
    }

    func testDefaultFontSize() {
        let fontSize = UserDefaults.standard.double(forKey: "reader_fontSize")
        // Should be 0 (unset) which means default 17
        XCTAssertEqual(fontSize, 0, "Unset font size should be 0 (default applies 17)")
    }

    func testDefaultLineSpacing() {
        let spacing = UserDefaults.standard.double(forKey: "reader_lineSpacing")
        XCTAssertEqual(spacing, 0, "Unset line spacing should be 0 (default applies 11.9)")
    }

    func testDefaultFont() {
        let font = UserDefaults.standard.string(forKey: "reader_fontFamily")
        XCTAssertNil(font, "Default font should be nil (system default)")
    }

    func testPersistFontSize() {
        UserDefaults.standard.set(19.0, forKey: "reader_fontSize")
        let stored = UserDefaults.standard.double(forKey: "reader_fontSize")
        XCTAssertEqual(stored, 19.0)
    }

    func testPersistLineSpacing() {
        UserDefaults.standard.set(1.8, forKey: "reader_lineSpacing")
        let stored = UserDefaults.standard.double(forKey: "reader_lineSpacing")
        XCTAssertEqual(stored, 1.8)
    }

    func testPersistTheme() {
        UserDefaults.standard.set("dark", forKey: "reader_theme")
        let stored = UserDefaults.standard.string(forKey: "reader_theme")
        XCTAssertEqual(stored, "dark")
    }

    // MARK: - ReadingTheme Tests

    func testReadingTheme_allCasesRawValues() {
        XCTAssertEqual(ReadingTheme.system.rawValue, "system")
        XCTAssertEqual(ReadingTheme.light.rawValue, "light")
        XCTAssertEqual(ReadingTheme.dark.rawValue, "dark")
        XCTAssertEqual(ReadingTheme.sepia.rawValue, "sepia")
    }

    func testReadingTheme_displayNames() {
        for theme in ReadingTheme.allCases {
            XCTAssertFalse(theme.displayName.isEmpty, "\(theme) should have a non-empty display name")
        }
    }

    // MARK: - ReadingFontFamily Tests

    func testReadingFontFamily_allCasesRawValues() {
        XCTAssertEqual(ReadingFontFamily.notoSerif.rawValue, "noto_serif")
        XCTAssertEqual(ReadingFontFamily.system.rawValue, "system")
        XCTAssertEqual(ReadingFontFamily.serif.rawValue, "serif")
    }

    func testReadingFontFamily_displayNames() {
        XCTAssertEqual(ReadingFontFamily.notoSerif.displayName, "Noto Serif SC")
        XCTAssertEqual(ReadingFontFamily.system.displayName, "System (SF Pro)")
        XCTAssertEqual(ReadingFontFamily.serif.displayName, "Georgia")
    }

    func testReadingFontFamily_fontSizeMethod() {
        // Verify font(size:) doesn't crash for all cases
        for family in ReadingFontFamily.allCases {
            let font = family.font(size: 17)
            XCTAssertNotNil(font, "\(family) font(size:) should return a valid Font")
        }
    }

    func testDefaultValues_matchSource() {
        // Verify defaults match what ReadingPreferenceView uses
        XCTAssertEqual(ReadingTheme.system.rawValue, "system")
        XCTAssertEqual(ReadingFontFamily.notoSerif.rawValue, "noto_serif")
        // The @AppStorage defaults from ReadingPreferenceView are:
        // fontSize=17, lineSpacing=11.9, theme="system", fontFamily="noto_serif"
        XCTAssertEqual(ReadingTheme(rawValue: "system"), .system)
        XCTAssertEqual(ReadingFontFamily(rawValue: "noto_serif"), .notoSerif)
    }
}
