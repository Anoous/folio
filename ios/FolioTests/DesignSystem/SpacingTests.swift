import XCTest
@testable import Folio

final class SpacingTests: XCTestCase {

    func testSpacingValues() {
        XCTAssertEqual(Spacing.xxs, 4)
        XCTAssertEqual(Spacing.xs, 8)
        XCTAssertEqual(Spacing.sm, 12)
        XCTAssertEqual(Spacing.md, 16)
        XCTAssertEqual(Spacing.lg, 24)
        XCTAssertEqual(Spacing.xl, 32)
    }

    func testScreenPadding() {
        XCTAssertEqual(Spacing.screenPadding, 16)
    }

    func testCornerRadiusValues() {
        XCTAssertEqual(CornerRadius.small, 4)
        XCTAssertEqual(CornerRadius.medium, 8)
        XCTAssertEqual(CornerRadius.large, 12)
    }
}
