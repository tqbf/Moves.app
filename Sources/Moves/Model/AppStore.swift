import Foundation
import Observation
import UserNotifications

/// Main-actor-bound view-model root for the app. Owns the database actor,
/// the repositories, and the Phase 2 reminder/notification surface. Surfaces
/// the slice of state the (currently throwaway) UI needs: lists of threads
/// and captured items, plus the due-or-overdue hard count for the menu-bar
/// badge.
///
/// Phases 3–5 will replace these surfaces with the real popover/main-window
/// state.
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

  let database: Database?
  let threadRepository: ThreadRepository?
  let segmentRepository: SegmentRepository?
  let itemRepository: ItemRepository?
  let alertRepository: AlertRepository?
  let currentStateRepository: CurrentStateRepository?
  let timeLogRepository: TimeLogRepository?
  let settingsRepository: SettingsRepository?
  let reminderScheduler: ReminderScheduler?

  /// Designated initializer. Accepts an explicit path so tests can point
  /// at a temp directory; production constructs from `Database.defaultURL()`.
  /// `enableNotifications` lets test bundles skip the
  /// `UNUserNotificationCenter.current()` call, which throws inside the
  /// SwiftPM xctest host (no proper main bundle).
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
      self.database = nil
      self.threadRepository = nil
      self.segmentRepository = nil
      self.itemRepository = nil
      self.alertRepository = nil
      self.currentStateRepository = nil
      self.timeLogRepository = nil
      self.settingsRepository = nil
      self.reminderScheduler = nil
      self.loadError = "Database failed to open: \(error)"
    }
  }

  // MARK: - Lifecycle

  func load() async {
    await reloadThreads()
    await reloadCaptured()
    await reloadUpcoming()
    await reloadCurrent()
    await refreshDueCount()
    await rebuildAvailable()
  }

  func reloadThreads() async {
    guard let threadRepository else { return }
    do {
      threads = try await threadRepository.all()
    } catch {
      loadError = "Load failed: \(error)"
    }
  }

  func reloadCurrent() async {
    guard let currentStateRepository else { return }
    do {
      current = try await currentStateRepository.get()
    } catch {
      loadError = "Current load failed: \(error)"
    }
  }

  func reloadUpcoming() async {
    guard let itemRepository else { return }
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
  func rebuildAvailable() async {
    guard let segmentRepository, let itemRepository else { return }
    var built: [AvailableThread] = []
    for thread in threads where thread.status == .active {
      do {
        let segments = thread.kind == .regimented
          ? try await segmentRepository.forThread(thread.id)
          : []
        let openItems = try await itemRepository.openForThread(thread.id)
        if let move = MoveResolver.resolve(thread: thread, segments: segments, openItems: openItems) {
          built.append(AvailableThread(thread: thread, move: move))
        }
      } catch {
        loadError = "Available rebuild failed: \(error)"
      }
    }
    availableThreads = built
  }

  func reloadCaptured() async {
    guard let itemRepository else { return }
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
    guard let itemRepository else { return }
    let now = Int64(Date().timeIntervalSince1970)
    do {
      dueOrOverdueHardCount = try await itemRepository.dueOrOverdueHardCount(now: now)
    } catch {
      loadError = "Badge refresh failed: \(error)"
    }
  }

  // MARK: - Capture (Phase 2)

  /// Parse a capture string, persist the resulting item, and (if it has a
  /// `due_at`) schedule a notification. Returns the parsed projection so the
  /// caller can render the confirm line. If parsing yields an empty title,
  /// the capture is dropped and nil is returned.
  @discardableResult
  func capture(_ input: String, now: Date = Date()) async -> ParsedCapture? {
    guard let itemRepository, let reminderScheduler else { return nil }
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
    if parsed.dueAt != nil {
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
    guard let currentStateRepository else { return }
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
    guard let threadRepository, let currentStateRepository, let timeLogRepository else { return }
    do {
      try await applyBreadcrumb(to: threadId, breadcrumb: breadcrumb, threadRepository: threadRepository)
      try await currentStateRepository.clear()
      current = .empty
      try await logRoughTime(threadId: threadId, segmentId: nil, rough: rough, timeLogRepository: timeLogRepository)
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
    guard let threadRepository, let timeLogRepository else { return }
    do {
      try await applyBreadcrumb(to: previousId, breadcrumb: breadcrumb, threadRepository: threadRepository)
      try await logRoughTime(threadId: previousId, segmentId: nil, rough: rough, timeLogRepository: timeLogRepository)
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
    guard let threadRepository, let currentStateRepository else { return }
    do {
      try await applyBreadcrumb(to: thread.id, breadcrumb: breadcrumb, threadRepository: threadRepository)
      try await applyStatus(threadId: thread.id, status: .parked, threadRepository: threadRepository)
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
  private func applyBreadcrumb(
    to threadId: String,
    breadcrumb: String,
    threadRepository: ThreadRepository
  ) async throws {
    guard let idx = threads.firstIndex(where: { $0.id == threadId }) else { return }
    let now = Int64(Date().timeIntervalSince1970)
    threads[idx].breadcrumb = breadcrumb
    threads[idx].updatedAt = now
    threads[idx].lastTouchedAt = now
    try await threadRepository.update(threads[idx])
  }

  private func applyStatus(
    threadId: String,
    status: ThreadStatus,
    threadRepository: ThreadRepository
  ) async throws {
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
    guard let threadRepository else { return }
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
    rough: RoughTimeBucket,
    timeLogRepository: TimeLogRepository
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

  /// `YYYY-MM-DD` for the Monday of the current local-calendar ISO week.
  /// Matches the migration's `idx_time_log_week` grouping intent (§14).
  static func weekStartString(for date: Date) -> String {
    var calendar = Calendar(identifier: .iso8601)
    calendar.firstWeekday = 2 // Monday
    let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
    let monday = calendar.date(from: components) ?? date
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: monday)
  }

  // MARK: - Thread editing (throwaway phase-1 plumbing)

  func addThread(title: String) {
    guard let threadRepository else { return }
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    let thread = Thread(title: trimmed)
    threads.insert(thread, at: 0)
    Task { [threadRepository] in
      do { try await threadRepository.insert(thread) }
      catch { self.report("Insert failed: \(error)") }
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
    threads[idx].breadcrumb = breadcrumb
    threads[idx].updatedAt = Int64(Date().timeIntervalSince1970)
    persist(threads[idx])
  }

  func setStatus(_ thread: Thread, to status: ThreadStatus) {
    guard let idx = threads.firstIndex(of: thread) else { return }
    threads[idx].status = status
    threads[idx].updatedAt = Int64(Date().timeIntervalSince1970)
    persist(threads[idx])
  }

  func delete(_ thread: Thread) {
    threads.removeAll { $0.id == thread.id }
    guard let threadRepository else { return }
    Task { [threadRepository, id = thread.id] in
      do { try await threadRepository.delete(id: id) }
      catch { self.report("Delete failed: \(error)") }
    }
  }

  func thread(id: String) -> Thread? {
    threads.first { $0.id == id }
  }

  var activeCount: Int { threads.lazy.filter { $0.status == .active }.count }

  // MARK: - Captured item editing

  /// Delete a captured item by ID. Used by the throwaway captured list.
  func deleteCapturedItem(_ item: Item) {
    capturedItems.removeAll { $0.id == item.id }
    guard let itemRepository, let reminderScheduler else { return }
    Task { [itemRepository, reminderScheduler, id = item.id] in
      await reminderScheduler.cancelPending(itemId: id)
      do { try await itemRepository.delete(id: id) }
      catch { self.report("Item delete failed: \(error)") }
      await self.refreshDueCount()
    }
  }

  // MARK: - Internal

  private func persist(_ thread: Thread) {
    guard let threadRepository else { return }
    Task { [threadRepository] in
      do { try await threadRepository.update(thread) }
      catch { self.report("Update failed: \(error)") }
    }
  }

  private func report(_ message: String) {
    loadError = message
  }
}
