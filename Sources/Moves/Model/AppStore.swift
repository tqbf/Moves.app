import Foundation
import Observation
import UserNotifications

/// Main-actor-bound view-model root for the app. Owns the database actor,
/// the repositories, the reminder/notification surface, and the cached
/// working-hours config that drives §6 visibility filtering.
///
/// Phase-4 decision (carrying forward the Phase-1 deferred recommendation):
/// the repo set is now non-optional. `init` traps if the DB can't open. The
/// previous Optional pattern was a hedge against a UI surface that would
/// distinguish "DB broken" from "DB empty" — Phase 4's settings work
/// resolved that: working-hours settings only meaningfully render *after*
/// the DB is open, and there's no other settings-flavored copy that needs
/// the soft-fail path. If the DB can't open, nothing in the app works and
/// we'd rather crash hard in dev than render a misleading empty surface.
@Observable
@MainActor
final class AppStore {
  // MARK: - View state

  private(set) var threads: [Thread] = []
  private(set) var capturedItems: [Item] = []
  private(set) var dueOrOverdueHardCount: Int = 0
  private(set) var loadError: String?

  /// Cached `current_state` row. Mirrors the single-row table so the
  /// popover can read it synchronously without an async hop. Reset to
  /// `.empty` when stop/park/clear is called.
  private(set) var current: CurrentState = .empty

  /// Items projection that drives the popover's Upcoming section
  /// (`HeadroomService` consumes this). Refreshed alongside the captured
  /// feed; both are fed by `ItemRepository.upcomingHard(now:)`.
  private(set) var upcomingItems: [Item] = []

  /// Per-thread resolved moves for the Available list. Computed on every
  /// reload by running `MoveResolver.resolve` over each thread's segments
  /// + open items. Threads with no re-entry move are absent — that's the
  /// §22 invariant. Ordering matches `threads` (last_touched_at DESC).
  private(set) var availableThreads: [AvailableThread] = []

  /// Open items grouped by thread id. Used by §6's "deadline-bearing"
  /// carve-out (`hide_during_work` / `only_during_work` honor a non-nil
  /// `due_at` on any open item to keep the thread visible). Rebuilt
  /// alongside `availableThreads`.
  private(set) var openItemsByThread: [String: [Item]] = [:]

  /// Segments grouped by thread id, refreshed by `rebuildAvailable`. Used
  /// by the Phase-5 `SegmentsPanel` so the thread-detail view doesn't have
  /// to re-query on every render, and by `currentSegment(for:)` so the
  /// popover can show the displayed segment without an async hop.
  private(set) var segmentsByThread: [String: [Segment]] = [:]

  /// Cached working-hours config from the `settings` table. Defaults
  /// to `.default` until `loadWorkingHours()` resolves a stored row.
  private(set) var workingHours: WorkingHours = .default

  /// True if the most recent `isWorkTimeTick` call put us inside the
  /// working-hours window. Driven by a `TimelineView` in the main window
  /// (and recomputed on settings save). The popover's de-emphasis section
  /// also reads this.
  private(set) var isWorkTime: Bool = false

  /// Context for the currently-presenting flow sheet (Stop/Switch/Park).
  /// Sheets are separate `Window` scenes; they observe this value to know
  /// which thread they're acting on. The popover sets it before calling
  /// `openWindow(id:)`; the sheet clears it on dismiss.
  var pendingFlow: FlowContext?
  /// Set after the user has tried to schedule a reminder and been denied
  /// notification permission. Drives the "alerts disabled" affordance in the
  /// capture palette.
  private(set) var notificationsDenied: Bool = false

  /// User-facing parser result for the most recent capture. Drives the
  /// "Saved reminder: …" / "Saved capture: …" confirmation line in the
  /// capture palette. Cleared on next capture or when the palette closes.
  private(set) var lastCapture: ParsedCapture?

  // MARK: - Persistence + services

  let database: Database
  let threadRepository: ThreadRepository
  let segmentRepository: SegmentRepository
  let itemRepository: ItemRepository
  let alertRepository: AlertRepository
  let currentStateRepository: CurrentStateRepository
  let timeLogRepository: TimeLogRepository
  let settingsRepository: SettingsRepository
  let reminderScheduler: ReminderScheduler?

  /// Settings-table key for the working-hours JSON blob.
  static let workingHoursSettingsKey = "working_hours"

