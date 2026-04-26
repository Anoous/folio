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
            .folio.codeBackground,
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
        // #0071E3 => R:0/255=0.000, G:113/255≈0.443, B:227/255≈0.890
        XCTAssertEqual(resolved.red, 0.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(resolved.green, 113.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(resolved.blue, 227.0 / 255.0, accuracy: 0.01)
    }

}
