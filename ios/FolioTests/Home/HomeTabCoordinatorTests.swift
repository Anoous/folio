import XCTest
@testable import Folio

@MainActor
final class HomeTabCoordinatorTests: XCTestCase {
    func testInitialSelectionIsToday() {
        let coordinator = HomeTabCoordinator()

        XCTAssertEqual(coordinator.selection, .today)
        XCTAssertNil(coordinator.focusRequest)
    }

    func testSelectingTabsUpdatesSelectionWithoutFocusSideEffects() {
        let coordinator = HomeTabCoordinator()

        coordinator.select(.library)
        XCTAssertEqual(coordinator.selection, .library)
        XCTAssertNil(coordinator.focusRequest)

        coordinator.select(.ask)
        XCTAssertEqual(coordinator.selection, .ask)
        XCTAssertNil(coordinator.focusRequest)

        coordinator.select(.me)
        XCTAssertEqual(coordinator.selection, .me)
        XCTAssertNil(coordinator.focusRequest)
    }

    func testOpenLibrarySearchSelectsLibraryAndRequestsSearchFocus() {
        let coordinator = HomeTabCoordinator()

        coordinator.openLibrarySearch()

        XCTAssertEqual(coordinator.selection, .library)
        XCTAssertEqual(coordinator.focusRequest?.target, .librarySearch)
    }

    func testOpenAskSelectsAskAndRequestsAskFocus() {
        let coordinator = HomeTabCoordinator()

        coordinator.openAsk()

        XCTAssertEqual(coordinator.selection, .ask)
        XCTAssertEqual(coordinator.focusRequest?.target, .askInput)
    }
}
