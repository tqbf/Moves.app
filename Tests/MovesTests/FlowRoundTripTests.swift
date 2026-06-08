import XCTest
@testable import Moves

/// End-to-end exercise of the Phase-3 AppStore flows (start / stop /
/// switch / park) through a real on-disk database. The point isn't UI
/// coverage — it's that the methods touch the right rows in the right
/// order: `current_state` updates, `last_touched_at` re-touches, the
/// `time_log` write on stop/switch (and absence on park), and the §22
/// invariant on the resulting Available projection.
@MainActor
final class FlowRoundTripTests: XCTestCase {
  private var tempDir: URL!
  private var store: AppStore!

  override func setUp() async throws {
    tempDir = FileManager.default.temporaryDirectory
      .appending(path: "moves-flowtests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let dbPath = tempDir.appending(path: "moves.sqlite3").path(percentEncoded: false)
    store = AppStore(databasePath: dbPath, enableNotifications: false)
    XCTAssertNotNil(store.database, "Database failed to open: \(store.loadError ?? "nil")")
  }

  override func tearDown() async throws {
    store = nil
    if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
  }

  // MARK: - Helpers

  /// Insert a thread directly through the repo + reload. Mirrors what the
  /// Phase-4 main window will do; we don't go through `addThread(...)`
  /// here because that path is async-detached and we want determinism.
  private func makeThread(title: String, breadcrumb: String = "") async throws -> Moves.Thread {
    let repo = try XCTUnwrap(store.threadRepository)
    let thread = Moves.Thread(title: title, breadcrumb: breadcrumb)
    try await repo.insert(thread)
    await store.reloadThreads()
    await store.rebuildAvailable()
    return thread
  }

  private func makeOpenItem(on threadId: String, title: String) async throws {
    let repo = try XCTUnwrap(store.itemRepository)
    let item = Item(threadId: threadId, title: title, status: .open)
    try await repo.insert(item)
    await store.rebuildAvailable()
  }

  // MARK: - Start

  func testStartSetsCurrentAndTouchesThread() async throws {
    let thread = try await makeThread(title: "Python refresh", breadcrumb: "fix bulk string")

    await store.start(thread)

    XCTAssertEqual(store.current.threadId, thread.id)
    XCTAssertNotNil(store.current.startedAt)

    let touched = try await store.threadRepository?.find(id: thread.id)
    XCTAssertNotNil(touched?.lastTouchedAt, "start(_:) must update last_touched_at (§12)")
  }

  // MARK: - Stop

  func testStopClearsCurrentAndPersistsBreadcrumb() async throws {
    let thread = try await makeThread(title: "Writing")
    await store.start(thread)

    await store.stop(breadcrumb: "Halfway through filtering paragraph", rough: .m45)

    XCTAssertEqual(store.current, .empty)

    let persisted = try await store.threadRepository?.find(id: thread.id)
    XCTAssertEqual(persisted?.breadcrumb, "Halfway through filtering paragraph")

    // 45m bucket lands as one TimeLogEntry row.
    let log = try await store.timeLogRepository?.forThread(thread.id)
    XCTAssertEqual(log?.count, 1)
    XCTAssertEqual(log?.first?.roughMinutes, 45)
  }

  func testStopWithNoneBucketSkipsTimeLog() async throws {
    let thread = try await makeThread(title: "Writing")
    await store.start(thread)

    await store.stop(breadcrumb: "later", rough: .none)

    let log = try await store.timeLogRepository?.forThread(thread.id)
    XCTAssertEqual(log?.count ?? 0, 0, "rough == .none must not write a time_log row")
  }

  // MARK: - Switch

  func testSwitchSwapsCurrentAndLogsAgainstPrevious() async throws {
    let python = try await makeThread(title: "Python", breadcrumb: "")
    let writing = try await makeThread(title: "Writing", breadcrumb: "old breadcrumb")

    await store.start(python)
    await store.switchTo(writing, breadcrumb: "GET nil bulk string", rough: .h1)

    XCTAssertEqual(store.current.threadId, writing.id, "current must point at the new target")

    let pythonAfter = try await store.threadRepository?.find(id: python.id)
    XCTAssertEqual(pythonAfter?.breadcrumb, "GET nil bulk string", "previous thread must keep the saved breadcrumb")

    let pythonLog = try await store.timeLogRepository?.forThread(python.id)
    XCTAssertEqual(pythonLog?.count, 1, "time log must be attributed to the *previous* thread")
    XCTAssertEqual(pythonLog?.first?.roughMinutes, 60)

    let writingLog = try await store.timeLogRepository?.forThread(writing.id)
    XCTAssertEqual(writingLog?.count ?? 0, 0, "new thread must not get a time-log entry on switch")
  }

  func testSwitchWithNoPriorCurrentJustStarts() async throws {
    let writing = try await makeThread(title: "Writing")
    await store.switchTo(writing, breadcrumb: "", rough: .m30)

    XCTAssertEqual(store.current.threadId, writing.id)
    // No previous thread to attribute to — no time-log entry anywhere.
    let log = try await store.timeLogRepository?.forThread(writing.id)
    XCTAssertEqual(log?.count ?? 0, 0)
  }

  // MARK: - Park

  func testParkSetsStatusAndDropsFromAvailable() async throws {
    let thread = try await makeThread(title: "Frames", breadcrumb: "sand the half-lap")
    XCTAssertTrue(store.availableThreads.contains(where: { $0.thread.id == thread.id }))

    await store.park(thread, breadcrumb: "tomorrow: dry-fit + glue-up")

    let persisted = try await store.threadRepository?.find(id: thread.id)
    XCTAssertEqual(persisted?.status, .parked)
    XCTAssertEqual(persisted?.breadcrumb, "tomorrow: dry-fit + glue-up")

    // §22 — parked threads must not appear in Available.
    XCTAssertFalse(store.availableThreads.contains(where: { $0.thread.id == thread.id }))

    // §5.4 — park writes no time-log entry.
    let log = try await store.timeLogRepository?.forThread(thread.id)
    XCTAssertEqual(log?.count ?? 0, 0)
  }

  func testParkClearsCurrentWhenParkingTheCurrentThread() async throws {
    let thread = try await makeThread(title: "Frames", breadcrumb: "old")
    await store.start(thread)
    XCTAssertEqual(store.current.threadId, thread.id)

    await store.park(thread, breadcrumb: "later")

    XCTAssertEqual(store.current, .empty, "parking the current thread must clear Current")
  }

  // MARK: - §22 invariant

  func testThreadWithoutReentryPointIsAbsentFromAvailable() async throws {
    // Active thread, no breadcrumb, no segments, no open items.
    let thread = try await makeThread(title: "Empty", breadcrumb: "")

    XCTAssertFalse(
      store.availableThreads.contains(where: { $0.thread.id == thread.id }),
      "thread with no re-entry move must not appear in Available (§22)"
    )

    // Now give it an open item — it should appear.
    try await makeOpenItem(on: thread.id, title: "first move")
    XCTAssertTrue(store.availableThreads.contains(where: { $0.thread.id == thread.id }))
  }

  func testParkedThreadAbsentFromAvailableEvenWithBreadcrumb() async throws {
    let thread = try await makeThread(title: "Parked", breadcrumb: "next move")
    XCTAssertTrue(store.availableThreads.contains(where: { $0.thread.id == thread.id }))

    await store.park(thread, breadcrumb: "next move")
    XCTAssertFalse(
      store.availableThreads.contains(where: { $0.thread.id == thread.id }),
      "parked threads are filtered out by status, regardless of resolved move"
    )
  }
}
