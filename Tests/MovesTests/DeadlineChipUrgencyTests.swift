import XCTest
@testable import Moves

/// Cover the leaf urgency computation `DeadlineChip` uses to pick its
/// tint (overdue red vs orange) and accessibility label. Tests pin the
/// calendar to a fixed Gregorian + UTC so day-boundary math is
/// reproducible regardless of the host CI's locale / timezone.
final class DeadlineChipUrgencyTests: XCTestCase {

  private static let utcCalendar: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal
  }()

  /// Anchored "now" used across cases: 2026-06-09 14:00 UTC. Chosen so
  /// `startOfToday` is 2026-06-09 00:00 and `endOfToday`/`startOfTomorrow`
  /// is 2026-06-10 00:00 — clean buckets, no DST edges. Computed lazily
  /// via a static helper so the stored-property initializer doesn't
  /// reference `Self` (Swift 6 forbids that).
  private static func makeNow() -> Date {
    var c = DateComponents()
    c.year = 2026; c.month = 6; c.day = 9
    c.hour = 14; c.minute = 0; c.second = 0
    return utcCalendar.date(from: c)!
  }
  private var now: Date { Self.makeNow() }

  // MARK: - Overdue

  func testOverdueWhenDueAtIsBeforeNow() {
    let dueAt = now.addingTimeInterval(-5 * 60) // 5 minutes ago
    XCTAssertEqual(
      DeadlineChipUrgency.from(dueAt: dueAt, now: now, calendar: Self.utcCalendar),
      .overdue
    )
  }

  func testOverdueWhenDueAtIsHoursBefore() {
    let dueAt = now.addingTimeInterval(-6 * 60 * 60) // 6 hours ago
    XCTAssertEqual(
      DeadlineChipUrgency.from(dueAt: dueAt, now: now, calendar: Self.utcCalendar),
      .overdue
    )
  }

  // MARK: - Due today

  func testDueTodayLaterInTheDay() {
    // now = 2026-06-09 14:00, dueAt = 2026-06-09 23:30 → due today
    var c = DateComponents()
    c.year = 2026; c.month = 6; c.day = 9
    c.hour = 23; c.minute = 30; c.second = 0
    let dueAt = Self.utcCalendar.date(from: c)!
    XCTAssertEqual(
      DeadlineChipUrgency.from(dueAt: dueAt, now: now, calendar: Self.utcCalendar),
      .dueToday
    )
  }

  func testSpecCaseDueTodayMorningWindow() {
    // Spec case: startOfToday + 14h with now = startOfToday + 9h → dueToday.
    // Override now to 2026-06-09 09:00 UTC and dueAt to 2026-06-09 14:00 UTC.
    var nowComps = DateComponents()
    nowComps.year = 2026; nowComps.month = 6; nowComps.day = 9
    nowComps.hour = 9; nowComps.minute = 0
    let pinnedNow = Self.utcCalendar.date(from: nowComps)!

    var dueComps = DateComponents()
    dueComps.year = 2026; dueComps.month = 6; dueComps.day = 9
    dueComps.hour = 14; dueComps.minute = 0
    let pinnedDue = Self.utcCalendar.date(from: dueComps)!

    XCTAssertEqual(
      DeadlineChipUrgency.from(dueAt: pinnedDue, now: pinnedNow, calendar: Self.utcCalendar),
      .dueToday
    )
  }

  // MARK: - Due tomorrow

  func testDueTomorrowJustAfterMidnight() {
    var c = DateComponents()
    c.year = 2026; c.month = 6; c.day = 10
    c.hour = 0; c.minute = 30
    let dueAt = Self.utcCalendar.date(from: c)!
    XCTAssertEqual(
      DeadlineChipUrgency.from(dueAt: dueAt, now: now, calendar: Self.utcCalendar),
      .dueTomorrow
    )
  }

  func testDueTomorrowEndOfDay() {
    var c = DateComponents()
    c.year = 2026; c.month = 6; c.day = 10
    c.hour = 23; c.minute = 59
    let dueAt = Self.utcCalendar.date(from: c)!
    XCTAssertEqual(
      DeadlineChipUrgency.from(dueAt: dueAt, now: now, calendar: Self.utcCalendar),
      .dueTomorrow
    )
  }

  // MARK: - Due future

  func testDueFutureTwoDaysOut() {
    var c = DateComponents()
    c.year = 2026; c.month = 6; c.day = 11
    c.hour = 9; c.minute = 0
    let dueAt = Self.utcCalendar.date(from: c)!
    XCTAssertEqual(
      DeadlineChipUrgency.from(dueAt: dueAt, now: now, calendar: Self.utcCalendar),
      .dueFuture
    )
  }

  func testDueFutureInOneHourBucketsAsToday() {
    // Spec case: dueAt = now + 1h → still today (14:00 + 1h = 15:00),
    // so categorized as `.dueToday`. This documents that "due soon" in
    // the strict-future sense (<= 30m) is a menubar concept; the chip
    // doesn't have a separate same-day-soon bucket.
    let dueAt = now.addingTimeInterval(60 * 60)
    XCTAssertEqual(
      DeadlineChipUrgency.from(dueAt: dueAt, now: now, calendar: Self.utcCalendar),
      .dueToday
    )
  }

  func testDueFutureAcrossDayBoundary() {
    // 36 hours out → 2026-06-11 02:00 UTC → dueFuture.
    let dueAt = now.addingTimeInterval(36 * 60 * 60)
    XCTAssertEqual(
      DeadlineChipUrgency.from(dueAt: dueAt, now: now, calendar: Self.utcCalendar),
      .dueFuture
    )
  }

  // MARK: - Boundary: exactly now is treated as overdue

  func testExactNowIsNotOverdue() {
    // `dueAt < now` strictly — equal is not overdue.
    XCTAssertEqual(
      DeadlineChipUrgency.from(dueAt: now, now: now, calendar: Self.utcCalendar),
      .dueToday
    )
  }
}
