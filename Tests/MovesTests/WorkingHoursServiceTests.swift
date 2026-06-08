import XCTest
@testable import Moves

/// Boundary tests for the §6 working-hours predicate and visibility filter.
final class WorkingHoursServiceTests: XCTestCase {

  // MARK: - Helpers

  /// Build a `Date` for a UTC weekday/hour/minute. Returns a deterministic
  /// 2026 anchor — the test calendar is ISO-8601 (Monday=1), so passing
  /// `weekday = 1` lands on Monday.
  private func makeDate(weekday: Int, hour: Int, minute: Int = 0) -> Date {
    var calendar = Calendar(identifier: .iso8601)
    calendar.firstWeekday = 2
    calendar.timeZone = TimeZone(identifier: "UTC")!
    var components = DateComponents()
    components.yearForWeekOfYear = 2026
    components.weekOfYear = 24
    // DateComponents.weekday is 1 = Sunday, ..., 7 = Saturday — convert
    // from our ISO-1-Mon input.
    components.weekday = (weekday % 7) + 1
    components.hour = hour
    components.minute = minute
    return calendar.date(from: components)!
  }

  private func utcCalendar() -> Calendar {
    var c = Calendar(identifier: .iso8601)
    c.firstWeekday = 2
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
  }

  // MARK: - isInside boundaries

  func testStartOfWindowIsInside() {
    let hours = WorkingHours(days: [1, 2, 3, 4, 5], startMinute: 9 * 60, endMinute: 17 * 60)
    let mondayNine = makeDate(weekday: 1, hour: 9, minute: 0)
    XCTAssertTrue(WorkingHoursService.isInside(date: mondayNine, hours: hours, calendar: utcCalendar()))
  }

  func testOneMinuteBeforeStartIsOutside() {
    let hours = WorkingHours(days: [1, 2, 3, 4, 5], startMinute: 9 * 60, endMinute: 17 * 60)
    let mondayEightFiftyNine = makeDate(weekday: 1, hour: 8, minute: 59)
    XCTAssertFalse(WorkingHoursService.isInside(date: mondayEightFiftyNine, hours: hours, calendar: utcCalendar()))
  }

  func testEndOfWindowIsExclusive() {
    let hours = WorkingHours(days: [1, 2, 3, 4, 5], startMinute: 9 * 60, endMinute: 17 * 60)
    let mondayFive = makeDate(weekday: 1, hour: 17, minute: 0)
    XCTAssertFalse(WorkingHoursService.isInside(date: mondayFive, hours: hours, calendar: utcCalendar()),
                   "end minute is exclusive — 17:00 with end=17:00 should be outside")
  }

  func testOneMinuteBeforeEndIsInside() {
    let hours = WorkingHours(days: [1, 2, 3, 4, 5], startMinute: 9 * 60, endMinute: 17 * 60)
    let mondayFourFiftyNine = makeDate(weekday: 1, hour: 16, minute: 59)
    XCTAssertTrue(WorkingHoursService.isInside(date: mondayFourFiftyNine, hours: hours, calendar: utcCalendar()))
  }

  func testSaturdayWithMonFriHoursIsOutside() {
    let hours = WorkingHours(days: [1, 2, 3, 4, 5], startMinute: 9 * 60, endMinute: 17 * 60)
    let saturdayNoon = makeDate(weekday: 6, hour: 12)
    XCTAssertFalse(WorkingHoursService.isInside(date: saturdayNoon, hours: hours, calendar: utcCalendar()))
  }

  func testSundayWithMonFriHoursIsOutside() {
    let hours = WorkingHours(days: [1, 2, 3, 4, 5], startMinute: 9 * 60, endMinute: 17 * 60)
    let sundayNoon = makeDate(weekday: 7, hour: 12)
    XCTAssertFalse(WorkingHoursService.isInside(date: sundayNoon, hours: hours, calendar: utcCalendar()))
  }

  func testEmptyDaysMeansNeverInside() {
    let hours = WorkingHours(days: [], startMinute: 0, endMinute: 1440)
    XCTAssertFalse(WorkingHoursService.isInside(date: makeDate(weekday: 1, hour: 12), hours: hours, calendar: utcCalendar()))
  }

  func testZeroLengthWindowIsNeverInside() {
    let hours = WorkingHours(days: [1, 2, 3, 4, 5], startMinute: 12 * 60, endMinute: 12 * 60)
    XCTAssertFalse(WorkingHoursService.isInside(date: makeDate(weekday: 1, hour: 12), hours: hours, calendar: utcCalendar()))
  }

  // MARK: - Midnight wrap

  func testMidnightWrapWindowAtNightIsInside() {
    // 22:00–06:00 wraps midnight.
    let hours = WorkingHours(days: [1, 2, 3, 4, 5], startMinute: 22 * 60, endMinute: 6 * 60)
    let mondayTen = makeDate(weekday: 1, hour: 22, minute: 30)
    XCTAssertTrue(WorkingHoursService.isInside(date: mondayTen, hours: hours, calendar: utcCalendar()))
  }

