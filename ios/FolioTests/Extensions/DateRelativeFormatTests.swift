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

    // MARK: - English Specific

    func testEnglish_yesterday() {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date()))!
        let date = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: yesterday)!
        XCTAssertEqual(date.relativeFormatted(locale: enLocale), "Yesterday")
    }

    func testEnglish_daysAgo() {
        let date = Date(timeIntervalSinceNow: -3 * 86400)
        let result = date.relativeFormatted(locale: enLocale)
        XCTAssertTrue(result.contains("d ago"), "Expected 'd ago' but got: \(result)")
    }

    // MARK: - Boundary Tests

    func testExactly60Seconds() {
        let date = Date(timeIntervalSinceNow: -60)
        let result = date.relativeFormatted(locale: zhLocale)
        XCTAssertEqual(result, "1分钟前")
    }

    func testExactly7Days() {
        let date = Date(timeIntervalSinceNow: -7 * 86400)
        let result = date.relativeFormatted(locale: zhLocale)
        // At exactly 7 days, days >= 7 so it should format as a specific date (M月d日), not "N天前"
        XCTAssertTrue(result.contains("月") && result.contains("日"),
                       "Expected date format with 月 and 日 but got: \(result)")
    }

    func testCrossYear() {
        let calendar = Calendar.current
        let lastYear = calendar.date(byAdding: .year, value: -1, to: Date())!
        let result = lastYear.relativeFormatted(locale: zhLocale)
        // Previous year should include year in format (yyyy年M月d日)
        XCTAssertTrue(result.contains("年"), "Expected year in format but got: \(result)")
    }
}
