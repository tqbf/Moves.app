import XCTest
@testable import Moves

/// Tests the pure projection that drives the popover's Upcoming section
/// (INITIAL-PLAN §4.1, §2.10). The service is "headroom is a nudge, not
/// the app" — it only consults hard items for the runway calc, surfaces
/// the very next one, and reports overdue items as negative runway so the
/// UI can render them honestly instead of clamping to zero.
final class HeadroomServiceTests: XCTestCase {

  /// Fixture: 2026-06-08 14:30 UTC (matches the Phase-2 capture-parser
  /// fixture so we don't introduce a second magic timestamp).
  private let now = Date(timeIntervalSince1970: 1_780_493_400)

  private func item(
    title: String = "x",
    offsetSeconds: Int64?,
    interruption: InterruptionKind
  ) -> Item {
    Item(
      title: title,
      dueAt: offsetSeconds.map { Int64(now.timeIntervalSince1970) + $0 },
      dueKind: offsetSeconds == nil ? .none : .datetime,
      interruptionKind: interruption
    )
  }

  func testNoItemsReturnsNoRunway() {
    let result = HeadroomService.resolve(now: now, items: [])
    XCTAssertNil(result.nextHard)
    XCTAssertNil(result.runway)
  }

  func testOnlySoftItemsReturnsNoRunway() {
    // Soft items show in the popover's "other" line but don't contribute
    // runway. §2.10: headroom is hard-only; soft work doesn't pre-empt.
    let items = [
      item(title: "submit homework", offsetSeconds: 3600, interruption: .soft),
      item(title: "draft email", offsetSeconds: 1800, interruption: .soft),
    ]
    let result = HeadroomService.resolve(now: now, items: items)
    XCTAssertNil(result.nextHard)
    XCTAssertNil(result.runway)
  }

  func testNoneInterruptionItemsReturnNoRunway() {
    // .none captures (no deadline-bearing) are also excluded.
    let items = [
      item(title: "buy walnut dowels", offsetSeconds: 7200, interruption: .none),
    ]
    let result = HeadroomService.resolve(now: now, items: items)
    XCTAssertNil(result.nextHard)
    XCTAssertNil(result.runway)
  }

  func testSingleHardItemReportsExactRunway() {
    let oneHourOut = item(title: "call Sarah", offsetSeconds: 3600, interruption: .hard)
    let result = HeadroomService.resolve(now: now, items: [oneHourOut])
    XCTAssertEqual(result.nextHard?.title, "call Sarah")
    XCTAssertEqual(result.runway, 3600)
  }

  func testPicksEarliestHardItem() {
    // Pre-sort order shouldn't matter — the service sorts by dueAt asc.
    let items = [
      item(title: "later", offsetSeconds: 7200, interruption: .hard),
      item(title: "sooner", offsetSeconds: 1800, interruption: .hard),
      item(title: "soft", offsetSeconds: 300, interruption: .soft),
    ]
    let result = HeadroomService.resolve(now: now, items: items)
    XCTAssertEqual(result.nextHard?.title, "sooner")
    XCTAssertEqual(result.runway, 1800)
  }

  func testIgnoresHardItemsWithoutDueAt() {
    // A hard item with no due date is misconfigured but possible (an item
    // could lose its date via an edit). It must not crash the headroom
    // calc — just be excluded.
    let noDue = item(title: "broken hard", offsetSeconds: nil, interruption: .hard)
    XCTAssertNil(noDue.dueAt)
    let result = HeadroomService.resolve(now: now, items: [noDue])
    XCTAssertNil(result.nextHard)
    XCTAssertNil(result.runway)
  }

  func testOverdueHardItemReportsNegativeRunway() {
    // §4.1: overdue items must be reported honestly so the UI can render
    // "12m overdue" rather than clamping to zero. Negative runway is the
    // service's signal for that.
    let twelveMinutesAgo = item(title: "call Sarah", offsetSeconds: -720, interruption: .hard)
    let result = HeadroomService.resolve(now: now, items: [twelveMinutesAgo])
    XCTAssertEqual(result.nextHard?.title, "call Sarah")
    XCTAssertEqual(result.runway, -720)
  }

  func testOverdueAndFutureHardItems() {
    // Two hard items — one overdue, one upcoming. The overdue one is
    // earlier in time, so the service surfaces *that* with negative
    // runway. UI is responsible for the overdue copy.
    let items = [
      item(title: "upcoming", offsetSeconds: 1200, interruption: .hard),
      item(title: "overdue", offsetSeconds: -300, interruption: .hard),
    ]
    let result = HeadroomService.resolve(now: now, items: items)
    XCTAssertEqual(result.nextHard?.title, "overdue")
    XCTAssertEqual(result.runway, -300)
  }
}
