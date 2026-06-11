import XCTest
@testable import Moves

/// Every form in INITIAL-PLAN.md §15 gets a test here. The parser is pure —
/// `now` is supplied explicitly and the calendar is fixed to UTC with a
/// Sunday-start week so dates are stable across CI hosts.
final class CaptureParserTests: XCTestCase {

  // MARK: - Test fixtures

  /// 2026-06-08 14:30:00 UTC — a Monday afternoon. All relative tests use
  /// this as `now`.
  private let now: Date = {
    var components = DateComponents()
    components.year = 2026
    components.month = 6
    components.day = 8
    components.hour = 14
    components.minute = 30
    components.second = 0
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal.date(from: components)!
  }()

  private var calendar: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal
  }()

  private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    components.second = 0
    return calendar.date(from: components)!
  }

  private func parse(_ input: String) -> ParsedCapture {
    CaptureParser.parse(input, now: now, calendar: calendar)
  }

  // MARK: - §15 examples (the canonical DOD set)

  func testCallSarahAtFour() {
    // §15 worked example: `call Sarah at 4`
    // Now is 14:30; next 4:00 is 16:00 today (4pm is sooner than 4am tomorrow).
    let result = parse("call Sarah at 4")
    XCTAssertEqual(result.title, "call Sarah")
    XCTAssertEqual(result.dueAt, date(2026, 6, 8, 16, 0))
    XCTAssertEqual(result.dueKind, .datetime)
    XCTAssertEqual(result.interruptionKind, .hard)
  }

  func testPullRiceIn18m() {
    // DOD: `pull rice in 18m` → hard, due_at ≈ now+18m.
    let result = parse("pull rice in 18m")
    XCTAssertEqual(result.title, "pull rice")
    XCTAssertEqual(result.dueAt, now.addingTimeInterval(18 * 60))
    XCTAssertEqual(result.dueKind, .datetime)
    XCTAssertEqual(result.interruptionKind, .hard)
  }

  func testSubmitCalcHomeworkFridayFivePM() {
    // DOD: `submit calc homework Friday 5pm` → soft, due_at next Friday 17:00.
    // Now is Monday 2026-06-08. Next Friday is 2026-06-12.
    let result = parse("submit calc homework Friday 5pm")
    XCTAssertEqual(result.title, "submit calc homework")
    XCTAssertEqual(result.dueAt, date(2026, 6, 12, 17, 0))
    XCTAssertEqual(result.dueKind, .datetime)
    XCTAssertEqual(result.interruptionKind, .soft)
  }

  func testSubmitCalcHomeworkDueFridayFivePM() {
    // §15 worked example: `submit calc homework due Friday 5pm` → soft.
    let result = parse("submit calc homework due Friday 5pm")
    XCTAssertEqual(result.title, "submit calc homework")
    XCTAssertEqual(result.dueAt, date(2026, 6, 12, 17, 0))
    XCTAssertEqual(result.dueKind, .datetime)
    XCTAssertEqual(result.interruptionKind, .soft)
  }

  func testBuyWalnutDowels() {
    // DOD: `buy walnut dowels` → no due_at, interruption .none.
    let result = parse("buy walnut dowels")
    XCTAssertEqual(result.title, "buy walnut dowels")
    XCTAssertNil(result.dueAt)
    XCTAssertEqual(result.dueKind, .none)
    XCTAssertEqual(result.interruptionKind, .none)
  }

  // MARK: - `in <N>m` / `in <N>h`

  func testInTenMinutes() {
    let result = parse("step away in 10m")
    XCTAssertEqual(result.title, "step away")
    XCTAssertEqual(result.dueAt, now.addingTimeInterval(10 * 60))
    XCTAssertEqual(result.dueKind, .datetime)
    XCTAssertEqual(result.interruptionKind, .hard)
  }

  func testInFortyFiveMinutes() {
    let result = parse("check glue-up in 45m")
    XCTAssertEqual(result.title, "check glue-up")
    XCTAssertEqual(result.dueAt, now.addingTimeInterval(45 * 60))
    XCTAssertEqual(result.dueKind, .datetime)
    XCTAssertEqual(result.interruptionKind, .hard)
  }

  func testInTwoHours() {
    let result = parse("meeting in 2h")
    XCTAssertEqual(result.title, "meeting")
    XCTAssertEqual(result.dueAt, now.addingTimeInterval(2 * 3600))
    XCTAssertEqual(result.dueKind, .datetime)
    XCTAssertEqual(result.interruptionKind, .hard)
  }

  // MARK: - `at <H>` / `at <H>pm`

  func testAtFour() {
    let result = parse("walk dog at 4")
    XCTAssertEqual(result.title, "walk dog")
    // 14:30 → next 4:00 is 16:00 today.
    XCTAssertEqual(result.dueAt, date(2026, 6, 8, 16, 0))
    XCTAssertEqual(result.interruptionKind, .hard)
  }

  func testAtFourPM() {
    let result = parse("standup at 4pm")
    XCTAssertEqual(result.title, "standup")
    XCTAssertEqual(result.dueAt, date(2026, 6, 8, 16, 0))
    XCTAssertEqual(result.dueKind, .datetime)
    XCTAssertEqual(result.interruptionKind, .hard)
  }

  func testAtBareHourRollsToTomorrowWhenPassed() {
    // Now is 14:30. "at 2" — next 2:00 is 2am tomorrow (today's 2am and 2pm
    // are both in the past).
    let result = parse("water plants at 2")
    XCTAssertEqual(result.dueAt, date(2026, 6, 9, 2, 0))
    XCTAssertEqual(result.interruptionKind, .hard)
  }

  // MARK: - `tomorrow` / `tomorrow <H>` / `tomorrow <H>am`

  func testTomorrowAlone() {
    let result = parse("yard work tomorrow")
    XCTAssertEqual(result.title, "yard work")
    XCTAssertEqual(result.dueAt, date(2026, 6, 9, 0, 0))
    XCTAssertEqual(result.dueKind, .date)
    XCTAssertEqual(result.interruptionKind, .soft)
  }

  func testTomorrowAtBareNine() {
    let result = parse("standup tomorrow 9")
    XCTAssertEqual(result.title, "standup")
    XCTAssertEqual(result.dueAt, date(2026, 6, 9, 9, 0))
    XCTAssertEqual(result.dueKind, .datetime)
    XCTAssertEqual(result.interruptionKind, .soft)
  }

  func testTomorrowNineAM() {
    let result = parse("call mom tomorrow 9am")
    XCTAssertEqual(result.title, "call mom")
    XCTAssertEqual(result.dueAt, date(2026, 6, 9, 9, 0))
    XCTAssertEqual(result.dueKind, .datetime)
    XCTAssertEqual(result.interruptionKind, .soft)
  }

  func testTomorrowAtThreePM() {
    // Regression: `… tomorrow at 3pm` used to be silently downgraded to
    // bare `at 3pm` (= today 3pm), with the title left as "test API
    // tomorrow". The 3-token `tomorrow at <H>` form is now first-class.
    let result = parse("test API tomorrow at 3pm")
    XCTAssertEqual(result.title, "test API")
    XCTAssertEqual(result.dueAt, date(2026, 6, 9, 15, 0))
    XCTAssertEqual(result.dueKind, .datetime)
    XCTAssertEqual(result.interruptionKind, .soft)
  }

  func testTomorrowAtBareNineRollsToTomorrow() {
    // `… tomorrow at 9` (ambiguous bare hour) should still resolve to
    // tomorrow 9am — the `tomorrow` anchor wins. Without the 3-token
    // rule this regressed to "next 9 o'clock" (today 9pm at our `now`).
    let result = parse("standup tomorrow at 9")
    XCTAssertEqual(result.title, "standup")
    XCTAssertEqual(result.dueAt, date(2026, 6, 9, 9, 0))
    XCTAssertEqual(result.dueKind, .datetime)
    XCTAssertEqual(result.interruptionKind, .soft)
  }

  func testWeekdayAtFivePM() {
    // Same 3-token shape, but anchored on a weekday. `friday at 5pm`
    // must not be eaten by the bare `at 5pm` rule.
    let result = parse("ship draft friday at 5pm")
    XCTAssertEqual(result.title, "ship draft")
    XCTAssertEqual(result.dueAt, date(2026, 6, 12, 17, 0))
    XCTAssertEqual(result.dueKind, .datetime)
    XCTAssertEqual(result.interruptionKind, .soft)
  }

  // MARK: - `friday` / `friday <H>pm`

  func testFridayAlone() {
    // Now is Monday 2026-06-08. Next Friday is 2026-06-12.
    let result = parse("ship draft friday")
    XCTAssertEqual(result.title, "ship draft")
    XCTAssertEqual(result.dueAt, date(2026, 6, 12, 0, 0))
    XCTAssertEqual(result.dueKind, .date)
    XCTAssertEqual(result.interruptionKind, .soft)
  }

  func testFridayFivePM() {
    let result = parse("ship draft friday 5pm")
    XCTAssertEqual(result.title, "ship draft")
    XCTAssertEqual(result.dueAt, date(2026, 6, 12, 17, 0))
    XCTAssertEqual(result.dueKind, .datetime)
    XCTAssertEqual(result.interruptionKind, .soft)
  }

  func testWeekdaySkipsToNextWeekWhenToday() {
    // Now is Monday. "monday" alone should mean *next* Monday, not today.
    let result = parse("groceries monday")
    XCTAssertEqual(result.dueAt, date(2026, 6, 15, 0, 0))
    XCTAssertEqual(result.dueKind, .date)
  }

  // MARK: - `due <…>` / `by <…>`

  func testDueFriday() {
    let result = parse("ship draft due friday")
    XCTAssertEqual(result.title, "ship draft")
    XCTAssertEqual(result.dueAt, date(2026, 6, 12, 0, 0))
    XCTAssertEqual(result.dueKind, .date)
    XCTAssertEqual(result.interruptionKind, .soft)
  }

  func testDueFridayFivePM() {
    let result = parse("ship draft due friday 5pm")
    XCTAssertEqual(result.title, "ship draft")
    XCTAssertEqual(result.dueAt, date(2026, 6, 12, 17, 0))
    XCTAssertEqual(result.dueKind, .datetime)
    XCTAssertEqual(result.interruptionKind, .soft)
  }

  func testByFriday() {
    let result = parse("ship draft by friday")
    XCTAssertEqual(result.title, "ship draft")
    XCTAssertEqual(result.dueAt, date(2026, 6, 12, 0, 0))
    XCTAssertEqual(result.dueKind, .date)
    XCTAssertEqual(result.interruptionKind, .soft)
  }

  func testByFridayFivePM() {
    let result = parse("ship draft by friday 5pm")
    XCTAssertEqual(result.title, "ship draft")
    XCTAssertEqual(result.dueAt, date(2026, 6, 12, 17, 0))
    XCTAssertEqual(result.dueKind, .datetime)
    XCTAssertEqual(result.interruptionKind, .soft)
  }

  // MARK: - `YYYY-MM-DD` / `YYYY-MM-DD HH:MM`

  func testISODate() {
    let result = parse("renew passport 2026-08-01")
    XCTAssertEqual(result.title, "renew passport")
    XCTAssertEqual(result.dueAt, date(2026, 8, 1, 0, 0))
    XCTAssertEqual(result.dueKind, .date)
    XCTAssertEqual(result.interruptionKind, .soft)
  }

  func testISODateTime() {
    let result = parse("file taxes 2026-04-15 17:00")
    XCTAssertEqual(result.title, "file taxes")
    XCTAssertEqual(result.dueAt, date(2026, 4, 15, 17, 0))
    XCTAssertEqual(result.dueKind, .datetime)
    XCTAssertEqual(result.interruptionKind, .soft)
  }

  func testISODateRejectsInvalidMonth() {
    let result = parse("nope 2026-13-01")
    // Falls through to "no recognized date".
    XCTAssertEqual(result.title, "nope 2026-13-01")
    XCTAssertNil(result.dueAt)
    XCTAssertEqual(result.interruptionKind, .none)
  }

  func testISODateRejectsInvalidDay() {
    let result = parse("nope 2026-02-30")
    XCTAssertEqual(result.title, "nope 2026-02-30")
    XCTAssertNil(result.dueAt)
    XCTAssertEqual(result.interruptionKind, .none)
  }

  // MARK: - No-match degenerate cases

  func testEmpty() {
    let result = parse("")
    XCTAssertEqual(result.title, "")
    XCTAssertNil(result.dueAt)
    XCTAssertEqual(result.interruptionKind, .none)
  }

  func testWhitespaceOnly() {
    let result = parse("   \n  ")
    XCTAssertEqual(result.title, "")
    XCTAssertNil(result.dueAt)
  }

  func testNoRecognizedDate() {
    let result = parse("read the asyncio docs sometime")
    XCTAssertEqual(result.title, "read the asyncio docs sometime")
    XCTAssertNil(result.dueAt)
    XCTAssertEqual(result.dueKind, .none)
    XCTAssertEqual(result.interruptionKind, .none)
  }

  // MARK: - Case insensitivity

  func testCaseInsensitive() {
    let result = parse("Standup AT 4PM")
    XCTAssertEqual(result.title, "Standup")
    XCTAssertEqual(result.dueAt, date(2026, 6, 8, 16, 0))
    XCTAssertEqual(result.interruptionKind, .hard)
  }

  func testFridayCapitalized() {
    let result = parse("ship draft Friday")
    XCTAssertEqual(result.title, "ship draft")
    XCTAssertEqual(result.dueAt, date(2026, 6, 12, 0, 0))
  }

  // MARK: - Low-confidence signaling

  func testTomorrowAloneIsLowConfidence() {
    // Bare `tomorrow` matches as start-of-day with no clock — capture
    // overlay needs to flag this so the user can tap the chip and pick
    // a time rather than trust the inferred midnight.
    let result = parse("yard work tomorrow")
    XCTAssertTrue(result.lowConfidence)
  }

  func testTomorrowAtTimeIsHighConfidence() {
    // `tomorrow at 3pm` resolves to a precise datetime — no ambiguity.
    let result = parse("test API tomorrow at 3pm")
    XCTAssertFalse(result.lowConfidence)
  }

  func testBareWeekdayIsLowConfidence() {
    // Same shape as bare `tomorrow`: a day-only match with no time.
    let result = parse("ship draft Friday")
    XCTAssertTrue(result.lowConfidence)
  }

  func testWeekdayWithTimeIsHighConfidence() {
    let result = parse("submit calc homework Friday 5pm")
    XCTAssertFalse(result.lowConfidence)
  }

  func testNoMatchIsNotLowConfidence() {
    // Absence of a chip is its own signal — don't claim low confidence
    // when the parser declined to recognize anything at all.
    let result = parse("read the asyncio docs sometime")
    XCTAssertFalse(result.lowConfidence)
  }

  func testISODateAloneIsLowConfidence() {
    // `YYYY-MM-DD` matches as `.date` with no clock — also ambiguous.
    let result = parse("review draft 2026-06-12")
    XCTAssertTrue(result.lowConfidence)
  }
}
