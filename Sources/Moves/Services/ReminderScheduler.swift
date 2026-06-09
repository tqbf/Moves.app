import Foundation
import UserNotifications

/// Bridges captured items with deadlines to `UNUserNotificationCenter`.
/// Owns scheduling, snoozing, and cancellation; persists `Alert.fired_at`
/// after delivery so launch-time reconciliation in phase 6 has a record.
///
/// Multi-alert v1.1: `scheduleAlerts(item:offsetsMinutes:)` schedules one
/// notification per (positive future) offset, persisting one `Alert` row
/// each. Offsets <= 0 represent "at due time" or already-past fires and
/// are skipped if the resolved fire date is not in the future. Snooze
/// offsets are 5m / 15m / 1h (INITIAL-PLAN §16).
///
/// Notification authorization is requested lazily — on the first capture
/// that schedules a reminder, not on launch (Phase 2 decision). If the user
/// denies, the item is still saved; we just don't schedule anything.
@MainActor
final class ReminderScheduler {

  // MARK: - Snooze offsets (INITIAL-PLAN §16)

  enum SnoozeOffset: String, CaseIterable, Sendable {
    case fiveMinutes
    case fifteenMinutes
    case oneHour

    var seconds: TimeInterval {
      switch self {
      case .fiveMinutes: return 5 * 60
      case .fifteenMinutes: return 15 * 60
      case .oneHour: return 60 * 60
      }
    }

    var label: String {
      switch self {
      case .fiveMinutes: return "Snooze 5 min"
      case .fifteenMinutes: return "Snooze 15 min"
      case .oneHour: return "Snooze 1 hour"
      }
    }

    /// Action identifier registered with UNNotificationCategory.
    var actionIdentifier: String { "moves.snooze.\(rawValue)" }
  }

  // MARK: - Userinfo keys

  /// Notification `userInfo` carries these so the delegate can route taps
  /// and snoozes back into the database without re-parsing identifiers.
  enum UserInfoKey {
    static let itemId = "moves.itemId"
    static let alertId = "moves.alertId"
  }

  /// Single notification category — one shape of action set (the three
  /// snooze offsets). Registered once at app launch via `registerCategories`.
  static let categoryIdentifier = "moves.reminder"

  // MARK: - State

  private let center: any UNUserNotificationCenterProtocol
  private let alertRepository: AlertRepository
  private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

  init(
    center: any UNUserNotificationCenterProtocol = UNUserNotificationCenter.current(),
    alertRepository: AlertRepository
  ) {
    self.center = center
    self.alertRepository = alertRepository
  }

  // MARK: - Setup

  /// Register the snooze action category. Idempotent; safe to call on every
  /// launch. Called from `MovesApp.init` or equivalent.
  func registerCategories() {
    let actions = SnoozeOffset.allCases.map { offset in
      UNNotificationAction(
        identifier: offset.actionIdentifier,
        title: offset.label,
        options: []
      )
    }
    let category = UNNotificationCategory(
      identifier: Self.categoryIdentifier,
      actions: actions,
      intentIdentifiers: [],
      options: []
    )
    center.setNotificationCategories([category])
  }

  /// Refresh `authorizationStatus` from the OS. Cheap; safe at any time.
  func refreshAuthorizationStatus() async {
    authorizationStatus = await center.currentAuthorizationStatus()
  }

  /// Request `.alert + .sound` authorization. Idempotent — calling after a
  /// granted/denied response just returns the same answer. Returns true if
  /// alerts are allowed at the end.
  @discardableResult
  func requestAuthorizationIfNeeded() async -> Bool {
    await refreshAuthorizationStatus()
    switch authorizationStatus {
    case .authorized, .provisional, .ephemeral:
      return true
    case .denied:
      return false
    case .notDetermined:
      break
    @unknown default:
      return false
    }
    let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    await refreshAuthorizationStatus()
    return granted
  }

  // MARK: - Scheduling

  /// Convenience: schedule a single at-due notification for `item`. Equivalent
  /// to `scheduleAlerts(item: item, offsetsMinutes: [0])`. Returns the created
  /// alert ID (the first, and only, element of the result), or nil when the
  /// item has no `due_at` or the at-due fire would be in the past.
  @discardableResult
  func scheduleAtDue(item: Item) async throws -> String? {
    let ids = try await scheduleAlerts(item: item, offsetsMinutes: [0])
    return ids.first
  }

  /// Schedule one notification per offset for `item`. For each offset:
  ///
  /// - `fireDate = item.dueAt - offset*60`. If `fireDate <= now`, the offset
  ///   is skipped (no Alert row, no OS notification). The
  ///   `AlertReconciliation` + badge query handle past-due state.
  /// - Otherwise: insert an `Alert(itemId:, offsetMinutes:)` row and schedule
  ///   a `UNTimeIntervalNotificationTrigger` with the
  ///   `moves.item.<itemId>.alert.<alertId>` identifier.
  /// - Notification body is "Due in <label>" when offset > 0 (e.g. "Due in
  ///   15m before"). The offset=0 case has no body — title-only.
  ///
  /// Offsets are de-duplicated and sorted descending (earliest fire first).
  /// If the item has no `due_at`, this is a no-op and returns an empty array.
  /// If authorization is denied, Alert rows are still recorded but no OS-level
  /// notifications are scheduled.
  ///
  /// Returns the list of created alert IDs in fire-order.
  @discardableResult
  func scheduleAlerts(item: Item, offsetsMinutes: [Int]) async throws -> [String] {
    guard let dueAt = item.dueAt else { return [] }
    // De-duplicate and sort descending so the earliest-fire (largest offset)
    // is scheduled first. Stable order keeps tests deterministic.
    let unique = Array(Set(offsetsMinutes)).sorted(by: >)
    guard !unique.isEmpty else { return [] }

    let dueDate = Date(timeIntervalSince1970: TimeInterval(dueAt))
    let now = Date()

    let granted = await requestAuthorizationIfNeeded()

    var createdIds: [String] = []
    for offset in unique {
      let fireDate = dueDate.addingTimeInterval(TimeInterval(-offset * 60))
      // Skip past fires entirely — no Alert row either, since reconciliation
      // would just mark it fired immediately.
      guard fireDate > now else { continue }

      let alert = Alert(itemId: item.id, offsetMinutes: offset)
      try await alertRepository.insert(alert)
      createdIds.append(alert.id)

      guard granted else { continue }

      let interval = max(1, fireDate.timeIntervalSinceNow)
      let body: String? = offset > 0 ? "Due in \(Self.dueInLabel(offsetMinutes: offset))" : nil
      let content = makeContent(title: item.title, body: body, itemId: item.id, alertId: alert.id)
      let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
      let request = UNNotificationRequest(
        identifier: notificationIdentifier(itemId: item.id, alertId: alert.id),
        content: content,
        trigger: trigger
      )
      try await center.add(request)
    }
    return createdIds
  }

