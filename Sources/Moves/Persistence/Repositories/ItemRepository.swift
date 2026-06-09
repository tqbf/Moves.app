import Foundation

struct ItemRepository: Sendable {
  private let db: Database

  init(database: Database) {
    self.db = database
  }

  // MARK: - Reads

  func forThread(_ threadId: String) async throws -> [Item] {
    try await db.query(
      """
      \(Self.selectColumns)
      FROM items
      WHERE thread_id = ?
      ORDER BY created_at ASC;
      """,
      bind: { $0.bindText(threadId, at: 1) },
      row: Self.read
    )
  }

  func openForThread(_ threadId: String) async throws -> [Item] {
    try await db.query(
      """
      \(Self.selectColumns)
      FROM items
      WHERE thread_id = ? AND status = ?
      ORDER BY created_at ASC;
      """,
      bind: { stmt in
        stmt.bindText(threadId, at: 1)
        stmt.bindText(ItemStatus.open.rawValue, at: 2)
      },
      row: Self.read
    )
  }

  func captured() async throws -> [Item] {
    try await db.query(
      """
      \(Self.selectColumns)
      FROM items
      WHERE status = ?
      ORDER BY created_at DESC;
      """,
      bind: { $0.bindText(ItemStatus.captured.rawValue, at: 1) },
      row: Self.read
    )
  }

  func upcomingHard(now: Int64) async throws -> [Item] {
    try await db.query(
      """
      \(Self.selectColumns)
      FROM items
      WHERE due_at IS NOT NULL
        AND interruption_kind = ?
        AND status IN (?, ?)
        AND due_at >= ?
      ORDER BY due_at ASC;
      """,
      bind: { stmt in
        stmt.bindText(InterruptionKind.hard.rawValue, at: 1)
        stmt.bindText(ItemStatus.captured.rawValue, at: 2)
        stmt.bindText(ItemStatus.open.rawValue, at: 3)
        stmt.bindInt64(now, at: 4)
      },
      row: Self.read
    )
  }

  /// Count of items that are due-now or recently overdue (within the last
  /// hour) AND hard-interruption AND still open/captured. Drives the
  /// menu-bar badge per INITIAL-PLAN §16.
  ///
  /// The 1-hour cap is a deliberate UX call: once a deadline is more than
  /// an hour past, the badge stops flagging it — "if I missed the call, I
  /// missed the call". Reconciliation still marks those alerts fired
  /// regardless of age; only this badge query enforces the cap.
  func dueOrOverdueHardCount(now: Int64) async throws -> Int {
    let oneHourAgo = now - 3600
    let count: Int? = try await db.queryOne(
      """
      SELECT COUNT(*) FROM items
      WHERE due_at IS NOT NULL
        AND interruption_kind = ?
        AND status IN (?, ?)
        AND due_at <= ?
        AND due_at >= ?;
      """,
      bind: { stmt in
        stmt.bindText(InterruptionKind.hard.rawValue, at: 1)
        stmt.bindText(ItemStatus.captured.rawValue, at: 2)
        stmt.bindText(ItemStatus.open.rawValue, at: 3)
        stmt.bindInt64(now, at: 4)
        stmt.bindInt64(oneHourAgo, at: 5)
      },
      row: Self.readCount
    )
    return count ?? 0
  }

  /// All items in `(captured, open)` with a non-nil `due_at`, regardless of
  /// interruption kind. Drives Phase-6 launch-time `AlertReconciliation`,
  /// which schedules missing notifications for futures and stamps fired_at
  /// for hard items whose due_at has already passed.
  func allOpenOrCapturedWithDueAt() async throws -> [Item] {
    try await db.query(
      """
      \(Self.selectColumns)
      FROM items
      WHERE due_at IS NOT NULL
        AND status IN (?, ?);
      """,
      bind: { stmt in
        stmt.bindText(ItemStatus.captured.rawValue, at: 1)
        stmt.bindText(ItemStatus.open.rawValue, at: 2)
      },
      row: Self.read
    )
  }

  /// All items used by Phase-6 `ExportService.exportMarkdownBundle` to emit
  /// the `captured.md` file: items whose `thread_id` is NULL and whose
  /// status is `.captured` (matches the §13 inbox definition).
  func orphanCaptured() async throws -> [Item] {
    try await db.query(
      """
      \(Self.selectColumns)
      FROM items
      WHERE thread_id IS NULL AND status = ?
      ORDER BY created_at ASC;
      """,
      bind: { $0.bindText(ItemStatus.captured.rawValue, at: 1) },
      row: Self.read
    )
  }

