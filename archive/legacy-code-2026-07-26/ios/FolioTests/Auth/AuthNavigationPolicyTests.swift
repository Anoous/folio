import XCTest
@testable import Folio

final class AuthNavigationPolicyTests: XCTestCase {
    func testShouldDismissSignIn_whenAuthenticationCompletes() {
        XCTAssertTrue(AuthNavigationPolicy.shouldDismissSignIn(isAuthenticated: true))
    }

    func testShouldDismissSignIn_whenStillSignedOutOrUnknown() {
        XCTAssertFalse(AuthNavigationPolicy.shouldDismissSignIn(isAuthenticated: false))
        XCTAssertFalse(AuthNavigationPolicy.shouldDismissSignIn(isAuthenticated: nil))
    }
}
