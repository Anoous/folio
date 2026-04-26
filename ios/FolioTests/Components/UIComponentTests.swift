import XCTest
import SwiftUI
@testable import Folio

final class UIComponentTests: XCTestCase {

    func testTagChipRendersWithText() {
        let chip = TagChip(text: "Swift")
        XCTAssertNotNil(chip)
        XCTAssertEqual(chip.text, "Swift")
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

    func testHomeQuickCaptureViewConstructs() {
        let view = HomeQuickCaptureView(
            onPasteURL: { _ in },
            onTextTap: {},
            onPhotoSelected: { _ in }
        )

        XCTAssertNotNil(view)
    }

    func testEchoCardViewConstructs() {
        let card = EchoCardData(
            question: "还记得抽象层常会怎样吗？",
            answer: "抽象层常会泄漏，需要了解底层细节。",
            sourceContext: "来自《Essays on programming I think about a lot》",
            articleTitle: "Essays on programming I think about a lot",
            intervalDays: 7
        )
        let view = EchoCardView(card: card) { _, completion in
            completion(nil)
        }

        XCTAssertNotNil(view)
    }
}
