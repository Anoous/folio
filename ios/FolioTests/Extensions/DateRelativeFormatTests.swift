import XCTest
@testable import Folio

final class DateRelativeFormatTests: XCTestCase {

    let zhLocale = Locale(identifier: "zh-Hans")
    let enLocale = Locale(identifier: "en")

    func testJustNow() {
        let date = Date()
        XCTAssertEqual(date.relativeFormatted(locale: zhLocale), "刚刚")
    }

    func testMinutesAgo() {
        let date = Date(timeIntervalSinceNow: -5 * 60)
        XCTAssertEqual(date.relativeFormatted(locale: zhLocale), "5分钟前")
    }

    func testHoursAgo() {
        let date = Date(timeIntervalSinceNow: -3 * 3600)
        XCTAssertEqual(date.relativeFormatted(locale: zhLocale), "3小时前")
    }

    func testYesterday() {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date()))!
        let date = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: yesterday)!
        XCTAssertEqual(date.relativeFormatted(locale: zhLocale), "昨天")
    }

    func testDaysAgo() {
        let date = Date(timeIntervalSinceNow: -3 * 86400)
        let result = date.relativeFormatted(locale: zhLocale)
        XCTAssertTrue(result.contains("天前"), "Expected '天前' but got: \(result)")
    }

    func testSpecificDate() {
        let date = Date(timeIntervalSinceNow: -30 * 86400)
        let result = date.relativeFormatted(locale: zhLocale)
        XCTAssertTrue(result.contains("月") && result.contains("日"),
                       "Expected date format with 月 and 日 but got: \(result)")
    }

    func testEnglishLocale() {
        let date = Date()
        XCTAssertEqual(date.relativeFormatted(locale: enLocale), "Just now")

        let fiveMin = Date(timeIntervalSinceNow: -5 * 60)
        XCTAssertEqual(fiveMin.relativeFormatted(locale: enLocale), "5m ago")

        let threeHours = Date(timeIntervalSinceNow: -3 * 3600)
        XCTAssertEqual(threeHours.relativeFormatted(locale: enLocale), "3h ago")
    }
}