  /// Designated initializer. Accepts an explicit path so tests can point
  /// at a temp directory; production constructs from `Database.defaultURL()`.
  /// `enableNotifications` lets test bundles skip the
  /// `UNUserNotificationCenter.current()` call, which throws inside the
  /// SwiftPM xctest host (no proper main bundle).
  ///
  /// Traps on DB-open failure (see type-level note above).
  init(
    databasePath: String = Database.defaultURL().path(percentEncoded: false),
    enableNotifications: Bool = true
  ) {
    do {
      let db = try Database(path: databasePath)
      let alerts = AlertRepository(database: db)
      self.database = db
      self.threadRepository = ThreadRepository(database: db)
      self.segmentRepository = SegmentRepository(database: db)
      self.itemRepository = ItemRepository(database: db)
      self.alertRepository = alerts
      self.currentStateRepository = CurrentStateRepository(database: db)
      self.timeLogRepository = TimeLogRepository(database: db)
      self.settingsRepository = SettingsRepository(database: db)
      self.reminderScheduler = enableNotifications
        ? ReminderScheduler(alertRepository: alerts)
        : nil
    } catch {
      fatalError("Moves failed to open its database at \(databasePath): \(error)")
    }
  }

  // MARK: - Lifecycle

  func load() async {
    await loadWorkingHours()
    await reloadThreads()
    await reloadCaptured()
    await reloadUpcoming()
    await reloadCurrent()
    await refreshDueCount()
    await rebuildAvailable()
    refreshWorkTime(now: Date())
  }

  func reloadThreads() async {
    do {
      threads = try await threadRepository.all()
    } catch {
      loadError = "Load failed: \(error)"
    }
  }

  func reloadCurrent() async {
    do {
      current = try await currentStateRepository.get()
    } catch {
      loadError = "Current load failed: \(error)"
    }
  }

  func reloadUpcoming() async {
    let now = Int64(Date().timeIntervalSince1970)
    do {
      // upcomingHard returns hard-only future items — fine for headroom,
      // which is hard-only by §2.10 / §4.1. Soft items show in the popover
      // Upcoming section as "other" but aren't part of the runway calc.
      upcomingItems = try await itemRepository.upcomingHard(now: now)
    } catch {
      loadError = "Upcoming load failed: \(error)"
    }
  }

  /// Rebuild the Available projection: per-thread `MoveResolver.resolve`
  /// over segments + open items. Threads whose resolved move is nil are
  /// excluded — §22's "no re-entry, no Available" invariant.
  ///
  /// Also fills `openItemsByThread` so §6's deadline-bearing carve-out
  /// (`hide_during_work` / `only_during_work`) can be tested view-side
  /// without re-querying.
  func rebuildAvailable() async {
    var built: [AvailableThread] = []
    var openItems: [String: [Item]] = [:]
    var segmentsCache: [String: [Segment]] = [:]
    for thread in threads where thread.status == .active {
      do {
        let segments = thread.kind == .regimented
          ? try await segmentRepository.forThread(thread.id)
          : []
        let items = try await itemRepository.openForThread(thread.id)
        openItems[thread.id] = items
        if thread.kind == .regimented {
          segmentsCache[thread.id] = segments
        }
        if let move = MoveResolver.resolve(thread: thread, segments: segments, openItems: items) {
          built.append(AvailableThread(thread: thread, move: move))
        }
      } catch {
        loadError = "Available rebuild failed: \(error)"
      }
    }
    availableThreads = built
    openItemsByThread = openItems
    segmentsByThread = segmentsCache
  }

  func reloadCaptured() async {
    do {
      capturedItems = try await itemRepository.captured()
    } catch {
      loadError = "Captured load failed: \(error)"
    }
  }

  /// Recompute the menu-bar badge count. Counts items whose
  /// `interruption_kind = .hard` and whose `due_at <= now` (i.e. due-now or
  /// overdue), per INITIAL-PLAN.md §16: badge is hard-only, ignores soft
  /// and ordinary captures.
  func refreshDueCount() async {
    let now = Int64(Date().timeIntervalSince1970)
    do {
      dueOrOverdueHardCount = try await itemRepository.dueOrOverdueHardCount(now: now)
    } catch {
      loadError = "Badge refresh failed: \(error)"
    }
  }

  // MARK: - Working hours (Phase 4)

  /// Read the persisted working-hours JSON from `settings`. Falls back to
  /// `.default` on missing-or-malformed rows. Idempotent — safe to call from
  /// `load()` and again after a settings save.
  func loadWorkingHours() async {
    do {
      let raw = try await settingsRepository.get(Self.workingHoursSettingsKey)
      if let raw, let parsed = WorkingHours.decodedJSON(raw) {
        workingHours = parsed
      } else {
        workingHours = .default
      }
    } catch {
      loadError = "Working hours load failed: \(error)"
      workingHours = .default
    }
  }

