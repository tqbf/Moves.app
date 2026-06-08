import XCTest
@testable import Moves

final class TimeLogServiceTests: XCTestCase {

  // MARK: - weekStart

  func testWeekStartReturnsMondayForMidWeekDate() {
    // 2026-06-08 is a Monday — week_start should equal the same day.
    var comps = DateComponents()
    comps.year = 2026; comps.month = 6; comps.day = 8
    var cal = Calendar(identifier: .iso8601)
    cal.timeZone = TimeZone(secondsFromGMT: 0)!
    cal.firstWeekday = 2
    let date = cal.date(from: comps)!
    XCTAssertEqual(TimeLogService.weekStart(for: date, calendar: cal), "2026-06-08")
  }

  func testWeekStartReturnsPriorMondayForSunday() {
    // 2026-06-14 is a Sunday — week_start should be the Monday before it
    // (2026-06-08).
    var comps = DateComponents()
    comps.year = 2026; comps.month = 6; comps.day = 14
    var cal = Calendar(identifier: .iso8601)
    cal.timeZone = TimeZone(secondsFromGMT: 0)!
    cal.firstWeekday = 2
    let date = cal.date(from: comps)!
    XCTAssertEqual(TimeLogService.weekStart(for: date, calendar: cal), "2026-06-08")
  }

  func testWeekStartForTuesdayResolvesToMonday() {
    var comps = DateComponents()
    comps.year = 2026; comps.month = 6; comps.day = 9
    var cal = Calendar(identifier: .iso8601)
    cal.timeZone = TimeZone(secondsFromGMT: 0)!
    cal.firstWeekday = 2
    let date = cal.date(from: comps)!
    XCTAssertEqual(TimeLogService.weekStart(for: date, calendar: cal), "2026-06-08")
  }

  // MARK: - aggregate

  func testAggregateSumsMinutesPerThread() {
    let entries: [TimeLogEntry] = [
      .init(threadId: "a", weekStart: "2026-06-08", roughMinutes: 30),
      .init(threadId: "a", weekStart: "2026-06-08", roughMinutes: 60),
      .init(threadId: "b", weekStart: "2026-06-08", roughMinutes: 15),
    ]
    let result = TimeLogService.aggregate(entries: entries)
    XCTAssertEqual(result.count, 2)
    // Sorted by descending total minutes.
    XCTAssertEqual(result[0].threadId, "a")
    XCTAssertEqual(result[0].totalMinutes, 90)
    XCTAssertEqual(result[1].threadId, "b")
    XCTAssertEqual(result[1].totalMinutes, 15)
  }

  func testAggregateEmptyReturnsEmpty() {
    XCTAssertEqual(TimeLogService.aggregate(entries: []).count, 0)
  }

  func testAggregateTiesBreakOnThreadId() {
    let entries: [TimeLogEntry] = [
      .init(threadId: "z", weekStart: "w", roughMinutes: 30),
      .init(threadId: "a", weekStart: "w", roughMinutes: 30),
    ]
    let result = TimeLogService.aggregate(entries: entries)
    XCTAssertEqual(result.map(\.threadId), ["a", "z"])
  }

  // MARK: - roughBucketLabel

  func testRoughBucketLabelUnderHourRoundsToFifteen() {
    XCTAssertEqual(TimeLogService.roughBucketLabel(0), "0m")
    XCTAssertEqual(TimeLogService.roughBucketLabel(15), "~15m")
    XCTAssertEqual(TimeLogService.roughBucketLabel(30), "~30m")
    XCTAssertEqual(TimeLogService.roughBucketLabel(45), "~45m")
    XCTAssertEqual(TimeLogService.roughBucketLabel(20), "~30m") // 20 rounds up to 30
  }

  func testRoughBucketLabelHourMultiples() {
    XCTAssertEqual(TimeLogService.roughBucketLabel(60), "~1h")
    XCTAssertEqual(TimeLogService.roughBucketLabel(120), "~2h")
    XCTAssertEqual(TimeLogService.roughBucketLabel(180), "~3h")
  }

  func testRoughBucketLabelHourPlusMinutes() {
    XCTAssertEqual(TimeLogService.roughBucketLabel(75), "~1h 15m")
    XCTAssertEqual(TimeLogService.roughBucketLabel(90), "~1h 30m")
    XCTAssertEqual(TimeLogService.roughBucketLabel(135), "~2h 15m")
  }
}
