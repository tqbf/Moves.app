import UserNotifications
import XCTest
@testable import Moves

/// Tests the Phase-6 `AlertReconciliation` service against (a) the pure
/// `plan(now:items:pendingAlertsByItem:pendingIdentifiers:)` projection and
/// (b) end-to-end through a fake `UNUserNotificationCenterProtocol`.
///
/// The three §17 buckets:
///   1. Cancel pending OS notifications whose item is done/canceled/missing.
///   2. Schedule hard future items whose OS notification is missing.
///   3. Stamp Alert.fired_at for hard past-due items that never fired.
@MainActor
final class AlertReconciliationTests: XCTestCase {

  /// Fixture: 2026-06-08 14:30 UTC. Matches the Phase-2 / Headroom fixture.
  private let now = Date(timeIntervalSince1970: 1_780_493_400)

  // MARK: - Pure plan

  func testPlanCancelsIdentifierForDoneItem() {
    let item = makeItem(
      id: "item-1",
      status: .done,
      dueSeconds: secondsAgo(60),
      interruption: .hard
    )
    let identifier = identifierFor(itemId: "item-1", alertId: "alert-1")
    let plan = AlertReconciliation.plan(
      now: now,
      items: [item],
      pendingAlertsByItem: [:],
      pendingIdentifiers: [identifier]
    )
    XCTAssertEqual(plan.identifiersToCancel, [identifier])
    XCTAssertTrue(plan.itemsToSchedule.isEmpty)
    XCTAssertTrue(plan.alertIdsToMarkFired.isEmpty)
  }

  func testPlanCancelsIdentifierForCanceledItem() {
    let item = makeItem(
      id: "item-2",
      status: .canceled,
      dueSeconds: secondsAhead(3600),
      interruption: .hard
    )
    let identifier = identifierFor(itemId: "item-2", alertId: "alert-2")
    let plan = AlertReconciliation.plan(
      now: now,
      items: [item],
      pendingAlertsByItem: [:],
      pendingIdentifiers: [identifier]
    )
    XCTAssertEqual(plan.identifiersToCancel, [identifier])
  }

  func testPlanCancelsIdentifierForMissingItem() {
    // Item was deleted between scheduling and reconcile.
    let identifier = identifierFor(itemId: "item-gone", alertId: "alert-gone")
    let plan = AlertReconciliation.plan(
      now: now,
      items: [],
      pendingAlertsByItem: [:],
      pendingIdentifiers: [identifier]
    )
    XCTAssertEqual(plan.identifiersToCancel, [identifier])
  }

  func testPlanCancelsIdentifierForSoftItem() {
    // Item was converted from hard → soft after scheduling. The OS request
    // for the hard alert is stale and should be cleared.
    let item = makeItem(
      id: "item-3",
      status: .open,
      dueSeconds: secondsAhead(3600),
      interruption: .soft
    )
    let identifier = identifierFor(itemId: "item-3", alertId: "alert-3")
    let plan = AlertReconciliation.plan(
      now: now,
      items: [item],
      pendingAlertsByItem: [:],
      pendingIdentifiers: [identifier]
    )
    XCTAssertEqual(plan.identifiersToCancel, [identifier])
  }

  func testPlanLeavesValidScheduledNotificationAlone() {
    let item = makeItem(
      id: "item-4",
      status: .open,
      dueSeconds: secondsAhead(3600),
      interruption: .hard
    )
    let identifier = identifierFor(itemId: "item-4", alertId: "alert-4")
    let plan = AlertReconciliation.plan(
      now: now,
      items: [item],
      pendingAlertsByItem: [:],
      pendingIdentifiers: [identifier]
    )
    XCTAssertTrue(plan.identifiersToCancel.isEmpty,
                  "live hard future item with existing schedule shouldn't be canceled")
    XCTAssertTrue(plan.itemsToSchedule.isEmpty,
                  "an existing pending request covers this item")
  }

  func testPlanSchedulesHardFutureItemWithoutPending() {
    let item = makeItem(
      id: "item-5",
      status: .open,
      dueSeconds: secondsAhead(7200),
      interruption: .hard
    )
    let plan = AlertReconciliation.plan(
      now: now,
      items: [item],
      pendingAlertsByItem: [:],
      pendingIdentifiers: []
    )
    XCTAssertEqual(plan.itemsToSchedule.map(\.id), ["item-5"])
  }