  /// Persist a working-hours change to `settings`, update the cache, and
  /// recompute `isWorkTime` for the current moment. The Available view
  /// re-renders automatically via @Observable.
  func saveWorkingHours(_ hours: WorkingHours) async {
    do {
      try await settingsRepository.set(Self.workingHoursSettingsKey, value: hours.encodedJSON())
      workingHours = hours
      refreshWorkTime(now: Date())
    } catch {
      loadError = "Working hours save failed: \(error)"
    }
  }

  /// Recompute `isWorkTime` for the supplied `now`. Cheap (`WorkingHours
  /// Service.isInside` is pure) — call freely from a `TimelineView`.
  func refreshWorkTime(now: Date) {
    isWorkTime = WorkingHoursService.isInside(date: now, hours: workingHours)
  }

  // MARK: - Capture (Phase 2)

  /// Parse a capture string, persist the resulting item, and (if it has a
  /// `due_at`) schedule a notification. Returns the parsed projection so the
  /// caller can render the confirm line. If parsing yields an empty title,
  /// the capture is dropped and nil is returned.
  @discardableResult
  func capture(_ input: String, now: Date = Date()) async -> ParsedCapture? {
    let parsed = CaptureParser.parse(input, now: now)
    guard !parsed.title.isEmpty else { return nil }

    let dueAtSeconds = parsed.dueAt.map { Int64($0.timeIntervalSince1970) }
    let itemKind: ItemKind = {
      switch parsed.interruptionKind {
      case .hard: return .reminder
      case .soft: return .task
      case .none: return .capture
      }
    }()

    let createdAt = Int64(now.timeIntervalSince1970)
    let item = Item(
      threadId: nil,
      segmentId: nil,
      title: parsed.title,
      bodyMarkdown: "",
      status: .captured,
      kind: itemKind,
      dueAt: dueAtSeconds,
      dueKind: parsed.dueKind,
      interruptionKind: parsed.interruptionKind,
      createdAt: createdAt,
      updatedAt: createdAt,
      completedAt: nil
    )

    do {
      try await itemRepository.insert(item)
    } catch {
      loadError = "Capture insert failed: \(error)"
      return nil
    }

    // Schedule the at-due notification if applicable. The scheduler handles
    // the authorization-on-first-capture flow.
    if parsed.dueAt != nil, let reminderScheduler {
      do {
        _ = try await reminderScheduler.scheduleAtDue(item: item)
        notificationsDenied = reminderScheduler.authorizationStatus == .denied
      } catch {
        loadError = "Notification schedule failed: \(error)"
      }
    }

    lastCapture = parsed
    await reloadCaptured()
    await refreshDueCount()
    return parsed
  }

  /// Clear the "Saved reminder: …" confirmation line. Called when the
  /// capture palette dismisses.
  func clearLastCapture() {
    lastCapture = nil
  }

  // MARK: - Notification delegate routing

  /// Called by `NotificationDelegate` for every notification response. Maps
  /// snooze action identifiers back to scheduler calls; default action
  /// (`UNNotificationDefaultActionIdentifier`) just marks the alert fired.
  func handleNotificationResponse(
    actionId: String,
    itemId: String,
    alertId: String,
    title: String
  ) async {
    guard let reminderScheduler else { return }
    do {
      if let snooze = ReminderScheduler.SnoozeOffset.allCases.first(where: { $0.actionIdentifier == actionId }) {
        try await reminderScheduler.snooze(
          itemId: itemId,
          alertId: alertId,
          title: title,
          offset: snooze
        )
      } else {
        try await reminderScheduler.markFired(alertId: alertId)
      }
      await reloadCaptured()
      await refreshDueCount()
    } catch {
      loadError = "Snooze handling failed: \(error)"
    }
  }

  // MARK: - Current-state flows (Phase 3)

  /// Set `thread` as the current thread. Touches `last_touched_at` so the
  /// thread floats to the top of Available (§12 v1 ordering). The
  /// `started_at` field records when this Current began for §5.1's coarse
  /// "later" estimate. No segment selection: a future phase 5 may attach
  /// the displayed segment, but Phase 3 never advances segments.
  func start(_ thread: Thread) async {
    let now = Int64(Date().timeIntervalSince1970)
    let state = CurrentState(threadId: thread.id, segmentId: nil, startedAt: now)
    do {
      try await currentStateRepository.set(state)
      current = state
      await touch(threadId: thread.id, at: now)
      await rebuildAvailable()
    } catch {
      loadError = "Start failed: \(error)"
    }
  }

