import XCTest
@testable import Folio

final class TimeGroupingTests: XCTestCase {

    func testGroupArticlesByTime() {
        let calendar = Calendar.current
        let now = Date()

        let dates = [
            now,
            calendar.date(byAdding: .hour, value: -25, to: now)!,
            calendar.date(byAdding: .day, value: -3, to: now)!,
            calendar.date(byAdding: .day, value: -10, to: now)!,
            calendar.date(byAdding: .month, value: -2, to: now)!,
        ]
        let groups = TimeGroup.group(dates: dates, calendar: calendar, now: now)

        XCTAssertGreaterThanOrEqual(groups.count, 3)
        XCTAssertEqual(groups[0].group, .today)
    }

    func testEmptyDatesReturnsEmpty() {
        let groups = TimeGroup.group(dates: [], now: .now)
        XCTAssertTrue(groups.isEmpty)
    }

    func testSingleDateGroupsCorrectly() {
        let now = Date()
        let groups = TimeGroup.group(dates: [now], now: now)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].group, .today)
        XCTAssertEqual(groups[0].indices, [0])
    }
}