  func find(id: String) async throws -> Item? {
    try await db.queryOne(
      """
      \(Self.selectColumns)
      FROM items
      WHERE id = ?;
      """,
      bind: { $0.bindText(id, at: 1) },
      row: Self.read
    )
  }

  // MARK: - Writes

  func insert(_ item: Item) async throws {
    try await db.execute(
      """
      INSERT INTO items (
        id, thread_id, segment_id, title, body_markdown, status, kind,
        due_at, due_kind, interruption_kind, created_at, updated_at, completed_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
      """
    ) { stmt in
      stmt.bindText(item.id, at: 1)
      stmt.bindText(item.threadId, at: 2)
      stmt.bindText(item.segmentId, at: 3)
      stmt.bindText(item.title, at: 4)
      stmt.bindText(item.bodyMarkdown, at: 5)
      stmt.bindText(item.status.rawValue, at: 6)
      stmt.bindText(item.kind.rawValue, at: 7)
      stmt.bindInt64(item.dueAt, at: 8)
      stmt.bindText(item.dueKind.rawValue, at: 9)
      stmt.bindText(item.interruptionKind.rawValue, at: 10)
      stmt.bindInt64(item.createdAt, at: 11)
      stmt.bindInt64(item.updatedAt, at: 12)
      stmt.bindInt64(item.completedAt, at: 13)
    }
  }

  func update(_ item: Item) async throws {
    try await db.execute(
      """
      UPDATE items SET
        thread_id = ?,
        segment_id = ?,
        title = ?,
        body_markdown = ?,
        status = ?,
        kind = ?,
        due_at = ?,
        due_kind = ?,
        interruption_kind = ?,
        updated_at = ?,
        completed_at = ?
      WHERE id = ?;
      """
    ) { stmt in
      stmt.bindText(item.threadId, at: 1)
      stmt.bindText(item.segmentId, at: 2)
      stmt.bindText(item.title, at: 3)
      stmt.bindText(item.bodyMarkdown, at: 4)
      stmt.bindText(item.status.rawValue, at: 5)
      stmt.bindText(item.kind.rawValue, at: 6)
      stmt.bindInt64(item.dueAt, at: 7)
      stmt.bindText(item.dueKind.rawValue, at: 8)
      stmt.bindText(item.interruptionKind.rawValue, at: 9)
      stmt.bindInt64(item.updatedAt, at: 10)
      stmt.bindInt64(item.completedAt, at: 11)
      stmt.bindText(item.id, at: 12)
    }
  }

  func delete(id: String) async throws {
    try await db.execute("DELETE FROM items WHERE id = ?;") { stmt in
      stmt.bindText(id, at: 1)
    }
  }

  // MARK: - Row mapping

  private static let selectColumns = """
    SELECT id, thread_id, segment_id, title, body_markdown, status, kind,
           due_at, due_kind, interruption_kind, created_at, updated_at, completed_at
    """

  /// Row mapper for `SELECT COUNT(*)` projections.
  static func readCount(_ s: Statement) throws -> Int { s.int(at: 0) }

  static func read(_ s: Statement) throws -> Item {
    let statusRaw = s.text(at: 5)
    let kindRaw = s.text(at: 6)
    let dueKindRaw = s.text(at: 8)
    let interruptionRaw = s.text(at: 9)
    guard
      let status = ItemStatus(rawValue: statusRaw),
      let kind = ItemKind(rawValue: kindRaw),
      let dueKind = DueKind(rawValue: dueKindRaw),
      let interruption = InterruptionKind(rawValue: interruptionRaw)
    else {
      throw PersistenceError.unexpectedRowShape(
        "item enum: status=\(statusRaw) kind=\(kindRaw) dueKind=\(dueKindRaw) interruption=\(interruptionRaw)"
      )
    }
    return Item(
      id: s.text(at: 0),
      threadId: s.optionalText(at: 1),
      segmentId: s.optionalText(at: 2),
      title: s.text(at: 3),
      bodyMarkdown: s.text(at: 4),
      status: status,
      kind: kind,
      dueAt: s.optionalInt64(at: 7),
      dueKind: dueKind,
      interruptionKind: interruption,
      createdAt: s.int64(at: 10),
      updatedAt: s.int64(at: 11),
      completedAt: s.optionalInt64(at: 12)
    )
  }
}
