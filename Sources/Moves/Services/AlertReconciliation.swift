import Foundation
import UserNotifications

/// Launch-time reconciliation of `UNUserNotificationCenter`'s pending
/// requests against the persisted item + alert state (INITIAL-PLAN §8.4,
/// §17). Idempotent, safe to run repeatedly. The contract:
///
///   1. Any pending OS notification whose item is `.done` or `.canceled`
///      (or whose item has been deleted) is canceled. The DB is the
///      source of truth.
///   2. For each item with `status ∈ {.captured, .open}` whose `due_at`
///      is in the future AND `interruption_kind == .hard` AND no
///      matching pending OS notification exists, a new one is scheduled.
///   3. For each hard item whose `due_at` is already past, the
///      corresponding `Alert.fired_at` is stamped to `now()` (if any
///      pending alert row exists). The OS notification is NOT re-fired —
///      banners for past times are noise.
///
/// The reconciler is split into two phases for testability:
///
///   - `plan(now:)` returns a pure `Plan` describing what would change.
///     The plan is computable from {items, alerts, pendingIdentifiers}
///     alone — no IO, no notifications, no DB writes.
///   - `apply(plan:now:)` performs the OS cancellations, the
///     `Alert.fired_at` writes, and dispatches the missing schedules.
///
/// Tests against a fake `UNUserNotificationCenterProtocol` only need to
/// drive `plan(now:)` and inspect the result. Production calls
/// `reconcile(now:)`, which composes the two.
///
/// We rely on the `moves.item.<itemId>.alert.<alertId>` notification
/// identifier scheme that `ReminderScheduler` already uses.
@MainActor
struct AlertReconciliation {

  /// What `plan(now:)` decided. All three buckets per the §17 contract.
  struct Plan: Equatable, Sendable {
    /// OS-level notification identifiers to cancel via `removePending…`.
    /// Either the item is gone / done / canceled, or the item is no longer
    /// schedule-worthy (e.g. interruption-kind flipped to soft and the
    /// previously-scheduled hard alert is now stale).
    var identifiersToCancel: [String]
    /// Items that should be (re)scheduled via `ReminderScheduler.scheduleAtDue`.
    /// `interruption_kind == .hard`, `due_at` in the future, and there is no
    /// pending OS notification already covering them.
    var itemsToSchedule: [Item]
    /// Alert ids whose `fired_at` should be stamped to `now` because the
    /// item is hard, past due, and the alert row is still unfired. No OS
    /// notification is delivered — that ship sailed.
    var alertIdsToMarkFired: [String]
  }

  /// Notification identifier prefix `ReminderScheduler` writes:
  /// `moves.item.<itemId>.alert.<alertId>`.
  private static let identifierPrefix = "moves.item."

  let itemRepository: ItemRepository
  let alertRepository: AlertRepository
  let reminderScheduler: ReminderScheduler?
  let center: any UNUserNotificationCenterProtocol

  init(
    itemRepository: ItemRepository,
    alertRepository: AlertRepository,
    reminderScheduler: ReminderScheduler?,
    center: any UNUserNotificationCenterProtocol
  ) {
    self.itemRepository = itemRepository
    self.alertRepository = alertRepository
    self.reminderScheduler = reminderScheduler
    self.center = center
  }

  // MARK: - Pure planning