  /// Clear Current. Persists the edited breadcrumb on the previously-
  /// current thread, writes a `TimeLogEntry` for the rough-time bucket
  /// (skipped when `rough == .none`), and re-touches the thread (§12).
  func stop(breadcrumb: String, rough: RoughTimeBucket) async {
    guard let threadId = current.threadId else { return }
    do {
      try await applyBreadcrumb(to: threadId, breadcrumb: breadcrumb)
      try await currentStateRepository.clear()
      current = .empty
      try await logRoughTime(threadId: threadId, segmentId: nil, rough: rough)
      await rebuildAvailable()
    } catch {
      loadError = "Stop failed: \(error)"
    }
  }

  /// Switch from the current thread to `target`. Persists breadcrumb on
  /// the *previous* thread, logs rough time against the previous thread,
  /// then sets `target` as current (which also touches `target`).
  func switchTo(_ target: Thread, breadcrumb: String, rough: RoughTimeBucket) async {
    guard let previousId = current.threadId else {
      // No prior current — degenerate to start.
      await start(target)
      return
    }
    do {
      try await applyBreadcrumb(to: previousId, breadcrumb: breadcrumb)
      try await logRoughTime(threadId: previousId, segmentId: nil, rough: rough)
    } catch {
      loadError = "Switch save failed: \(error)"
      return
    }
    await start(target)
  }

  /// Park `thread`. Saves the breadcrumb (required by §5.4), flips status
  /// to parked, and — if it was the current thread — clears Current. No
  /// rough-time prompt (parking ≠ stopping, per the Phase 3 plan).
  func park(_ thread: Thread, breadcrumb: String) async {
    do {
      try await applyBreadcrumb(to: thread.id, breadcrumb: breadcrumb)
      try await applyStatus(threadId: thread.id, status: .parked)
      if current.threadId == thread.id {
        try await currentStateRepository.clear()
        current = .empty
      }
      await rebuildAvailable()
    } catch {
      loadError = "Park failed: \(error)"
    }
  }

  // MARK: - Flow helpers

  /// Persist a breadcrumb edit on `threadId` and re-touch the row (§12:
  /// breadcrumb edits update last_touched_at). The in-memory `threads`
  /// array is updated to match so the popover renders immediately.
  private func applyBreadcrumb(to threadId: String, breadcrumb: String) async throws {
    guard let idx = threads.firstIndex(where: { $0.id == threadId }) else { return }
    let now = Int64(Date().timeIntervalSince1970)
    threads[idx].breadcrumb = breadcrumb
    threads[idx].updatedAt = now
    threads[idx].lastTouchedAt = now
    try await threadRepository.update(threads[idx])
  }

  private func applyStatus(threadId: String, status: ThreadStatus) async throws {
    guard let idx = threads.firstIndex(where: { $0.id == threadId }) else { return }
    let now = Int64(Date().timeIntervalSince1970)
    threads[idx].status = status
    threads[idx].updatedAt = now
    try await threadRepository.update(threads[idx])
  }

  /// Update `last_touched_at` for `threadId` (no other thread fields) and
  /// resort the in-memory array. Used on Current changes (§12: any current
  /// change re-touches the affected thread).
  private func touch(threadId: String, at now: Int64) async {
    guard let idx = threads.firstIndex(where: { $0.id == threadId }) else { return }
    threads[idx].lastTouchedAt = now
    threads[idx].updatedAt = now
    do {
      try await threadRepository.update(threads[idx])
    } catch {
      loadError = "Touch failed: \(error)"
    }
    // Resort by last_touched_at DESC to match the repo's ORDER BY.
    threads.sort { lhs, rhs in
      let l = lhs.lastTouchedAt ?? Int64.min
      let r = rhs.lastTouchedAt ?? Int64.min
      if l != r { return l > r }
      return lhs.createdAt > rhs.createdAt
    }
  }

  /// Insert a `TimeLogEntry` for the rough-time bucket. Skips when the
  /// bucket is `.none` (the user said "no, not really" — store nothing).
  private func logRoughTime(
    threadId: String,
    segmentId: String?,
    rough: RoughTimeBucket
  ) async throws {
    guard let minutes = rough.minutes else { return }
    let entry = TimeLogEntry(
      threadId: threadId,
      segmentId: segmentId,
      weekStart: Self.weekStartString(for: Date()),
      roughMinutes: minutes
    )
    try await timeLogRepository.insert(entry)
  }

