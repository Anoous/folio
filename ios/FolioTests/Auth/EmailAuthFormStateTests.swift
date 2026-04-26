import XCTest
@testable import Folio

final class EmailAuthFormStateTests: XCTestCase {
    func testEmailValidation_acceptsTrimmedEmailWithDomain() {
        var form = EmailAuthFormState()
        form.email = "  reader@example.com  "

        XCTAssertEqual(form.normalizedEmail, "reader@example.com")
        XCTAssertTrue(form.isEmailValid)
        XCTAssertTrue(form.canSendCode)
        XCTAssertNil(form.emailValidationMessage)
    }

    func testEmailValidation_rejectsMalformedEmail() {
        let invalidEmails = [
            "",
            "reader",
            "reader@",
            "@example.com",
            "reader@example",
            "reader@.com",
            "reader@example.",
            "reader @example.com"
        ]

        for email in invalidEmails {
            var form = EmailAuthFormState()
            form.email = email

            XCTAssertFalse(form.isEmailValid, "\(email) should be invalid")
            XCTAssertFalse(form.canSendCode, "\(email) should not be sendable")
        }
    }

    func testEmailValidationMessage_onlyShowsForNonEmptyInvalidEmail() {
        var form = EmailAuthFormState()
        XCTAssertNil(form.emailValidationMessage)

        form.email = "reader"
        XCTAssertEqual(form.emailValidationMessage, "请输入有效的邮箱地址。")
    }

    func testSanitizedCode_keepsOnlyFirstSixDigits() {
        XCTAssertEqual(EmailAuthFormState.sanitizedCode("12a 34-56789"), "123456")
    }

    func testMoveToCodeStep_clearsCodeAndStartsCooldown() {
        var form = EmailAuthFormState()
        form.email = "reader@example.com"
        form.code = "123456"

        form.moveToCodeStep()

        XCTAssertEqual(form.step, .code)
        XCTAssertEqual(form.code, "")
        XCTAssertEqual(form.cooldownRemaining, 60)
        XCTAssertFalse(form.canSendCode)
    }

    func testCooldownTickStopsAtZero() {
        var form = EmailAuthFormState()
        form.startCooldown(seconds: 1)

        form.tickCooldown()
        form.tickCooldown()

        XCTAssertEqual(form.cooldownRemaining, 0)
    }
}
