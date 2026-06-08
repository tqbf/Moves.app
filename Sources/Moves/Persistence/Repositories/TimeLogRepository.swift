import Foundation

struct TimeLogRepository: Sendable {
  private let db: Database

  init(database: Database) {
    self.db = database
  }

  func forWeek(_ weekStart: String) async throws -> [TimeLogEntry] {
    try await db.query(
      """
      SELECT id, thread_id, segment_id, week_start, rough_minutes, created_at
      FROM time_log
      WHERE week_start = ?
      ORDER BY created_at ASC;
      """,
      bind: { $0.bindText(weekStart, at: 1) },
      row: Self.read
    )
  }

  func forThread(_ threadId: String) async throws -> [TimeLogEntry] {
    try await db.query(
      """
      SELECT id, thread_id, segment_id, week_start, rough_minutes, created_at
      FROM time_log
      WHERE thread_id = ?
      ORDER BY created_at ASC;
      """,
      bind: { $0.bindText(threadId, at: 1) },
      row: Self.read
    )
  }

  func insert(_ entry: TimeLogEntry) async throws {
    try await db.execute(
      """
      INSERT INTO time_log (id, thread_id, segment_id, week_start, rough_minutes, created_at)
      VALUES (?, ?, ?, ?, ?, ?);
      """
    ) { stmt in
      stmt.bindText(entry.id, at: 1)
      stmt.bindText(entry.threadId, at: 2)
      stmt.bindText(entry.segmentId, at: 3)
      stmt.bindText(entry.weekStart, at: 4)
      stmt.bindInt(entry.roughMinutes, at: 5)
      stmt.bindInt64(entry.createdAt, at: 6)
    }
  }

  func delete(id: String) async throws {
    try await db.execute("DELETE FROM time_log WHERE id = ?;") { stmt in
      stmt.bindText(id, at: 1)
    }
  }

  static func read(_ s: Statement) throws -> TimeLogEntry {
    TimeLogEntry(
      id: s.text(at: 0),
      threadId: s.text(at: 1),
      segmentId: s.optionalText(at: 2),
      weekStart: s.text(at: 3),
      roughMinutes: s.int(at: 4),
      createdAt: s.int64(at: 5)
    )
  }
}
