import XCTest
import SwiftUI
@testable import Folio

final class UIComponentTests: XCTestCase {

    func testTagChipRendersWithText() {
        let chip = TagChip(text: "Swift")
        XCTAssertNotNil(chip)
        XCTAssertEqual(chip.text, "Swift")
    }

    func testStatusBadgeAllStates() {
        let states: [ContentStatus] = [.unread, .processing, .failed, .offline]
        for state in states {
            let badge = StatusBadge(status: state)
            XCTAssertNotNil(badge)
            XCTAssertEqual(badge.status, state)
        }
    }

    func testFolioButtonStyles() {
        let primary = FolioButton(title: "OK", style: .primary) {}
        XCTAssertNotNil(primary)
        XCTAssertEqual(primary.title, "OK")
        XCTAssertEqual(primary.style, .primary)

        let secondary = FolioButton(title: "Cancel", style: .secondary) {}
        XCTAssertNotNil(secondary)
        XCTAssertEqual(secondary.style, .secondary)
    }

    func testToastViewAppears() {
        let toast = ToastView(message: "Saved!", icon: "checkmark")
        XCTAssertNotNil(toast)
        XCTAssertEqual(toast.message, "Saved!")
        XCTAssertEqual(toast.icon, "checkmark")
    }
}
