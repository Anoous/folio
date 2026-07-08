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
        // #FAF8F2 => R:250/255≈0.980, G:248/255≈0.973, B:242/255≈0.949
        XCTAssertEqual(resolved.red, 250.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(resolved.green, 248.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(resolved.blue, 242.0 / 255.0, accuracy: 0.01)
    }

    func testAccentColor() {
        let resolved = Color.folio.accent.resolve(in: EnvironmentValues())
        // #0071E3 => R:0/255=0.000, G:113/255≈0.443, B:227/255≈0.890
        XCTAssertEqual(resolved.red, 0.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(resolved.green, 113.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(resolved.blue, 227.0 / 255.0, accuracy: 0.01)
    }

    func testPaperPaletteTextKeepsContrastInDarkMode() {
        var environment = EnvironmentValues()
        environment.colorScheme = .dark

        let background = FolioPaperPalette.background.resolve(in: environment)

        assertContrast(FolioPaperPalette.primaryText, on: background, in: environment, minimum: 7.0)
        assertContrast(FolioPaperPalette.secondaryText, on: background, in: environment, minimum: 4.5)
        assertContrast(FolioPaperPalette.tertiaryText, on: background, in: environment, minimum: 3.0)
        assertContrast(FolioPaperPalette.quaternaryText, on: background, in: environment, minimum: 3.0)
    }

    func testPaperPaletteSettingsSurfacesStayLightInDarkMode() {
        var environment = EnvironmentValues()
        environment.colorScheme = .dark

        let surfaces = [
            FolioPaperPalette.cardSurface,
            FolioPaperPalette.iconSurface,
            FolioPaperPalette.accentSurface,
        ]

        for surface in surfaces {
            XCTAssertGreaterThan(relativeLuminance(surface.resolve(in: environment)), 0.82)
        }
    }

    func testPaperPaletteControlsUseFreshTintInsteadOfNeutralGray() {
        var environment = EnvironmentValues()
        environment.colorScheme = .dark

        let control = FolioPaperPalette.controlSurface.resolve(in: environment)
        let icon = FolioPaperPalette.iconSurface.resolve(in: environment)
        let accent = FolioPaperPalette.accentSurface.resolve(in: environment)

        XCTAssertGreaterThan(relativeLuminance(control), 0.82)
        XCTAssertGreaterThan(control.green - control.red, 0.02)
        XCTAssertGreaterThan(icon.green - icon.red, 0.02)
        XCTAssertGreaterThan(accent.blue - accent.red, 0.04)
    }

    private func assertContrast(
        _ foreground: Color,
        on background: Color.Resolved,
        in environment: EnvironmentValues,
        minimum: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let ratio = contrastRatio(foreground.resolve(in: environment), background)
        XCTAssertGreaterThanOrEqual(ratio, minimum, file: file, line: line)
    }

    private func contrastRatio(_ foreground: Color.Resolved, _ background: Color.Resolved) -> Double {
        let bright = max(relativeLuminance(foreground), relativeLuminance(background))
        let dark = min(relativeLuminance(foreground), relativeLuminance(background))
        return (bright + 0.05) / (dark + 0.05)
    }

    private func relativeLuminance(_ color: Color.Resolved) -> Double {
        0.2126 * linearized(color.red)
            + 0.7152 * linearized(color.green)
            + 0.0722 * linearized(color.blue)
    }

    private func linearized(_ component: Float) -> Double {
        let value = Double(component)
        return value <= 0.03928
            ? value / 12.92
            : pow((value + 0.055) / 1.055, 2.4)
    }

}
