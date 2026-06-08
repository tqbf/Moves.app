import Foundation

struct SegmentRepository: Sendable {
  private let db: Database

  init(database: Database) {
    self.db = database
  }

  // MARK: - Reads

  func forThread(_ threadId: String) async throws -> [Segment] {
    try await db.query(
      """
      \(Self.selectColumns)
      FROM segments
      WHERE thread_id = ?
      ORDER BY order_index ASC;
      """,
      bind: { $0.bindText(threadId, at: 1) },
      row: Self.read
    )
  }

  func find(id: String) async throws -> Segment? {
    try await db.queryOne(
      """
      \(Self.selectColumns)
      FROM segments
      WHERE id = ?;
      """,
      bind: { $0.bindText(id, at: 1) },
      row: Self.read
    )
  }

  // MARK: - Writes

  func insert(_ segment: Segment) async throws {
    try await db.execute(
      """
      INSERT INTO segments (
        id, thread_id, title, order_index, body_markdown, built_in_move,
        status, scheduled_at, due_at, estimate_minutes, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
      """
    ) { stmt in
      stmt.bindText(segment.id, at: 1)
      stmt.bindText(segment.threadId, at: 2)
      stmt.bindText(segment.title, at: 3)
      stmt.bindInt(segment.orderIndex, at: 4)
      stmt.bindText(segment.bodyMarkdown, at: 5)
      stmt.bindText(segment.builtInMove, at: 6)
      stmt.bindText(segment.status.rawValue, at: 7)
      stmt.bindInt64(segment.scheduledAt, at: 8)
      stmt.bindInt64(segment.dueAt, at: 9)
      stmt.bindInt(segment.estimateMinutes, at: 10)
      stmt.bindInt64(segment.createdAt, at: 11)
      stmt.bindInt64(segment.updatedAt, at: 12)
    }
  }

  func update(_ segment: Segment) async throws {
    try await db.execute(
      """
      UPDATE segments SET
        title = ?,
        order_index = ?,
        body_markdown = ?,
        built_in_move = ?,
        status = ?,
        scheduled_at = ?,
        due_at = ?,
        estimate_minutes = ?,
        updated_at = ?
      WHERE id = ?;
      """
    ) { stmt in
      stmt.bindText(segment.title, at: 1)
      stmt.bindInt(segment.orderIndex, at: 2)
      stmt.bindText(segment.bodyMarkdown, at: 3)
      stmt.bindText(segment.builtInMove, at: 4)
      stmt.bindText(segment.status.rawValue, at: 5)
      stmt.bindInt64(segment.scheduledAt, at: 6)
      stmt.bindInt64(segment.dueAt, at: 7)
      stmt.bindInt(segment.estimateMinutes, at: 8)
      stmt.bindInt64(segment.updatedAt, at: 9)
      stmt.bindText(segment.id, at: 10)
    }
  }

  func delete(id: String) async throws {
    try await db.execute("DELETE FROM segments WHERE id = ?;") { stmt in
      stmt.bindText(id, at: 1)
    }
  }

  // MARK: - Row mapping

  private static let selectColumns = """
    SELECT id, thread_id, title, order_index, body_markdown, built_in_move,
           status, scheduled_at, due_at, estimate_minutes, created_at, updated_at
    """

  static func read(_ s: Statement) throws -> Segment {
    let statusRaw = s.text(at: 6)
    guard let status = SegmentStatus(rawValue: statusRaw) else {
      throw PersistenceError.unexpectedRowShape("segment.status=\(statusRaw)")
    }
    return Segment(
      id: s.text(at: 0),
      threadId: s.text(at: 1),
      title: s.text(at: 2),
      orderIndex: s.int(at: 3),
      bodyMarkdown: s.text(at: 4),
      builtInMove: s.text(at: 5),
      status: status,
      scheduledAt: s.optionalInt64(at: 7),
      dueAt: s.optionalInt64(at: 8),
      estimateMinutes: s.optionalInt(at: 9),
      createdAt: s.int64(at: 10),
      updatedAt: s.int64(at: 11)
    )
  }
}