  /// Terse human label for the notification body. "15m" / "1h" / "1d" /
  /// "1h 30m". Mirrors `AlertOffsetLabel.describe` shape but without the
  /// "before"/"at due time" suffix — those don't fit the "Due in …" frame.
  static func dueInLabel(offsetMinutes: Int) -> String {
    let m = max(0, offsetMinutes)
    if m < 60 { return "\(m)m" }
    if m < 24 * 60 {
      let hours = m / 60
      let rest = m % 60
      if rest == 0 { return "\(hours)h" }
      return "\(hours)h \(rest)m"
    }
    let days = m / (24 * 60)
    let rest = m % (24 * 60)
    if rest == 0 { return "\(days)d" }
    let hours = rest / 60
    if hours == 0 { return "\(days)d" }
    return "\(days)d \(hours)h"
  }

  /// Cancel any pending OS notification for this item, but leave the
  /// persisted alert row alone — phase 6 will reconcile.
  func cancelPending(itemId: String) async {
    let pending = await center.pendingNotificationRequests()
    let ids = pending
      .map(\.identifier)
      .filter { $0.hasPrefix("moves.item.\(itemId).") }
    if !ids.isEmpty {
      center.removePendingNotificationRequests(withIdentifiers: ids)
    }
  }

  /// Snooze a fired notification by scheduling a new one at `now + offset`.
  /// Per the Phase 2 decision: snooze defers the *alert*, not the deadline,
  /// so `Item.due_at` is unchanged. Records the snoozed alert's `fired_at`
  /// so we don't double-count.
  func snooze(
    itemId: String,
    alertId: String,
    title: String,
    offset: SnoozeOffset,
    now: Date = Date()
  ) async throws {
    try await alertRepository.markFired(id: alertId, at: Int64(now.timeIntervalSince1970))

    // Insert a fresh alert row representing the rescheduled fire.
    let snoozeAlert = Alert(itemId: itemId, offsetMinutes: Int(offset.seconds / 60))
    try await alertRepository.insert(snoozeAlert)

    let content = makeContent(title: title, body: nil, itemId: itemId, alertId: snoozeAlert.id)
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: offset.seconds, repeats: false)
    let request = UNNotificationRequest(
      identifier: notificationIdentifier(itemId: itemId, alertId: snoozeAlert.id),
      content: content,
      trigger: trigger
    )
    try await center.add(request)
  }

  /// Mark an alert as fired at `now`. Called by the notification delegate
  /// when a notification is delivered (foreground) or tapped.
  func markFired(alertId: String, at now: Date = Date()) async throws {
    try await alertRepository.markFired(id: alertId, at: Int64(now.timeIntervalSince1970))
  }

  // MARK: - Building blocks

  private func makeContent(title: String, body: String?, itemId: String, alertId: String) -> UNMutableNotificationContent {
    let content = UNMutableNotificationContent()
    content.title = title.isEmpty ? "Reminder" : title
    if let body { content.body = body }
    content.sound = .default
    content.categoryIdentifier = Self.categoryIdentifier
    content.userInfo = [
      UserInfoKey.itemId: itemId,
      UserInfoKey.alertId: alertId,
    ]
    return content
  }

  private func notificationIdentifier(itemId: String, alertId: String) -> String {
    "moves.item.\(itemId).alert.\(alertId)"
  }
}

// MARK: - Testability seam

/// Subset of `UNUserNotificationCenter`'s API we depend on, expressed as a
/// protocol so future tests can swap in a fake. The real
/// `UNUserNotificationCenter` adopts this trivially.
@MainActor
protocol UNUserNotificationCenterProtocol: AnyObject, Sendable {
  /// The current authorization status. Real implementations forward
  /// `notificationSettings().authorizationStatus`; the seam lets fakes
  /// return a status without constructing `UNNotificationSettings` (which
  /// has no public init).
  func currentAuthorizationStatus() async -> UNAuthorizationStatus
  func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
  func setNotificationCategories(_ categories: Set<UNNotificationCategory>)
  func add(_ request: UNNotificationRequest) async throws
  func pendingNotificationRequests() async -> [UNNotificationRequest]
  func removePendingNotificationRequests(withIdentifiers: [String])
}

extension UNUserNotificationCenter: UNUserNotificationCenterProtocol {
  func currentAuthorizationStatus() async -> UNAuthorizationStatus {
    let settings = await notificationSettings()
    return settings.authorizationStatus
  }
}
