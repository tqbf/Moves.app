import XCTest
@testable import Moves

/// Round-trip tests for Phase-5 AppStore additions: segment lifecycle,
/// Markdown import, weekly view aggregation. The DOD: segment lifecycle
/// survives relaunch; importing the §9 example produces a regimented
/// thread with 2 segments + 7 items; weekly view aggregates correctly.
@MainActor
final class Phase5AppStoreTests: XCTestCase {
  private var tempDir: URL!
  private var store: AppStore!

  override func setUp() async throws {
    tempDir = FileManager.default.temporaryDirectory
      .appending(path: "moves-phase5tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    store = AppStore(databasePath: dbPath, enableNotifications: false)
  }

  override func tearDown() async throws {
    store = nil
    if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
  }

  private var dbPath: String {
    tempDir.appending(path: "moves.sqlite3").path(percentEncoded: false)
  }

  private func insertRegimentedThread() async throws -> Moves.Thread {
    let thread = Moves.Thread(title: "Python refresh", kind: .regimented)
    try await store.threadRepository.insert(thread)
    await store.reloadThreads()
    return thread
  }

  // MARK: - Segment lifecycle

  func testAddSegmentAppendsAtEnd() async throws {
    let thread = try await insertRegimentedThread()
    _ = await store.addSegment(thread: thread, title: "Day 01", builtInMove: "Write parser")
    _ = await store.addSegment(thread: thread, title: "Day 02", builtInMove: "Build log parser")
    let segments = try await store.segmentRepository.forThread(thread.id)
    XCTAssertEqual(segments.count, 2)
    XCTAssertEqual(segments.map(\.title), ["Day 01", "Day 02"])
    XCTAssertEqual(segments.map(\.orderIndex), [0, 1])
  }

  func testActivateSegmentDemotesPreviousActive() async throws {
    let thread = try await insertRegimentedThread()
    let aRaw = await store.addSegment(thread: thread, title: "A", builtInMove: "alpha")
    let bRaw = await store.addSegment(thread: thread, title: "B", builtInMove: "beta")
    let aSeg = try XCTUnwrap(aRaw)
    let bSeg = try XCTUnwrap(bRaw)
    await store.activateSegment(aSeg)
    await store.activateSegment(bSeg)
    let segments = try await store.segmentRepository.forThread(thread.id)
    XCTAssertEqual(segments.filter { $0.status == .active }.count, 1,
                   "exactly one segment may be active per thread (§3)")
    XCTAssertEqual(segments.first(where: { $0.id == bSeg.id })?.status, .active)
    XCTAssertEqual(segments.first(where: { $0.id == aSeg.id })?.status, .pending)
  }

  func testCompleteActiveSegmentLogsTimeAndAdvances() async throws {
    let thread = try await insertRegimentedThread()
    let aRaw = await store.addSegment(thread: thread, title: "A", builtInMove: "alpha")
    let bRaw = await store.addSegment(thread: thread, title: "B", builtInMove: "beta")
    let a = try XCTUnwrap(aRaw)
    let b = try XCTUnwrap(bRaw)
    await store.activateSegment(a)

    await store.completeActiveSegment(thread: thread, rough: .m30)

    let segments = try await store.segmentRepository.forThread(thread.id)
    let completed = try XCTUnwrap(segments.first(where: { $0.id == a.id }))
    let promoted = try XCTUnwrap(segments.first(where: { $0.id == b.id }))
    XCTAssertEqual(completed.status, .done)
    XCTAssertEqual(promoted.status, .active, "next pending segment becomes active per §5.5")

    let logs = try await store.timeLogRepository.forThread(thread.id)
    XCTAssertEqual(logs.count, 1)
    XCTAssertEqual(logs.first?.roughMinutes, 30)
    XCTAssertEqual(logs.first?.segmentId, a.id,
                   "rough time attributes to the segment that was completed, not the new active one")
    _ = b
  }

  func testCompleteActiveSegmentWithNoneBucketSkipsLog() async throws {
    let thread = try await insertRegimentedThread()
    let aRaw = await store.addSegment(thread: thread, title: "A")
    let a = try XCTUnwrap(aRaw)
    await store.activateSegment(a)
    await store.completeActiveSegment(thread: thread, rough: .none)
    let logs = try await store.timeLogRepository.forThread(thread.id)
    XCTAssertTrue(logs.isEmpty, "rough=.none must not write a time_log row")
  }

  func testCompleteActiveSegmentWithNoMorePendingLeavesNoActive() async throws {
    let thread = try await insertRegimentedThread()
    let onlyRaw = await store.addSegment(thread: thread, title: "Only", builtInMove: "x")
    let only = try XCTUnwrap(onlyRaw)
    await store.activateSegment(only)
    await store.completeActiveSegment(thread: thread, rough: .m15)
    let segments = try await store.segmentRepository.forThread(thread.id)
    XCTAssertNil(segments.first(where: { $0.status == .active }))
    XCTAssertEqual(segments.first?.status, .done)
  }

  func testSkipActiveSegmentPromotesNextPending() async throws {
    let thread = try await insertRegimentedThread()
    let aRaw = await store.addSegment(thread: thread, title: "A")
    let bRaw = await store.addSegment(thread: thread, title: "B")
    let a = try XCTUnwrap(aRaw)
    let b = try XCTUnwrap(bRaw)
    await store.activateSegment(a)
    let segmentsAfterActivate = try await store.segmentRepository.forThread(thread.id)
    let active = try XCTUnwrap(segmentsAfterActivate.first(where: { $0.id == a.id }))
    await store.skipSegment(active)
    let segments = try await store.segmentRepository.forThread(thread.id)
    XCTAssertEqual(segments.first(where: { $0.id == a.id })?.status, .skipped)
    XCTAssertEqual(segments.first(where: { $0.id == b.id })?.status, .active)
  }

  // MARK: - Switching does not advance segments (§5.5)

  func testSwitchingDoesNotTouchSegmentStatus() async throws {
    let thread = try await insertRegimentedThread()
    let aRaw = await store.addSegment(thread: thread, title: "A")
    let a = try XCTUnwrap(aRaw)
    await store.activateSegment(a)

    // Bring up a second thread + switch.
    let other = Moves.Thread(title: "Other")
    try await store.threadRepository.insert(other)
    await store.reloadThreads()
    await store.start(thread)
    await store.switchTo(other, breadcrumb: "left mid-step", rough: .m15)

    let segments = try await store.segmentRepository.forThread(thread.id)
    XCTAssertEqual(segments.first(where: { $0.id == a.id })?.status, .active,
                   "switching must not advance the segment (§5.5)")
  }

  // MARK: - Lifecycle survives relaunch (DOD)

  func testSegmentLifecycleSurvivesRelaunch() async throws {
    let thread = try await insertRegimentedThread()
    let aRaw = await store.addSegment(thread: thread, title: "A", builtInMove: "alpha")
    let bRaw = await store.addSegment(thread: thread, title: "B", builtInMove: "beta")
    let a = try XCTUnwrap(aRaw)
    let b = try XCTUnwrap(bRaw)
    await store.activateSegment(a)
    await store.completeActiveSegment(thread: thread, rough: .h1)

    // Sanity: in this process, b is active.
    let pre = try await store.segmentRepository.forThread(thread.id)
    XCTAssertEqual(pre.first(where: { $0.id == b.id })?.status, .active)

    // Re-open a fresh AppStore against the same DB.
    let reopened = AppStore(databasePath: dbPath, enableNotifications: false)
    await reopened.reloadThreads()
    await reopened.rebuildAvailable()
    let segments = try await reopened.segmentRepository.forThread(thread.id)
    XCTAssertEqual(segments.first(where: { $0.id == a.id })?.status, .done)
    XCTAssertEqual(segments.first(where: { $0.id == b.id })?.status, .active)
    let logs = try await reopened.timeLogRepository.forThread(thread.id)
    XCTAssertEqual(logs.count, 1)
    XCTAssertEqual(logs.first?.roughMinutes, 60)
  }

  // MARK: - Markdown import (DOD)

  func testImportMarkdownProducesTwoSegmentsAndItemsFromSection9Example() async throws {
    let source = """
    ---
    title: Python Refresh
    kind: regimented
    visibility: normal
    default_estimate_minutes: 60
    ---

    ## Day 01: Modern Python syntax
    date: 2026-06-01
    estimate: 60

    move: Write a tiny parser using dataclasses and match/case.

    - [ ] Review dataclasses
    - [ ] Review type hints
    - [ ] Write parser
    - [ ] Add pytest cases

    ## Day 02: pathlib, argparse, pytest
    date: 2026-06-02
    estimate: 60

    move: Build a compact access-log parser.

    - [ ] Parse one line
    - [ ] Add named-group regex
    - [ ] Add invalid-line tests
    """
    let resultRaw = await store.importMarkdown(source)
    let result = try XCTUnwrap(resultRaw)
    XCTAssertEqual(result.segmentCount, 2)
    XCTAssertEqual(result.itemCount, 7)

    let threadRaw = try await store.threadRepository.find(id: result.threadId)
    let thread = try XCTUnwrap(threadRaw)
    XCTAssertEqual(thread.title, "Python Refresh")
    XCTAssertEqual(thread.kind, .regimented)
    let segments = try await store.segmentRepository.forThread(thread.id)
    XCTAssertEqual(segments.count, 2)
    XCTAssertEqual(segments[0].status, .active)
    XCTAssertEqual(segments[1].status, .pending)
  }

  func testImportingSameTitleTwiceProducesDistinctThreadsWithWarning() async throws {
    let source = """
    ---
    title: Dup
    kind: regimented
    ---

    ## Only
    move: x
    """
    let aRaw = await store.importMarkdown(source)
    let bRaw = await store.importMarkdown(source)
    let a = try XCTUnwrap(aRaw)
    let b = try XCTUnwrap(bRaw)
    XCTAssertNotEqual(a.threadId, b.threadId, "v1 import is create-only — duplicates are distinct threads")
    XCTAssertTrue(b.warnings.contains(where: { $0.contains("already exists") }))
  }

  // MARK: - Weekly view (DOD)

  func testWeeklyViewAggregatesAcrossMultipleStopsAndSegmentCompletions() async throws {
    // Insert two threads in this week. One gets stop logs, the other gets a
    // segment-completion log. The weekly view should sum them per thread.
    let writing = Moves.Thread(title: "Writing")
    try await store.threadRepository.insert(writing)
    let python = try await insertRegimentedThread()
    let segRaw = await store.addSegment(thread: python, title: "Day 01", builtInMove: "x")
    let seg = try XCTUnwrap(segRaw)
    await store.activateSegment(seg)
    await store.reloadThreads()

    // Stop on writing twice (30m + 15m).
    await store.start(writing)
    await store.stop(breadcrumb: "saved point", rough: .m30)
    await store.start(writing)
    await store.stop(breadcrumb: "saved again", rough: .m15)

    // Complete one segment on python (60m).
    await store.completeActiveSegment(thread: python, rough: .h1)

    let summary = await store.weeklyView(for: Date())
    let writingAgg = summary.entries.first(where: { $0.threadId == writing.id })
    let pythonAgg = summary.entries.first(where: { $0.threadId == python.id })
    XCTAssertEqual(writingAgg?.totalMinutes, 45)
    XCTAssertEqual(pythonAgg?.totalMinutes, 60)
  }

  func testWeeklyViewEmptyWeekReturnsEmpty() async throws {
    let summary = await store.weeklyView(for: Date())
    XCTAssertEqual(summary.entries.count, 0)
  }

  // MARK: - segmentsByThread cache feeds Available

  func testRebuildAvailablePopulatesSegmentsByThreadCache() async throws {
    let thread = try await insertRegimentedThread()
    let aRaw = await store.addSegment(thread: thread, title: "A", builtInMove: "alpha")
    let a = try XCTUnwrap(aRaw)
    await store.activateSegment(a)
    await store.rebuildAvailable()
    let cached = store.segmentsByThread[thread.id]
    XCTAssertEqual(cached?.count, 1)
    XCTAssertEqual(store.currentSegment(for: thread)?.id, a.id)
  }
}
