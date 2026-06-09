import XCTest
@testable import Moves

/// End-to-end round-trip exercise for every Phase-1 repository against a
/// fresh on-disk SQLite file. The point isn't coverage — it's that the
/// schema, binding, and row-mapping line up on every table.
final class PersistenceRoundTripTests: XCTestCase {
  private var tempDir: URL!

  override func setUpWithError() throws {
    tempDir = FileManager.default.temporaryDirectory
      .appending(path: "moves-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
  }

  private func openDatabase() throws -> Database {
    try Database(path: tempDir.appending(path: "moves.sqlite3").path(percentEncoded: false))
  }

  // MARK: - Threads

  func testThreadRoundTrip() async throws {
    let db = try openDatabase()
    let repo = ThreadRepository(database: db)

    let initial = Thread(
      title: "Python refresh",
      kind: .regimented,
      breadcrumb: "GET nil bulk string still failing"
    )
    try await repo.insert(initial)

    let loaded = try await repo.find(id: initial.id)
    XCTAssertEqual(loaded?.title, "Python refresh")
    XCTAssertEqual(loaded?.kind, .regimented)
    XCTAssertEqual(loaded?.breadcrumb, "GET nil bulk string still failing")
    XCTAssertEqual(loaded?.status, .active)

    var updated = try XCTUnwrap(loaded)
    updated.title = "Python refresh v2"
    updated.status = .parked
    updated.visibility = .hideWork
    try await repo.update(updated)

    let again = try await repo.find(id: initial.id)
    XCTAssertEqual(again?.title, "Python refresh v2")
    XCTAssertEqual(again?.status, .parked)
    XCTAssertEqual(again?.visibility, .hideWork)

    let parked = try await repo.withStatus(.parked)
    let active = try await repo.withStatus(.active)
    XCTAssertEqual(parked.count, 1)
    XCTAssertEqual(active.count, 0)

    try await repo.delete(id: initial.id)
    let afterDelete = try await repo.find(id: initial.id)
    XCTAssertNil(afterDelete)
  }

  // MARK: - Segments

  func testSegmentRoundTrip() async throws {
    let db = try openDatabase()
    let threads = ThreadRepository(database: db)
    let segments = SegmentRepository(database: db)

    let thread = Thread(title: "Multivariable calculus", kind: .regimented)
    try await threads.insert(thread)

    let lesson1 = Segment(
      threadId: thread.id,
      title: "Lesson 1 — Vectors",
      orderIndex: 1,
      builtInMove: "Do a dot product exercise"
    )
    let lesson2 = Segment(
      threadId: thread.id,
      title: "Lesson 2 — Lines & planes",
      orderIndex: 2,
      builtInMove: "Parametrize a line"
    )
    try await segments.insert(lesson1)
    try await segments.insert(lesson2)

    let loaded = try await segments.forThread(thread.id)
    XCTAssertEqual(loaded.map(\.title), [lesson1.title, lesson2.title])

    var updated = lesson1
    updated.status = .active
    updated.estimateMinutes = 45
    try await segments.update(updated)

    let refetched = try await segments.find(id: lesson1.id)
    XCTAssertEqual(refetched?.status, .active)
    XCTAssertEqual(refetched?.estimateMinutes, 45)

    try await segments.delete(id: lesson2.id)
    let remaining = try await segments.forThread(thread.id)
    XCTAssertEqual(remaining.count, 1)
  }

  // MARK: - Items

  func testItemRoundTrip() async throws {
    let db = try openDatabase()
    let threads = ThreadRepository(database: db)
    let items = ItemRepository(database: db)

    let thread = Thread(title: "Picture frames")
    try await threads.insert(thread)

    let standalone = Item(title: "buy walnut dowels")
    let reminder = Item(
      threadId: thread.id,
      title: "check glue-up",
      status: .open,
      kind: .reminder,
      dueAt: 4_102_444_800, // 2100-01-01
      dueKind: .datetime,
      interruptionKind: .hard
    )
    try await items.insert(standalone)
    try await items.insert(reminder)

    let captured = try await items.captured()
    let openForThread = try await items.openForThread(thread.id)
    let forThread = try await items.forThread(thread.id)
    let upcoming = try await items.upcomingHard(now: 0)
    XCTAssertEqual(captured.count, 1)
    XCTAssertEqual(openForThread.count, 1)
    XCTAssertEqual(forThread.count, 1)
    XCTAssertEqual(upcoming.count, 1)

    var updated = standalone
    updated.status = .open
    updated.threadId = thread.id
    try await items.update(updated)
    let openAfterUpdate = try await items.openForThread(thread.id)
    XCTAssertEqual(openAfterUpdate.count, 2)

    try await items.delete(id: reminder.id)
    let gone = try await items.find(id: reminder.id)
    XCTAssertNil(gone)
  }

  /// Boundary test for the 1-hour overdue cap on the badge query: items
  /// up to 60 minutes past due_at count, anything older does not. The
  /// user's framing: "overdue status only matters for an hour, and then
  /// stop flagging it."
  func testDueOrOverdueHardCountCapsAtOneHour() async throws {
    let db = try openDatabase()
    let items = ItemRepository(database: db)

    let now: Int64 = 1_780_493_400 // fixture: 2026-06-08 14:30 UTC

    // 30 minutes overdue — should count.
    let recent = Item(
      title: "30m overdue",
      status: .open,
      kind: .reminder,
      dueAt: now - 30 * 60,
      dueKind: .datetime,
      interruptionKind: .hard
    )
    // 90 minutes overdue — should NOT count.
    let stale = Item(
      title: "90m overdue",
      status: .open,
      kind: .reminder,
      dueAt: now - 90 * 60,
      dueKind: .datetime,
      interruptionKind: .hard
    )
    // Future hard item — should NOT count (existing behavior).
    let future = Item(
      title: "in 10m",
      status: .open,
      kind: .reminder,
      dueAt: now + 10 * 60,
      dueKind: .datetime,
      interruptionKind: .hard
    )
    try await items.insert(recent)
    try await items.insert(stale)
    try await items.insert(future)

    let count = try await items.dueOrOverdueHardCount(now: now)
    XCTAssertEqual(count, 1, "only the 30-minute-overdue item should count toward the badge")

    // Boundary: exactly 60 minutes overdue is still inside the window.
    let edge = Item(
      title: "60m overdue",
      status: .open,
      kind: .reminder,
      dueAt: now - 3600,
      dueKind: .datetime,
      interruptionKind: .hard
    )
    try await items.insert(edge)
    let withEdge = try await items.dueOrOverdueHardCount(now: now)
    XCTAssertEqual(withEdge, 2, "60-minute-overdue boundary should count (>= now - 3600)")
  }

  /// `dueSoonHardCount` counts hard items whose `due_at` is in the strict
  /// future window `(now, now + soonWindow]`. Excludes past-due
  /// (`dueOrOverdueHardCount`'s territory), exclusive lower bound at
  /// exactly `now`, inclusive upper bound at exactly `now + window`,
  /// honors the status + interruption-kind filter.
  func testDueSoonHardCountWindowBoundaries() async throws {
    let db = try openDatabase()
    let items = ItemRepository(database: db)

    let now: Int64 = 1_780_493_400 // 2026-06-08 14:30 UTC fixture
    let window: Int64 = 30 * 60

    // Inside the window: 10m, 20m, 29m ahead — hard + open/captured.
    let inTen = Item(
      title: "10m",
      status: .open,
      kind: .reminder,
      dueAt: now + 10 * 60,
      dueKind: .datetime,
      interruptionKind: .hard
    )
    let inTwenty = Item(
      title: "20m",
      status: .captured,
      kind: .reminder,
      dueAt: now + 20 * 60,
      dueKind: .datetime,
      interruptionKind: .hard
    )
    let inTwentyNine = Item(
      title: "29m",
      status: .open,
      kind: .reminder,
      dueAt: now + 29 * 60,
      dueKind: .datetime,
      interruptionKind: .hard
    )
    // On the upper boundary: exactly 30m ahead — should count (inclusive).
    let atBoundary = Item(
      title: "30m",
      status: .open,
      kind: .reminder,
      dueAt: now + window,
      dueKind: .datetime,
      interruptionKind: .hard
    )
    // Outside the window: 31m and 45m ahead — should NOT count.
    let inThirtyOne = Item(
      title: "31m",
      status: .open,
      kind: .reminder,
      dueAt: now + 31 * 60,
      dueKind: .datetime,
      interruptionKind: .hard
    )
    let inFortyFive = Item(
      title: "45m",
      status: .open,
      kind: .reminder,
      dueAt: now + 45 * 60,
      dueKind: .datetime,
      interruptionKind: .hard
    )
    // 20m ahead but soft interruption — kind filter excludes it.
    let softInTwenty = Item(
      title: "20m soft",
      status: .open,
      kind: .reminder,
      dueAt: now + 20 * 60,
      dueKind: .datetime,
      interruptionKind: .soft
    )
    // 20m ahead but already completed — status filter excludes it.
    let doneInTwenty = Item(
      title: "20m done",
      status: .done,
      kind: .reminder,
      dueAt: now + 20 * 60,
      dueKind: .datetime,
      interruptionKind: .hard
    )
    // Exactly at `now` — strict-future lower bound excludes it
    // (this is the `dueOrOverdueHardCount` bucket's territory).
    let atNow = Item(
      title: "now",
      status: .open,
      kind: .reminder,
      dueAt: now,
      dueKind: .datetime,
      interruptionKind: .hard
    )

    for item in [inTen, inTwenty, inTwentyNine, atBoundary,
                 inThirtyOne, inFortyFive, softInTwenty, doneInTwenty, atNow] {
      try await items.insert(item)
    }

    let count = try await items.dueSoonHardCount(now: now, soonWindow: window)
    XCTAssertEqual(count, 4, "10m, 20m, 29m, 30m should count; the rest are filtered out by window / kind / status")
  }

  // MARK: - Alerts

  func testAlertRoundTrip() async throws {
    let db = try openDatabase()
    let threads = ThreadRepository(database: db)
    let items = ItemRepository(database: db)
    let alerts = AlertRepository(database: db)

    let thread = Thread(title: "Errands")
    try await threads.insert(thread)
    let item = Item(
      threadId: thread.id,
      title: "call Sarah",
      kind: .reminder,
      dueAt: 5_000_000,
      dueKind: .datetime,
      interruptionKind: .hard
    )
    try await items.insert(item)

    let atDue = Alert(itemId: item.id, offsetMinutes: 0)
    let fiveBefore = Alert(itemId: item.id, offsetMinutes: -5)
    try await alerts.insert(atDue)
    try await alerts.insert(fiveBefore)

    let forItem = try await alerts.forItem(item.id)
    let pending = try await alerts.pending()
    XCTAssertEqual(forItem.count, 2)
    XCTAssertEqual(pending.count, 2)

    try await alerts.markFired(id: atDue.id, at: 5_000_000)
    let pendingAfterFire = try await alerts.pending()
    XCTAssertEqual(pendingAfterFire.count, 1)

    try await alerts.delete(id: fiveBefore.id)
    let afterDelete = try await alerts.forItem(item.id)
    XCTAssertEqual(afterDelete.count, 1)

    // Cascade: deleting the item should remove its alerts.
    try await items.delete(id: item.id)
    let afterCascade = try await alerts.forItem(item.id)
    XCTAssertEqual(afterCascade.count, 0)
  }

  // MARK: - CurrentState

  func testCurrentStateRoundTrip() async throws {
    let db = try openDatabase()
    let threads = ThreadRepository(database: db)
    let current = CurrentStateRepository(database: db)

    let initial = try await current.get()
    XCTAssertEqual(initial, .empty)

    let thread = Thread(title: "Writing")
    try await threads.insert(thread)

    try await current.set(
      CurrentState(threadId: thread.id, segmentId: nil, startedAt: 1_700_000_000)
    )
    let loaded = try await current.get()
    XCTAssertEqual(loaded.threadId, thread.id)
    XCTAssertEqual(loaded.startedAt, 1_700_000_000)

    try await current.clear()
    let cleared = try await current.get()
    XCTAssertEqual(cleared, .empty)
  }

  // MARK: - TimeLog

  func testTimeLogRoundTrip() async throws {
    let db = try openDatabase()
    let threads = ThreadRepository(database: db)
    let log = TimeLogRepository(database: db)

    let thread = Thread(title: "Wood shop")
    try await threads.insert(thread)

    let weekStart = "2026-06-01"
    let entry = TimeLogEntry(threadId: thread.id, weekStart: weekStart, roughMinutes: 45)
    try await log.insert(entry)

    let byWeek = try await log.forWeek(weekStart)
    let byThread = try await log.forThread(thread.id)
    XCTAssertEqual(byWeek.count, 1)
    XCTAssertEqual(byThread.count, 1)

    try await log.delete(id: entry.id)
    let after = try await log.forWeek(weekStart)
    XCTAssertEqual(after.count, 0)
  }

  // MARK: - Settings

  func testSettingsRoundTrip() async throws {
    let db = try openDatabase()
    let settings = SettingsRepository(database: db)

    let missing = try await settings.get("working_hours")
    XCTAssertNil(missing)

    try await settings.set("working_hours", value: "mon-fri 09:00-17:30")
    let first = try await settings.get("working_hours")
    XCTAssertEqual(first, "mon-fri 09:00-17:30")

    try await settings.set("working_hours", value: "mon-fri 10:00-18:00")
    let updated = try await settings.get("working_hours")
    XCTAssertEqual(updated, "mon-fri 10:00-18:00")

    let all = try await settings.all()
    XCTAssertEqual(all.count, 1)

    try await settings.delete("working_hours")
    let afterDelete = try await settings.get("working_hours")
    XCTAssertNil(afterDelete)
  }

  // MARK: - Migrations are idempotent across reopen

  func testReopeningTwiceDoesNotReapplyMigrations() async throws {
    _ = try openDatabase()
    let db = try openDatabase()
    let repo = ThreadRepository(database: db)
    let all = try await repo.all()
    XCTAssertEqual(all.count, 0)
  }
}