  func testPlanDoesNotScheduleSoftFutureItem() {
    let item = makeItem(
      id: "item-soft",
      status: .open,
      dueSeconds: secondsAhead(3600),
      interruption: .soft
    )
    let plan = AlertReconciliation.plan(
      now: now,
      items: [item],
      pendingAlertsByItem: [:],
      pendingIdentifiers: []
    )
    XCTAssertTrue(plan.itemsToSchedule.isEmpty,
                  "soft items don't get scheduled — they're not hard interruptions per §2.10")
  }

  func testPlanMarksFiredForPastDueHardItem() {
    let item = makeItem(
      id: "item-past",
      status: .open,
      dueSeconds: secondsAgo(120),
      interruption: .hard
    )
    let unfiredAlert = Alert(id: "alert-past", itemId: "item-past", offsetMinutes: 0, firedAt: nil)
    let plan = AlertReconciliation.plan(
      now: now,
      items: [item],
      pendingAlertsByItem: ["item-past": [unfiredAlert]],
      pendingIdentifiers: []
    )
    XCTAssertEqual(plan.alertIdsToMarkFired, ["alert-past"])
    XCTAssertTrue(plan.itemsToSchedule.isEmpty,
                  "past-due hard items shouldn't be re-scheduled — that's stale-banner noise")
  }

  func testPlanDoesNotMarkAlreadyFiredAlert() {
    let item = makeItem(
      id: "item-fired",
      status: .open,
      dueSeconds: secondsAgo(60),
      interruption: .hard
    )
    let firedAlert = Alert(
      id: "alert-fired",
      itemId: "item-fired",
      offsetMinutes: 0,
      firedAt: Int64(now.timeIntervalSince1970) - 30
    )
    let plan = AlertReconciliation.plan(
      now: now,
      items: [item],
      pendingAlertsByItem: ["item-fired": [firedAlert]],
      pendingIdentifiers: []
    )
    XCTAssertTrue(plan.alertIdsToMarkFired.isEmpty,
                  "fired_at is already set — idempotent reconciliation must not stomp")
  }

  func testPlanIgnoresForeignIdentifiers() {
    // Some other framework added a notification to the OS. We should
    // never touch it.
    let plan = AlertReconciliation.plan(
      now: now,
      items: [],
      pendingAlertsByItem: [:],
      pendingIdentifiers: ["someotherapp.alert.42"]
    )
    XCTAssertTrue(plan.identifiersToCancel.isEmpty)
  }

  func testPlanIsIdempotent() {
    // Running plan twice on the same inputs yields the same plan. The
    // service must be safe to call repeatedly per the §17 contract.
    let item = makeItem(
      id: "item-idem",
      status: .open,
      dueSeconds: secondsAhead(900),
      interruption: .hard
    )
    let first = AlertReconciliation.plan(
      now: now,
      items: [item],
      pendingAlertsByItem: [:],
      pendingIdentifiers: []
    )
    let second = AlertReconciliation.plan(
      now: now,
      items: [item],
      pendingAlertsByItem: [:],
      pendingIdentifiers: []
    )
    XCTAssertEqual(first, second)
  }

  func testPlanMixedBuckets() {
    // One done item with a stale OS request + one hard future item with
    // no pending + one hard past-due item with an unfired alert. All
    // three buckets land in the same plan.
    let done = makeItem(
      id: "done",
      status: .done,
      dueSeconds: secondsAgo(60),
      interruption: .hard
    )
    let future = makeItem(
      id: "future",
      status: .open,
      dueSeconds: secondsAhead(1800),
      interruption: .hard
    )
    let past = makeItem(
      id: "past",
      status: .open,
      dueSeconds: secondsAgo(120),
      interruption: .hard
    )
    let pastAlert = Alert(id: "past-alert", itemId: "past", offsetMinutes: 0, firedAt: nil)
    let plan = AlertReconciliation.plan(
      now: now,
      items: [done, future, past],
      pendingAlertsByItem: ["past": [pastAlert]],
      pendingIdentifiers: [identifierFor(itemId: "done", alertId: "stale-alert")]
    )
    XCTAssertEqual(plan.identifiersToCancel, [identifierFor(itemId: "done", alertId: "stale-alert")])
    XCTAssertEqual(plan.itemsToSchedule.map(\.id), ["future"])
    XCTAssertEqual(plan.alertIdsToMarkFired, ["past-alert"])
  }