  /// `YYYY-MM-DD` for the Monday of the current ISO week. Delegates to
  /// `TimeLogService.weekStart(for:)` so the writer (stop/switch/complete-
  /// segment) and reader (`weeklyView(for:)`) agree on the bucket key.
  static func weekStartString(for date: Date) -> String {
    TimeLogService.weekStart(for: date)
  }

  // MARK: - Thread editing (Phase 4)

  func addThread(title: String) {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    let thread = Thread(title: trimmed)
    threads.insert(thread, at: 0)
    Task { [threadRepository] in
      do { try await threadRepository.insert(thread) }
      catch { self.report("Insert failed: \(error)") }
    }
  }

  /// Insert a new thread and return its id so the caller can navigate to it.
  /// Used by the main-window "New Thread" button so the user lands inside
  /// the row they just created.
  @discardableResult
  func createThread(title: String) async -> String? {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let thread = Thread(title: trimmed)
    do {
      try await threadRepository.insert(thread)
      threads.insert(thread, at: 0)
      await rebuildAvailable()
      return thread.id
    } catch {
      loadError = "Insert failed: \(error)"
      return nil
    }
  }

  func rename(_ thread: Thread, to title: String) {
    guard let idx = threads.firstIndex(of: thread) else { return }
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed != thread.title else { return }
    threads[idx].title = trimmed
    threads[idx].updatedAt = Int64(Date().timeIntervalSince1970)
    persist(threads[idx])
  }

  func updateBreadcrumb(_ thread: Thread, to breadcrumb: String) {
    guard let idx = threads.firstIndex(of: thread) else { return }
    // §12: breadcrumb edits re-touch.
    let now = Int64(Date().timeIntervalSince1970)
    threads[idx].breadcrumb = breadcrumb
    threads[idx].updatedAt = now
    threads[idx].lastTouchedAt = now
    persist(threads[idx])
    Task { await rebuildAvailable() }
  }

  func updateDetailMarkdown(_ thread: Thread, to markdown: String) {
    guard let idx = threads.firstIndex(of: thread) else { return }
    threads[idx].detailMarkdown = markdown
    threads[idx].updatedAt = Int64(Date().timeIntervalSince1970)
    persist(threads[idx])
  }

  func setStatus(_ thread: Thread, to status: ThreadStatus) {
    guard let idx = threads.firstIndex(of: thread) else { return }
    threads[idx].status = status
    threads[idx].updatedAt = Int64(Date().timeIntervalSince1970)
    persist(threads[idx])
    Task { await rebuildAvailable() }
  }

  func setKind(_ thread: Thread, to kind: ThreadKind) {
    guard let idx = threads.firstIndex(of: thread) else { return }
    threads[idx].kind = kind
    threads[idx].updatedAt = Int64(Date().timeIntervalSince1970)
    persist(threads[idx])
  }

  /// Set the §6 visibility policy on `thread`. Drives the de-emphasize /
  /// hide / only-during-work behavior on the Available list.
  func setVisibility(_ thread: Thread, to visibility: ThreadVisibility) {
    guard let idx = threads.firstIndex(of: thread) else { return }
    threads[idx].visibility = visibility
    threads[idx].updatedAt = Int64(Date().timeIntervalSince1970)
    persist(threads[idx])
  }

  func delete(_ thread: Thread) {
    threads.removeAll { $0.id == thread.id }
    Task { [threadRepository, id = thread.id] in
      do { try await threadRepository.delete(id: id) }
      catch { self.report("Delete failed: \(error)") }
    }
  }

  func thread(id: String) -> Thread? {
    threads.first { $0.id == id }
  }

  var activeCount: Int { threads.lazy.filter { $0.status == .active }.count }

  // MARK: - Item editing (Phase 4)

  /// Toggle an item's status between `.open` and `.done`. Used by the
  /// thread-detail items checklist. Persists, then reloads the captured
  /// feed (which may now include or exclude this item) and rebuilds
  /// Available because §22's "no open items → no Available" can flip on
  /// the last open item completing.
  func toggleItemDone(_ item: Item) async {
    let updated = nextStatus(for: item)
    var copy = item
    copy.status = updated
    copy.updatedAt = Int64(Date().timeIntervalSince1970)
    copy.completedAt = updated == .done ? copy.updatedAt : nil
    do {
      try await itemRepository.update(copy)
      await reloadCaptured()
      await rebuildAvailable()
      await refreshDueCount()
    } catch {
      loadError = "Item toggle failed: \(error)"
    }
  }