  /// Decide what would change without touching the OS or the DB. Tests call
  /// this directly with synthetic inputs.
  static func plan(
    now: Date,
    items: [Item],
    pendingAlertsByItem: [String: [Alert]],
    pendingIdentifiers: [String]
  ) -> Plan {
    let nowSeconds = Int64(now.timeIntervalSince1970)

    let liveItemIds = Set(items.map(\.id))
    let liveItemsById = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })

    // Bucket 1: cancel anything whose owning item is gone, done, canceled,
    // soft, or no longer has a due_at.
    var cancel: [String] = []
    var pendingItemIds = Set<String>()
    for identifier in pendingIdentifiers {
      guard let parsed = parseIdentifier(identifier) else {
        // Foreign identifier (something else stuffed a moves.* request in?) —
        // leave it alone. The scheduler only adds well-formed identifiers.
        continue
      }
      pendingItemIds.insert(parsed.itemId)
      guard let item = liveItemsById[parsed.itemId] else {
        // Item gone — cancel the OS request.
        cancel.append(identifier)
        continue
      }
      let scheduleWorthy =
        item.status == .captured || item.status == .open
      let hasFutureHardDue =
        item.interruptionKind == .hard
        && (item.dueAt ?? 0) > nowSeconds
      if !scheduleWorthy || !hasFutureHardDue {
        cancel.append(identifier)
      }
    }

    // Bucket 2: schedule hard items whose due_at is in the future and have
    // no pending OS notification covering them.
    var schedule: [Item] = []
    for item in items where item.interruptionKind == .hard {
      guard let due = item.dueAt, due > nowSeconds else { continue }
      if !pendingItemIds.contains(item.id) {
        schedule.append(item)
      }
    }

    // Bucket 3: mark fired for hard items whose due_at is past and which
    // have an unfired alert row. We don't re-fire OS notifications — that
    // would surface stale banners hours / days after the fact.
    var markFired: [String] = []
    for item in items where item.interruptionKind == .hard {
      guard let due = item.dueAt, due <= nowSeconds else { continue }
      let alerts = pendingAlertsByItem[item.id] ?? []
      for alert in alerts where alert.firedAt == nil {
        markFired.append(alert.id)
      }
    }

    // Keep liveItemIds referenced so a future tweak (e.g. "only schedule
    // for known items") doesn't have to re-derive it.
    _ = liveItemIds

    return Plan(
      identifiersToCancel: cancel,
      itemsToSchedule: schedule,
      alertIdsToMarkFired: markFired
    )
  }

  /// Parse `moves.item.<itemId>.alert.<alertId>` into its pieces. Returns
  /// nil for anything not matching the scheme.
  static func parseIdentifier(_ identifier: String) -> (itemId: String, alertId: String)? {
    guard identifier.hasPrefix(Self.identifierPrefix) else { return nil }
    let tail = identifier.dropFirst(Self.identifierPrefix.count)
    // tail = "<itemId>.alert.<alertId>"
    guard let range = tail.range(of: ".alert.") else { return nil }
    let itemId = String(tail[..<range.lowerBound])
    let alertId = String(tail[range.upperBound...])
    guard !itemId.isEmpty, !alertId.isEmpty else { return nil }
    return (itemId, alertId)
  }

  // MARK: - IO

  /// Compose the pure plan and apply it: cancel OS requests, stamp
  /// `fired_at`, dispatch missing schedules. Safe to run from app launch.
  func reconcile(now: Date = Date()) async {
    do {
      let items = try await itemRepository.allOpenOrCapturedWithDueAt()
      // Pull alert rows only for hard, past-due items — that's the
      // mark-fired bucket. Future scheduling doesn't need them.
      let nowSeconds = Int64(now.timeIntervalSince1970)
      var alertsByItem: [String: [Alert]] = [:]
      for item in items where item.interruptionKind == .hard
        && (item.dueAt ?? 0) <= nowSeconds {
        alertsByItem[item.id] = try await alertRepository.allForItem(item.id)
      }
      let pending = await center.pendingNotificationRequests()
      let pendingIdentifiers = pending.map(\.identifier)

      let plan = Self.plan(
        now: now,
        items: items,
        pendingAlertsByItem: alertsByItem,
        pendingIdentifiers: pendingIdentifiers
      )

      if !plan.identifiersToCancel.isEmpty {
        center.removePendingNotificationRequests(withIdentifiers: plan.identifiersToCancel)
      }
      for alertId in plan.alertIdsToMarkFired {
        try await alertRepository.markFired(id: alertId, at: nowSeconds)
      }
      if let reminderScheduler {
        for item in plan.itemsToSchedule {
          _ = try? await reminderScheduler.scheduleAtDue(item: item)
        }
      }
    } catch {
      // Reconciliation is best-effort: a failure here mustn't trap the
      // app. The next launch will retry.
    }
  }
}