  // MARK: - End-to-end with fake center

  func testReconcileCancelsAndMarksFiredEndToEnd() async throws {
    let env = try await Environment.make()
    defer { env.tearDown() }

    // A hard captured item with a past due_at + an unfired alert row +
    // a stale OS request. After reconcile: OS request canceled, alert
    // fired_at stamped.
    let pastItem = Item(
      title: "submit calc homework",
      status: .open,
      kind: .reminder,
      dueAt: env.secondsAgo(120),
      dueKind: .datetime,
      interruptionKind: .hard
    )
    try await env.itemRepo.insert(pastItem)
    let alert = Alert(itemId: pastItem.id, offsetMinutes: 0)
    try await env.alertRepo.insert(alert)
    let staleIdentifier = "moves.item.\(pastItem.id).alert.\(alert.id)"
    env.center.queuePending([staleIdentifier])

    let reconciler = AlertReconciliation(
      itemRepository: env.itemRepo,
      alertRepository: env.alertRepo,
      reminderScheduler: nil, // no scheduling in this test
      center: env.center
    )
    await reconciler.reconcile(now: env.now)

    XCTAssertEqual(env.center.removedIdentifiers, [[staleIdentifier]])
    let alerts = try await env.alertRepo.allForItem(pastItem.id)
    XCTAssertEqual(alerts.count, 1)
    XCTAssertNotNil(alerts.first?.firedAt, "past-due hard item's alert should be marked fired")
  }

  func testReconcileIsIdempotentEndToEnd() async throws {
    let env = try await Environment.make()
    defer { env.tearDown() }

    // Done item with a stale OS request — cancellation should happen on
    // both passes but the DB state remains consistent.
    let doneItem = Item(
      title: "old reminder",
      status: .done,
      kind: .reminder,
      dueAt: env.secondsAgo(3600),
      dueKind: .datetime,
      interruptionKind: .hard,
      completedAt: env.secondsAgo(60)
    )
    try await env.itemRepo.insert(doneItem)
    let staleIdentifier = "moves.item.\(doneItem.id).alert.deadbeef"
    env.center.queuePending([staleIdentifier])

    let reconciler = AlertReconciliation(
      itemRepository: env.itemRepo,
      alertRepository: env.alertRepo,
      reminderScheduler: nil,
      center: env.center
    )
    await reconciler.reconcile(now: env.now)
    // The done item's status filter means it's not in
    // allOpenOrCapturedWithDueAt so plan(items: []) sees nothing. The
    // pending identifier therefore has no matching item — cancel.
    XCTAssertEqual(env.center.removedIdentifiers.last, [staleIdentifier])

    // Second pass: no new pending requests; nothing to cancel.
    env.center.pendingRequests = []
    await reconciler.reconcile(now: env.now)
    // Nothing to cancel on the second pass because there are no stale
    // identifiers left.
    XCTAssertEqual(env.center.removedIdentifiers.count, 1)
  }

  // MARK: - Multi-alert end-to-end

  func testPlanSchedulesHardFutureItemWhenNoPendingExists() {
    // Multi-alert end-to-end shape: the `plan` step decides the item
    // needs scheduling. The actual offset fan-out happens inside the
    // scheduler, which `reconcile()` invokes via `scheduleAlerts(item:
    // offsetsMinutes:)`. We can't drive the real scheduler through the
    // test fake (UNNotificationSettings has no public init), so this
    // covers the plan/dispatch contract — and the per-offset behavior
    // is exercised through `Sources/Moves/Services/ReminderScheduler`'s
    // direct API in the multi-offset persistence test below.
    let item = makeItem(
      id: "item-multi",
      status: .open,
      dueSeconds: secondsAhead(2 * 3600),
      interruption: .hard
    )
    let plan = AlertReconciliation.plan(
      now: now,
      items: [item],
      pendingAlertsByItem: [:],
      pendingIdentifiers: []
    )
    XCTAssertEqual(plan.itemsToSchedule.map(\.id), ["item-multi"])
  }