  private func nextStatus(for item: Item) -> ItemStatus {
    switch item.status {
    case .done: return .open
    case .canceled: return .open
    case .open, .captured: return .done
    }
  }

  /// Attach a captured item to a thread. Persists the change and reloads.
  /// Used by the Captured row's "Attach to thread" picker.
  func attachToThread(_ threadId: String, item: Item) async {
    var copy = item
    copy.threadId = threadId
    // Captured items become `.open` once they have a home.
    copy.status = .open
    copy.updatedAt = Int64(Date().timeIntervalSince1970)
    do {
      try await itemRepository.update(copy)
      await reloadCaptured()
      await rebuildAvailable()
      await refreshDueCount()
    } catch {
      loadError = "Attach failed: \(error)"
    }
  }

  /// Convert a captured item between `task` and `reminder` (and back to
  /// `capture` if needed). Adjusts `interruption_kind` to match the new
  /// kind so the badge query / popover icons stay coherent (§16: hard-only
  /// badge comes from `interruption_kind = .hard`).
  func convertItemKind(_ item: Item, to kind: ItemKind) async {
    var copy = item
    copy.kind = kind
    switch kind {
    case .reminder: copy.interruptionKind = .hard
    case .task: copy.interruptionKind = .soft
    case .capture: copy.interruptionKind = .none
    }
    copy.updatedAt = Int64(Date().timeIntervalSince1970)
    do {
      try await itemRepository.update(copy)
      await reloadCaptured()
      await refreshDueCount()
    } catch {
      loadError = "Convert failed: \(error)"
    }
  }

  /// Mark a captured/open item done. Persists `completed_at` so phase 5/6
  /// can show a completion history.
  func markItemDone(_ item: Item) async {
    var copy = item
    copy.status = .done
    let now = Int64(Date().timeIntervalSince1970)
    copy.updatedAt = now
    copy.completedAt = now
    do {
      try await itemRepository.update(copy)
      await reloadCaptured()
      await rebuildAvailable()
      await refreshDueCount()
    } catch {
      loadError = "Mark done failed: \(error)"
    }
  }

  /// Cancel an item — no completion timestamp, status moves to `.canceled`.
  /// Distinct from delete: keeps a row for audit / undo.
  func cancelItem(_ item: Item) async {
    var copy = item
    copy.status = .canceled
    copy.updatedAt = Int64(Date().timeIntervalSince1970)
    do {
      try await itemRepository.update(copy)
      await reloadCaptured()
      await rebuildAvailable()
      await refreshDueCount()
    } catch {
      loadError = "Cancel failed: \(error)"
    }
  }

  /// Edit the `due_at` (and matching `due_kind`) for a captured item.
  /// Passing nil clears the deadline. The notification is rescheduled (or
  /// cancelled) to match.
  func editDueAt(_ item: Item, dueAt: Date?, dueKind: DueKind) async {
    var copy = item
    if let dueAt {
      copy.dueAt = Int64(dueAt.timeIntervalSince1970)
      copy.dueKind = dueKind
    } else {
      copy.dueAt = nil
      copy.dueKind = .none
    }
    copy.updatedAt = Int64(Date().timeIntervalSince1970)
    do {
      try await itemRepository.update(copy)
      if let reminderScheduler {
        await reminderScheduler.cancelPending(itemId: copy.id)
        if copy.dueAt != nil, copy.interruptionKind == .hard {
          _ = try? await reminderScheduler.scheduleAtDue(item: copy)
        }
      }
      await reloadCaptured()
      await refreshDueCount()
    } catch {
      loadError = "Edit due failed: \(error)"
    }
  }

  // MARK: - Captured item editing (Phase 2 carry-over)

  /// Delete a captured item by ID.
  func deleteCapturedItem(_ item: Item) {
    capturedItems.removeAll { $0.id == item.id }
    Task { [itemRepository, reminderScheduler, id = item.id] in
      await reminderScheduler?.cancelPending(itemId: id)
      do { try await itemRepository.delete(id: id) }
      catch { self.report("Item delete failed: \(error)") }
      await self.refreshDueCount()
    }
  }

  // MARK: - Convenience read projections

  /// Threads matching `status`, used by Parking Lot / Threads list panes.
  func threads(matching status: ThreadStatus) -> [Thread] {
    threads.filter { $0.status == status }
  }

