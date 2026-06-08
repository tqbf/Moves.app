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

  init() {
    do {
      let db = try Database(path: Database.defaultURL().path(percentEncoded: false))
      let alerts = AlertRepository(database: db)
      self.database = db
      self.threadRepository = ThreadRepository(database: db)
      self.segmentRepository = SegmentRepository(database: db)
      self.itemRepository = ItemRepository(database: db)
      self.alertRepository = alerts
      self.currentStateRepository = CurrentStateRepository(database: db)
      self.timeLogRepository = TimeLogRepository(database: db)
      self.settingsRepository = SettingsRepository(database: db)
      self.reminderScheduler = ReminderScheduler(alertRepository: alerts)
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
    await refreshDueCount()
  }

  func reloadThreads() async {
    guard let threadRepository else { return }
    do {
      threads = try await threadRepository.all()
    } catch {
      loadError = "Load failed: \(error)"
    }
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
