import XCTest
@testable import Moves

/// Round-trip tests for the Phase-4 AppStore additions: attach-to-thread,
/// convert-item-kind, set-visibility, working-hours persistence, and the
/// thread-detail Markdown notes path (write → reload → still there).
@MainActor
final class Phase4AppStoreTests: XCTestCase {
  private var tempDir: URL!
  private var store: AppStore!

  override func setUp() async throws {
    tempDir = FileManager.default.temporaryDirectory
      .appending(path: "moves-phase4tests-\(UUID().uuidString)", directoryHint: .isDirectory)
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

  // MARK: - Helpers

  private func insertThread(title: String, breadcrumb: String = "") async throws -> Moves.Thread {
    let thread = Moves.Thread(title: title, breadcrumb: breadcrumb)
    try await store.threadRepository.insert(thread)
    await store.reloadThreads()
    await store.rebuildAvailable()
    return thread
  }

  private func insertCapturedItem(title: String) async throws -> Item {
    let item = Item(threadId: nil, title: title, status: .captured, kind: .capture)
    try await store.itemRepository.insert(item)
    await store.reloadCaptured()
    return item
  }

  // MARK: - attachToThread

  func testAttachToThreadMovesItem() async throws {
    let thread = try await insertThread(title: "Python refresh")
    let item = try await insertCapturedItem(title: "remember to read this")

    await store.attachToThread(thread.id, item: item)

    // Item should no longer be in `captured` (status flipped to .open) and
    // should be attached to the thread.
    XCTAssertFalse(store.capturedItems.contains(where: { $0.id == item.id }))
    let reloaded = try await store.itemRepository.find(id: item.id)
    XCTAssertEqual(reloaded?.threadId, thread.id)
    XCTAssertEqual(reloaded?.status, .open)
  }

  // MARK: - convertItemKind

  func testConvertItemKindToReminderUpdatesInterruption() async throws {
    let item = try await insertCapturedItem(title: "ping the dog walker")
    await store.convertItemKind(item, to: .reminder)

    let reloaded = try await store.itemRepository.find(id: item.id)
    XCTAssertEqual(reloaded?.kind, .reminder)
    XCTAssertEqual(reloaded?.interruptionKind, .hard,
                   "reminder kind implies hard interruption (badge query expects it)")
  }

  func testConvertItemKindToTaskUpdatesInterruption() async throws {
    let item = try await insertCapturedItem(title: "draft the proposal")
    await store.convertItemKind(item, to: .task)

    let reloaded = try await store.itemRepository.find(id: item.id)
    XCTAssertEqual(reloaded?.kind, .task)
    XCTAssertEqual(reloaded?.interruptionKind, .soft)
  }

  // MARK: - setVisibility

  func testSetVisibilityPersists() async throws {
    let thread = try await insertThread(title: "Personal admin")

    store.setVisibility(thread, to: .hideWork)
    // The persist runs in a detached task — let it finish.
    try await Task.sleep(nanoseconds: 50_000_000)

    let reloaded = try await store.threadRepository.find(id: thread.id)
    XCTAssertEqual(reloaded?.visibility, .hideWork)
  }

  /// Regression: `availableThreads` caches a frozen `Thread` snapshot
  /// inside each `AvailableThread`. The popover groups Available rows on
  /// `row.thread.visibility`, so a `setVisibility` call that doesn't
  /// trigger `rebuildAvailable` leaves the popover reading stale values.
  /// Before the fix the second and third visibility edits looked like
  /// no-ops in the menubar — only the first one "stuck" (until some
  /// other action incidentally rebuilt).
  func testSetVisibilityRebuildsAvailableSnapshot() async throws {
    let t1 = try await insertThread(title: "T1", breadcrumb: "next 1")
    let t2 = try await insertThread(title: "T2", breadcrumb: "next 2")
    let t3 = try await insertThread(title: "T3", breadcrumb: "next 3")
    await store.rebuildAvailable()

    // Sanity: all three start as .normal in the cached snapshot.
    XCTAssertEqual(snapshotVisibility(for: t1.id), .normal)
    XCTAssertEqual(snapshotVisibility(for: t2.id), .normal)
    XCTAssertEqual(snapshotVisibility(for: t3.id), .normal)

    // Apply the change to all three in sequence. Each call must rebuild
    // — without that, only the first one would be reflected.
    for t in [t1, t2, t3] {
      store.setVisibility(t, to: .downweightWork)
      try await Task.sleep(nanoseconds: 50_000_000)
    }

    XCTAssertEqual(snapshotVisibility(for: t1.id), .downweightWork)
    XCTAssertEqual(snapshotVisibility(for: t2.id), .downweightWork)
    XCTAssertEqual(snapshotVisibility(for: t3.id), .downweightWork)
  }

  private func snapshotVisibility(for threadId: String) -> ThreadVisibility? {
    store.availableThreads.first { $0.thread.id == threadId }?.thread.visibility
  }

  // MARK: - Working hours round-trip

  func testWorkingHoursDefaultsWhenAbsent() async throws {
    await store.loadWorkingHours()
    XCTAssertEqual(store.workingHours, .default)
  }

  func testWorkingHoursPersistAndReload() async throws {
    let custom = WorkingHours(days: [2, 3, 4], startMinute: 10 * 60, endMinute: 18 * 60 + 30)
    await store.saveWorkingHours(custom)
    XCTAssertEqual(store.workingHours, custom)

    // New AppStore against the same DB should re-read the same value.
    let secondStore = AppStore(databasePath: dbPath, enableNotifications: false)
    await secondStore.loadWorkingHours()
    XCTAssertEqual(secondStore.workingHours, custom, "working hours must survive an AppStore re-open")
  }

  func testRefreshWorkTimeUpdatesIsWorkTime() async throws {
    // Tuesday at 10:00 UTC — inside Mon-Fri 9-17 default window. The
    // service operates in the calendar passed in; AppStore uses ISO-8601
    // local — fine for this assertion because we set workingHours to a
    // wraparound window that covers everything except a tiny gap.
    let always = WorkingHours(days: [1, 2, 3, 4, 5, 6, 7], startMinute: 0, endMinute: 1440)
    await store.saveWorkingHours(always)
    store.refreshWorkTime(now: Date())
    XCTAssertTrue(store.isWorkTime)

    let never = WorkingHours(days: [], startMinute: 0, endMinute: 1440)
    await store.saveWorkingHours(never)
    store.refreshWorkTime(now: Date())
    XCTAssertFalse(store.isWorkTime)
  }

  // MARK: - Markdown notes round-trip (DOD)

  func testMarkdownNotesRoundTripStableAcrossReopen() async throws {
    let thread = try await insertThread(title: "Frame jig")
    let markdown = """
    # Plan

    - dry-fit the half-laps
    - tune the dado stack to a snug fit
    - glue-up tomorrow morning

    ```swift
    let stack = DadoStack(width: 0.5)
    ```
    """

    store.updateDetailMarkdown(thread, to: markdown)
    try await Task.sleep(nanoseconds: 50_000_000)

    // Re-open the store against the same DB; the persisted detail_markdown
    // should be byte-identical (this is the DOD's "round-trip stable"
    // assertion).
    let reopened = AppStore(databasePath: dbPath, enableNotifications: false)
    await reopened.reloadThreads()
    let persisted = reopened.thread(id: thread.id)
    XCTAssertEqual(persisted?.detailMarkdown, markdown)
  }

  // MARK: - toggleItemDone

  func testToggleItemDoneFlipsStatus() async throws {
    let thread = try await insertThread(title: "Python refresh")
    let item = Item(threadId: thread.id, title: "wire up the parser", status: .open)
    try await store.itemRepository.insert(item)

    await store.toggleItemDone(item)
    let afterToggle = try await store.itemRepository.find(id: item.id)
    XCTAssertEqual(afterToggle?.status, .done)
    XCTAssertNotNil(afterToggle?.completedAt)

    if let toggled = afterToggle {
      await store.toggleItemDone(toggled)
    }
    let afterUnToggle = try await store.itemRepository.find(id: item.id)
    XCTAssertEqual(afterUnToggle?.status, .open)
    XCTAssertNil(afterUnToggle?.completedAt)
  }

  // MARK: - editDueAt

  func testEditDueAtSetsAndClears() async throws {
    let item = try await insertCapturedItem(title: "draft the email")
    let due = Date(timeIntervalSince1970: 1_800_000_000)

    await store.editDueAt(item, dueAt: due, dueKind: .datetime)
    let withDue = try await store.itemRepository.find(id: item.id)
    XCTAssertEqual(withDue?.dueAt, Int64(due.timeIntervalSince1970))
    XCTAssertEqual(withDue?.dueKind, .datetime)

    if let updated = withDue {
      await store.editDueAt(updated, dueAt: nil, dueKind: .none)
    }
    let cleared = try await store.itemRepository.find(id: item.id)
    XCTAssertNil(cleared?.dueAt)
    XCTAssertEqual(cleared?.dueKind, DueKind.none)
  }

  // MARK: - resolveOffsets

  func testResolveOffsetsNilUsesKindDefault() {
    XCTAssertEqual(
      AppStore.resolveOffsets(override: nil, kindDefault: [60, 0]),
      [60, 0]
    )
  }

  func testResolveOffsetsEmptyOverrideFallsBackToAtDueOnly() {
    // Phrased differently: the user deselects every chip. We don't fight
    // them; we just don't let them save a deadline-bearing item with zero
    // scheduled alerts.
    XCTAssertEqual(
      AppStore.resolveOffsets(override: [], kindDefault: [24 * 60, 60, 0]),
      [0]
    )
  }

  func testResolveOffsetsPopulatedOverrideWinsOverKindDefault() {
    XCTAssertEqual(
      AppStore.resolveOffsets(override: [30, 15], kindDefault: [60, 0]),
      [30, 15]
    )
  }

  // MARK: - editDueAt drops prior alert rows

  func testEditDueAtDropsPriorAlertsBeforeRescheduling() async throws {
    let item = try await insertCapturedItem(title: "kickoff the deck")
    // Pre-seed two stale Alert rows that a prior schedule would have left
    // behind. editDueAt must wipe them — even though `enableNotifications`
    // is false (so no fresh ones are written), the deletion path runs.
    try await store.alertRepository.insert(Alert(itemId: item.id, offsetMinutes: 60))
    try await store.alertRepository.insert(Alert(itemId: item.id, offsetMinutes: 0))

    let due = Date(timeIntervalSince1970: 1_800_000_000)
    await store.editDueAt(item, dueAt: due, dueKind: .datetime, offsetsOverride: [15])

    let remaining = try await store.alertRepository.allForItem(item.id)
    XCTAssertTrue(
      remaining.isEmpty,
      "stale alerts must be cleared before re-scheduling; got \(remaining.count)"
    )
  }
}