  /// All items with a non-nil `due_at` ordered ascending. Drives the
  /// Deadlines pane. Returns directly from the in-memory `capturedItems` +
  /// `openItemsByThread` projections — Phase 4's deadlines pane doesn't
  /// need a fresh repo round-trip.
  var deadlineItems: [Item] {
    var all: [Item] = []
    all.append(contentsOf: capturedItems.filter { $0.dueAt != nil })
    for (_, items) in openItemsByThread {
      all.append(contentsOf: items.filter { $0.dueAt != nil })
    }
    return all.sorted { ($0.dueAt ?? .max) < ($1.dueAt ?? .max) }
  }

  // MARK: - Internal

  private func persist(_ thread: Thread) {
    Task { [threadRepository] in
      do { try await threadRepository.update(thread) }
      catch { self.report("Update failed: \(error)") }
    }
  }

  private func report(_ message: String) {
    loadError = message
  }

  // MARK: - Segment lifecycle (Phase 5)

  /// Currently-displayed segment for a thread per `MoveResolver.displayedSegment`
  /// rules (active wins; else first pending by orderIndex). Reads from the
  /// cached `segmentsByThread` to avoid a DB round-trip.
  func currentSegment(for thread: Thread) -> Segment? {
    guard thread.kind == .regimented else { return nil }
    let segments = segmentsByThread[thread.id] ?? []
    return MoveResolver.displayedSegment(for: segments)
  }

  /// Fetch all segments for a thread (any status) and cache the result.
  /// Used by the thread-detail SegmentsPanel which needs Done/Skipped rows
  /// too, not just the active/pending set `rebuildAvailable` cares about.
  func loadSegments(for threadId: String) async {
    do {
      let segments = try await segmentRepository.forThread(threadId)
      segmentsByThread[threadId] = segments
    } catch {
      loadError = "Segment load failed: \(error)"
    }
  }

  /// Set `segment` as the thread's active segment. Demotes any other active
  /// segments on the same thread back to `.pending` so the §3 invariant
  /// "only one segment is active per regimented thread" holds.
  ///
  /// Used by `SegmentsPanel`'s "Make active" affordance and by
  /// `completeActiveSegment(thread:rough:)` to promote the next pending row.
  func activateSegment(_ segment: Segment) async {
    let threadId = segment.threadId
    let now = Int64(Date().timeIntervalSince1970)
    do {
      let segments: [Segment]
      if let cached = segmentsByThread[threadId] {
        segments = cached
      } else {
        segments = (try? await segmentRepository.forThread(threadId)) ?? []
      }
      for var other in segments where other.status == .active && other.id != segment.id {
        other.status = .pending
        other.updatedAt = now
        try await segmentRepository.update(other)
      }
      var copy = segment
      copy.status = .active
      copy.updatedAt = now
      try await segmentRepository.update(copy)
      await loadSegments(for: threadId)
      await rebuildAvailable()
    } catch {
      loadError = "Activate segment failed: \(error)"
    }
  }

  /// Mark the active segment of `thread` done, log rough time against it,
  /// and advance to the next pending segment (the lowest `orderIndex` row
  /// among `.pending`). The next-segment promotion follows §5.5: explicit
  /// advancement only — switching, parking, and stopping do not touch
  /// segment status.
  ///
  /// If no pending segment remains, the thread is left without an active
  /// segment; `MoveResolver` will fall through to open items (§11.3) or
  /// surface nothing (§22).
  func completeActiveSegment(thread: Thread, rough: RoughTimeBucket) async {
    guard thread.kind == .regimented else { return }
    do {
      let segments = try await segmentRepository.forThread(thread.id)
      guard let active = segments.first(where: { $0.status == .active }) else {
        // No active segment → nothing to complete. Defensive guard.
        loadError = "No active segment on \(thread.title)."
        return
      }
      let now = Int64(Date().timeIntervalSince1970)
      var done = active
      done.status = .done
      done.updatedAt = now
      try await segmentRepository.update(done)

      // Log rough time attributed to the (thread, segment) per §14.
      try await logRoughTime(threadId: thread.id, segmentId: active.id, rough: rough)

      // Promote the next pending segment (lowest orderIndex) to active.
      let nextPending = segments
        .filter { $0.status == .pending && $0.id != active.id }
        .sorted { $0.orderIndex < $1.orderIndex }
        .first
      if let next = nextPending {
        var promoted = next
        promoted.status = .active
        promoted.updatedAt = now
        try await segmentRepository.update(promoted)
      }
      await loadSegments(for: thread.id)
      await rebuildAvailable()
    } catch {
      loadError = "Complete segment failed: \(error)"
    }
  }