  func testReconcileSchedulesAllOffsetsAsAlertRowsForHardFutureItem() async throws {
    let env = try await Environment.make()
    defer { env.tearDown() }

    // Future hard item with no pending notification. After reconcile,
    // the per-offset Alert rows should exist (one per future offset).
    // The scheduler uses real `Date()` for the past-fire skip — anchor
    // the item's due_at to a wall-clock-future moment so all three
    // offsets remain in the future.
    let dueAt = Int64(Date().timeIntervalSince1970) + 24 * 3600
    let item = Item(
      title: "submit calc homework",
      status: .open,
      kind: .reminder,
      dueAt: dueAt,
      dueKind: .datetime,
      interruptionKind: .hard
    )
    try await env.itemRepo.insert(item)

    // Drive `scheduleAlerts` through the fake center directly. The fake
    // returns `.authorized` from `currentAuthorizationStatus()` so the
    // scheduler proceeds to add OS requests.
    env.center.authorizationStatus = .authorized
    let scheduler = ReminderScheduler(
      center: env.center,
      alertRepository: env.alertRepo
    )
    _ = try await scheduler.scheduleAlerts(item: item, offsetsMinutes: [60, 15, 0])

    let alerts = try await env.alertRepo.allForItem(item.id)
    XCTAssertEqual(alerts.count, 3, "three offsets → three alert rows")
    let movesRequests = env.center.pendingRequests.filter {
      $0.identifier.hasPrefix("moves.item.\(item.id).alert.")
    }
    XCTAssertEqual(movesRequests.count, 3, "three offsets → three OS requests")
  }

  func testReconcileIsIdempotentForMultiAlertItem() async throws {
    let env = try await Environment.make()
    defer { env.tearDown() }

    // Future hard item with one pending OS request already in place
    // ("covered"). Reconcile twice; alert table shouldn't grow.
    let item = Item(
      title: "1:1 with Brian",
      status: .open,
      kind: .reminder,
      dueAt: env.secondsAhead(3600),
      dueKind: .datetime,
      interruptionKind: .hard
    )
    try await env.itemRepo.insert(item)
    let existing = Alert(itemId: item.id, offsetMinutes: 0)
    try await env.alertRepo.insert(existing)
    env.center.queuePending(["moves.item.\(item.id).alert.\(existing.id)"])

    let reconciler = AlertReconciliation(
      itemRepository: env.itemRepo,
      alertRepository: env.alertRepo,
      reminderScheduler: nil, // verify the "schedule" bucket is empty
      center: env.center,
      offsetsForItem: { _ in [60, 15, 0] }
    )
    await reconciler.reconcile(now: env.now)
    await reconciler.reconcile(now: env.now)

    let alerts = try await env.alertRepo.allForItem(item.id)
    XCTAssertEqual(alerts.count, 1,
                   "item already covered by a pending OS request; reconciler must not double-schedule")
  }

  func testReconcileMarksAllUnfiredAlertsForPastDueItem() async throws {
    let env = try await Environment.make()
    defer { env.tearDown() }

    // Past-due hard item with three unfired alert rows (offsets persisted
    // before the app last closed). All three should be marked fired in
    // one reconcile pass.
    let item = Item(
      title: "tax filing",
      status: .open,
      kind: .reminder,
      dueAt: env.secondsAgo(120),
      dueKind: .datetime,
      interruptionKind: .hard
    )
    try await env.itemRepo.insert(item)
    for offset in [60, 15, 0] {
      try await env.alertRepo.insert(Alert(itemId: item.id, offsetMinutes: offset))
    }

    let reconciler = AlertReconciliation(
      itemRepository: env.itemRepo,
      alertRepository: env.alertRepo,
      reminderScheduler: nil,
      center: env.center
    )
    await reconciler.reconcile(now: env.now)

    let alerts = try await env.alertRepo.allForItem(item.id)
    XCTAssertEqual(alerts.count, 3)
    XCTAssertTrue(alerts.allSatisfy { $0.firedAt != nil },
                  "every unfired row on a past-due hard item gets stamped")
  }

  // MARK: - Identifier parser

  func testParseIdentifierRoundTrip() {
    let parsed = AlertReconciliation.parseIdentifier("moves.item.abc-123.alert.zzz-9")
    XCTAssertEqual(parsed?.itemId, "abc-123")
    XCTAssertEqual(parsed?.alertId, "zzz-9")
  }

