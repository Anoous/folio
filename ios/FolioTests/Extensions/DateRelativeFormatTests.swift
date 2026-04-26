import XCTest
@testable import Folio

final class DateRelativeFormatTests: XCTestCase {

    let zhLocale = Locale(identifier: "zh-Hans")
    let enLocale = Locale(identifier: "en")
    let referenceDate = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 26, hour: 12, minute: 0, second: 0))!

    func testJustNow() {
        let date = referenceDate
        XCTAssertEqual(date.relativeFormatted(locale: zhLocale, relativeTo: referenceDate), "刚刚")
    }

    func testMinutesAgo() {
        let date = Date(timeInterval: -5 * 60, since: referenceDate)
        XCTAssertEqual(date.relativeFormatted(locale: zhLocale, relativeTo: referenceDate), "5分钟前")
    }

    func testHoursAgo() {
        let date = Date(timeInterval: -3 * 3600, since: referenceDate)
        XCTAssertEqual(date.relativeFormatted(locale: zhLocale, relativeTo: referenceDate), "3小时前")
    }

    func testYesterday() {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: referenceDate))!
        let date = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: yesterday)!
        XCTAssertEqual(date.relativeFormatted(locale: zhLocale, relativeTo: referenceDate), "昨天")
    }

    func testDaysAgo() {
        let date = Date(timeInterval: -3 * 86400, since: referenceDate)
        let result = date.relativeFormatted(locale: zhLocale, relativeTo: referenceDate)
        XCTAssertTrue(result.contains("天前"), "Expected '天前' but got: \(result)")
    }

    func testSpecificDate() {
        let date = Date(timeInterval: -30 * 86400, since: referenceDate)
        let result = date.relativeFormatted(locale: zhLocale, relativeTo: referenceDate)
        XCTAssertTrue(result.contains("月") && result.contains("日"),
                       "Expected date format with 月 and 日 but got: \(result)")
    }

    func testEnglishLocale() {
        let date = referenceDate
        XCTAssertEqual(date.relativeFormatted(locale: enLocale, relativeTo: referenceDate), "Just now")

        let fiveMin = Date(timeInterval: -5 * 60, since: referenceDate)
        XCTAssertEqual(fiveMin.relativeFormatted(locale: enLocale, relativeTo: referenceDate), "5m ago")

        let threeHours = Date(timeInterval: -3 * 3600, since: referenceDate)
        XCTAssertEqual(threeHours.relativeFormatted(locale: enLocale, relativeTo: referenceDate), "3h ago")
    }

    // MARK: - English Specific

    func testEnglish_yesterday() {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: referenceDate))!
        let date = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: yesterday)!
        XCTAssertEqual(date.relativeFormatted(locale: enLocale, relativeTo: referenceDate), "Yesterday")
    }

    func testEnglish_daysAgo() {
        let date = Date(timeInterval: -3 * 86400, since: referenceDate)
        let result = date.relativeFormatted(locale: enLocale, relativeTo: referenceDate)
        XCTAssertTrue(result.contains("d ago"), "Expected 'd ago' but got: \(result)")
    }

    // MARK: - Boundary Tests

    func testExactly60Seconds() {
        let date = Date(timeInterval: -60, since: referenceDate)
        let result = date.relativeFormatted(locale: zhLocale, relativeTo: referenceDate)
        XCTAssertEqual(result, "1分钟前")
    }

    func testExactly7Days() {
        let date = Date(timeInterval: -7 * 86400, since: referenceDate)
        let result = date.relativeFormatted(locale: zhLocale, relativeTo: referenceDate)
        // At exactly 7 days, days >= 7 so it should format as a specific date (M月d日), not "N天前"
        XCTAssertTrue(result.contains("月") && result.contains("日"),
                       "Expected date format with 月 and 日 but got: \(result)")
    }

    func testCrossYear() {
        let calendar = Calendar.current
        let lastYear = calendar.date(byAdding: .year, value: -1, to: referenceDate)!
        let result = lastYear.relativeFormatted(locale: zhLocale, relativeTo: referenceDate)
        // Previous year should include year in format (yyyy年M月d日)
        XCTAssertTrue(result.contains("年"), "Expected year in format but got: \(result)")
    }
}