  /// Skip a segment without logging time. Used by `SegmentsPanel`'s
  /// "Skip" overflow action. If the skipped segment was active, the next
  /// pending segment is promoted (same rules as completion) — without this,
  /// a skipped active would leave the thread silently de-activated.
  func skipSegment(_ segment: Segment) async {
    let now = Int64(Date().timeIntervalSince1970)
    do {
      var copy = segment
      copy.status = .skipped
      copy.updatedAt = now
      try await segmentRepository.update(copy)

      if segment.status == .active {
        let segments = try await segmentRepository.forThread(segment.threadId)
        let nextPending = segments
          .filter { $0.status == .pending }
          .sorted { $0.orderIndex < $1.orderIndex }
          .first
        if let next = nextPending {
          var promoted = next
          promoted.status = .active
          promoted.updatedAt = now
          try await segmentRepository.update(promoted)
        }
      }
      await loadSegments(for: segment.threadId)
      await rebuildAvailable()
    } catch {
      loadError = "Skip segment failed: \(error)"
    }
  }

  /// Append a new pending segment to `thread`. Order index is `count`
  /// (zero-based) so new segments land at the bottom of the list.
  @discardableResult
  func addSegment(
    thread: Thread,
    title: String,
    builtInMove: String = "",
    body: String = ""
  ) async -> Segment? {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    do {
      let existing = try await segmentRepository.forThread(thread.id)
      let segment = Segment(
        threadId: thread.id,
        title: trimmed,
        orderIndex: existing.count,
        bodyMarkdown: body,
        builtInMove: builtInMove,
        status: .pending
      )
      try await segmentRepository.insert(segment)
      await loadSegments(for: thread.id)
      await rebuildAvailable()
      return segment
    } catch {
      loadError = "Add segment failed: \(error)"
      return nil
    }
  }

  /// Update an existing segment (title / body / built-in move / etc.).
  /// Persists, re-bumps `updatedAt`, refreshes caches.
  func editSegment(_ segment: Segment) async {
    var copy = segment
    copy.updatedAt = Int64(Date().timeIntervalSince1970)
    do {
      try await segmentRepository.update(copy)
      await loadSegments(for: segment.threadId)
      await rebuildAvailable()
    } catch {
      loadError = "Edit segment failed: \(error)"
    }
  }

  // MARK: - Markdown import (Phase 5)

  /// Parse `source` as a §9 Markdown import and persist all rows in one
  /// transactional pass. Re-imports of the same title produce a new thread
  /// (v1 is create-only per the Phase 5 plan); a warning is appended.
  ///
  /// Returns a result describing what landed so the import view can show a
  /// confirmation toast and navigate to the new thread.
  @discardableResult
  func importMarkdown(_ source: String, now: Date = Date()) async -> ImportResult? {
    var preview = MarkdownImportService.parse(source, now: now)
    // Surface a warning for duplicate titles before the commit.
    if threads.contains(where: { $0.title == preview.thread.title }) {
      preview.warnings.append(
        "A thread titled '\(preview.thread.title)' already exists. Import creates a new thread (v1 is create-only)."
      )
    }
    do {
      try await threadRepository.insert(preview.thread)
      for segment in preview.segments {
        try await segmentRepository.insert(segment)
      }
      for item in preview.items {
        try await itemRepository.insert(item)
      }
      await reloadThreads()
      await reloadCaptured()
      await rebuildAvailable()
      return ImportResult(
        threadId: preview.thread.id,
        segmentCount: preview.segments.count,
        itemCount: preview.items.count,
        warnings: preview.warnings
      )
    } catch {
      loadError = "Markdown import failed: \(error)"
      return nil
    }
  }

  // MARK: - Weekly view (Phase 5 / §14)

  /// Aggregate rough-time minutes per thread for the ISO week containing
  /// `date`. Reads from `time_log` directly so the projection isn't tied to
  /// any in-memory cache: prior weeks remain queryable as the user navigates
  /// back with the prev/next chrome.
  func weeklyView(for date: Date) async -> WeeklySummary {
    let weekStart = TimeLogService.weekStart(for: date)
    do {
      let entries = try await timeLogRepository.forWeek(weekStart)
      let aggregates = TimeLogService.aggregate(entries: entries)
      return WeeklySummary(weekStart: weekStart, entries: aggregates)
    } catch {
      loadError = "Weekly view load failed: \(error)"
      return WeeklySummary.empty(weekStart: weekStart)
    }
  }
}