  func testMidnightWrapWindowEarlyMorningIsInside() {
    let hours = WorkingHours(days: [1, 2, 3, 4, 5], startMinute: 22 * 60, endMinute: 6 * 60)
    let mondayThree = makeDate(weekday: 1, hour: 3)
    XCTAssertTrue(WorkingHoursService.isInside(date: mondayThree, hours: hours, calendar: utcCalendar()))
  }

  func testMidnightWrapWindowAtSixIsOutside() {
    let hours = WorkingHours(days: [1, 2, 3, 4, 5], startMinute: 22 * 60, endMinute: 6 * 60)
    let mondaySix = makeDate(weekday: 1, hour: 6, minute: 0)
    XCTAssertFalse(WorkingHoursService.isInside(date: mondaySix, hours: hours, calendar: utcCalendar()),
                   "midnight-wrap end is also exclusive")
  }

  func testMidnightWrapMiddayIsOutside() {
    let hours = WorkingHours(days: [1, 2, 3, 4, 5], startMinute: 22 * 60, endMinute: 6 * 60)
    let mondayNoon = makeDate(weekday: 1, hour: 12)
    XCTAssertFalse(WorkingHoursService.isInside(date: mondayNoon, hours: hours, calendar: utcCalendar()))
  }

  // MARK: - Classification (§6)

  func testNormalVisibilityAlwaysVisible() {
    XCTAssertEqual(WorkingHoursService.classify(visibility: .normal, isWorkTime: true, hasDeadlineItem: false), .visible)
    XCTAssertEqual(WorkingHoursService.classify(visibility: .normal, isWorkTime: false, hasDeadlineItem: false), .visible)
  }

  func testHideWorkHidesDuringWorkWithoutDeadline() {
    XCTAssertEqual(WorkingHoursService.classify(visibility: .hideWork, isWorkTime: true, hasDeadlineItem: false), .hidden)
  }

  func testHideWorkVisibleDuringWorkIfDeadlineBearing() {
    XCTAssertEqual(WorkingHoursService.classify(visibility: .hideWork, isWorkTime: true, hasDeadlineItem: true), .visible,
                   "§6 carve-out: deadline-bearing threads stay visible even when hide_during_work")
  }

  func testHideWorkVisibleOutsideWork() {
    XCTAssertEqual(WorkingHoursService.classify(visibility: .hideWork, isWorkTime: false, hasDeadlineItem: false), .visible)
  }

  func testDownweightWorkDeemphasizedOnlyDuringWork() {
    XCTAssertEqual(WorkingHoursService.classify(visibility: .downweightWork, isWorkTime: true, hasDeadlineItem: false), .deemphasized)
    XCTAssertEqual(WorkingHoursService.classify(visibility: .downweightWork, isWorkTime: false, hasDeadlineItem: false), .visible)
  }

  func testOnlyWorkVisibleDuringWorkHiddenOtherwise() {
    XCTAssertEqual(WorkingHoursService.classify(visibility: .onlyWork, isWorkTime: true, hasDeadlineItem: false), .visible)
    XCTAssertEqual(WorkingHoursService.classify(visibility: .onlyWork, isWorkTime: false, hasDeadlineItem: false), .hidden)
  }

  func testOnlyWorkVisibleOutsideWorkIfDeadlineBearing() {
    XCTAssertEqual(WorkingHoursService.classify(visibility: .onlyWork, isWorkTime: false, hasDeadlineItem: true), .visible,
                   "§6 carve-out: deadline-bearing threads stay visible even when only_during_work")
  }

  // MARK: - Filter

  func testFilterPartitionsThreadsByClassification() {
    func makeAvail(title: String, visibility: ThreadVisibility) -> AvailableThread {
      let t = Thread(title: title, visibility: visibility, breadcrumb: "next")
      return AvailableThread(thread: t, move: .init(text: "next", source: .breadcrumb))
    }
    let rows = [
      makeAvail(title: "Normal", visibility: .normal),
      makeAvail(title: "Hidden", visibility: .hideWork),
      makeAvail(title: "Quieter", visibility: .downweightWork),
      makeAvail(title: "OnlyWork", visibility: .onlyWork),
    ]
    let result = WorkingHoursService.filter(available: rows, isWorkTime: true, hasDeadline: { _ in false })
    XCTAssertEqual(result.visible.map(\.thread.title), ["Normal", "OnlyWork"])
    XCTAssertEqual(result.deemphasized.map(\.thread.title), ["Quieter"])
  }

  // MARK: - Codable round-trip

  func testWorkingHoursEncodeDecodeRoundTrip() {
    let hours = WorkingHours(days: [1, 3, 5], startMinute: 9 * 60 + 15, endMinute: 17 * 60 + 30)
    let encoded = hours.encodedJSON()
    let decoded = WorkingHours.decodedJSON(encoded)
    XCTAssertEqual(decoded, hours)
  }

  func testWorkingHoursMalformedJSONReturnsNil() {
    XCTAssertNil(WorkingHours.decodedJSON("not json"))
    XCTAssertNil(WorkingHours.decodedJSON("{}"))
    XCTAssertNil(WorkingHours.decodedJSON(#"{"days":[1],"start":"25:00","end":"17:30"}"#))
  }
}
