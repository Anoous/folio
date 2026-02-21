import XCTest
import SwiftUI
@testable import Folio

final class ColorTests: XCTestCase {

    func testAllColorsExist() {
        let colors: [Color] = [
            .folio.background,
            .folio.cardBackground,
            .folio.textPrimary,
            .folio.textSecondary,
            .folio.textTertiary,
            .folio.separator,
            .folio.accent,
            .folio.link,
            .folio.unread,
            .folio.success,
            .folio.warning,
            .folio.error,
            .folio.tagBackground,
            .folio.tagText,
            .folio.highlightYellow,
            .folio.highlightGreen,
            .folio.highlightBlue,
            .folio.highlightRed,
        ]
        for color in colors {
            XCTAssertNotNil(color)
        }
    }

    func testLightDarkVariants() {
        let lightBg = Color.folio.background.resolve(in: EnvironmentValues())
        var darkEnv = EnvironmentValues()
        darkEnv.colorScheme = .dark
        let darkBg = Color.folio.background.resolve(in: darkEnv)
        XCTAssertNotEqual(
            lightBg.description,
            darkBg.description,
            "Light and Dark background colors should differ"
        )
    }

    func testBackgroundColor() {
        let resolved = Color.folio.background.resolve(in: EnvironmentValues())
        // #FAFAF8 => R:250/255≈0.980, G:250/255≈0.980, B:248/255≈0.973
        XCTAssertEqual(resolved.red, 250.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(resolved.green, 250.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(resolved.blue, 248.0 / 255.0, accuracy: 0.01)
    }

    func testAccentColor() {
        let resolved = Color.folio.accent.resolve(in: EnvironmentValues())
        // #2C2C2C => R:44/255≈0.173, G:44/255≈0.173, B:44/255≈0.173
        XCTAssertEqual(resolved.red, 44.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(resolved.green, 44.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(resolved.blue, 44.0 / 255.0, accuracy: 0.01)
    }

    func testHighlightColors() {
        let highlights: [Color] = [
            .folio.highlightYellow,
            .folio.highlightGreen,
            .folio.highlightBlue,
            .folio.highlightRed,
        ]
        for highlight in highlights {
            XCTAssertNotNil(highlight)
        }
    }
}