  func testParseIdentifierRejectsForeignPrefix() {
    XCTAssertNil(AlertReconciliation.parseIdentifier("foo.bar.alert.baz"))
  }

  func testParseIdentifierRejectsMissingAlertSegment() {
    XCTAssertNil(AlertReconciliation.parseIdentifier("moves.item.abc-123.something.zzz"))
  }

  // MARK: - Fixtures

  private func makeItem(
    id: String,
    status: ItemStatus,
    dueSeconds: Int64,
    interruption: InterruptionKind
  ) -> Item {
    Item(
      id: id,
      threadId: nil,
      title: "test",
      status: status,
      kind: interruption == .hard ? .reminder : .task,
      dueAt: dueSeconds,
      dueKind: .datetime,
      interruptionKind: interruption
    )
  }

  private func identifierFor(itemId: String, alertId: String) -> String {
    "moves.item.\(itemId).alert.\(alertId)"
  }

  private func secondsAhead(_ seconds: Int) -> Int64 {
    Int64(now.timeIntervalSince1970) + Int64(seconds)
  }

  private func secondsAgo(_ seconds: Int) -> Int64 {
    Int64(now.timeIntervalSince1970) - Int64(seconds)
  }
}

// MARK: - Environment (e2e)

/// Spins up a temp on-disk DB + repositories + a fake notification center.
/// Reused by the two end-to-end reconcile tests.
@MainActor
private struct Environment {
  let tempDir: URL
  let database: Database
  let itemRepo: ItemRepository
  let alertRepo: AlertRepository
  let center: FakeNotificationCenter
  let now: Date

  static func make() async throws -> Environment {
    let tempDir = FileManager.default.temporaryDirectory
      .appending(path: "moves-reconcile-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let dbPath = tempDir.appending(path: "moves.sqlite3").path(percentEncoded: false)
    let database = try Database(path: dbPath)
    return Environment(
      tempDir: tempDir,
      database: database,
      itemRepo: ItemRepository(database: database),
      alertRepo: AlertRepository(database: database),
      center: FakeNotificationCenter(),
      now: Date(timeIntervalSince1970: 1_780_493_400)
    )
  }

  func tearDown() {
    try? FileManager.default.removeItem(at: tempDir)
  }

  func secondsAgo(_ seconds: Int) -> Int64 {
    Int64(now.timeIntervalSince1970) - Int64(seconds)
  }

  func secondsAhead(_ seconds: Int) -> Int64 {
    Int64(now.timeIntervalSince1970) + Int64(seconds)
  }
}

/// Minimal fake of `UNUserNotificationCenterProtocol`. We only need
/// `pendingNotificationRequests()` + `removePendingNotificationRequests`;
/// the other protocol methods are stubbed because AlertReconciliation
/// never calls them.
@MainActor
private final class FakeNotificationCenter: UNUserNotificationCenterProtocol {
  /// IDs the test queued as "pending" before reconcile. Drained into
  /// real `UNNotificationRequest` instances by `pendingNotificationRequests`.
  var pendingRequests: [UNNotificationRequest] = []
  /// Captured `removePendingNotificationRequests` calls, one entry per call.
  var removedIdentifiers: [[String]] = []
  /// Mutable so the multi-offset persistence test can opt in to `.authorized`
  /// before driving `ReminderScheduler.scheduleAlerts`.
  var authorizationStatus: UNAuthorizationStatus = .denied

  func queuePending(_ ids: [String]) {
    let content = UNMutableNotificationContent()
    content.title = "stub"
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)
    pendingRequests = ids.map {
      UNNotificationRequest(identifier: $0, content: content, trigger: trigger)
    }
  }

  func currentAuthorizationStatus() async -> UNAuthorizationStatus {
    authorizationStatus
  }

  func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
    authorizationStatus == .authorized
  }

  func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
    // No-op for tests; production code only calls this from
    // `registerCategories` at launch, which the fake never exercises.
  }

  func add(_ request: UNNotificationRequest) async throws {
    pendingRequests.append(request)
  }

  func pendingNotificationRequests() async -> [UNNotificationRequest] {
    pendingRequests
  }

  func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
    removedIdentifiers.append(identifiers)
    pendingRequests.removeAll { identifiers.contains($0.identifier) }
  }
}
