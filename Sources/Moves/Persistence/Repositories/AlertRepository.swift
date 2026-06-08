import Foundation

struct AlertRepository: Sendable {
  private let db: Database

  init(database: Database) {
    self.db = database
  }

  func forItem(_ itemId: String) async throws -> [Alert] {
    try await db.query(
      "\(Self.selectColumns) FROM alerts WHERE item_id = ? ORDER BY offset_minutes ASC;",
      bind: { $0.bindText(itemId, at: 1) },
      row: Self.read
    )
  }

  func pending() async throws -> [Alert] {
    try await db.query(
      "\(Self.selectColumns) FROM alerts WHERE fired_at IS NULL;",
      row: Self.read
    )
  }

  /// All alerts (any fire state) for an item. Lets `AlertReconciliation`
  /// look up the persisted row for a hard item whose `due_at` is already past
  /// so it can stamp `fired_at` without re-firing an OS notification.
  func allForItem(_ itemId: String) async throws -> [Alert] {
    try await db.query(
      "\(Self.selectColumns) FROM alerts WHERE item_id = ? ORDER BY offset_minutes ASC;",
      bind: { $0.bindText(itemId, at: 1) },
      row: Self.read
    )
  }

  func insert(_ alert: Alert) async throws {
    try await db.execute(
      "INSERT INTO alerts (id, item_id, offset_minutes, fired_at) VALUES (?, ?, ?, ?);"
    ) { stmt in
      stmt.bindText(alert.id, at: 1)
      stmt.bindText(alert.itemId, at: 2)
      stmt.bindInt(alert.offsetMinutes, at: 3)
      stmt.bindInt64(alert.firedAt, at: 4)
    }
  }

  func markFired(id: String, at firedAt: Int64) async throws {
    try await db.execute("UPDATE alerts SET fired_at = ? WHERE id = ?;") { stmt in
      stmt.bindInt64(firedAt, at: 1)
      stmt.bindText(id, at: 2)
    }
  }

  func delete(id: String) async throws {
    try await db.execute("DELETE FROM alerts WHERE id = ?;") { stmt in
      stmt.bindText(id, at: 1)
    }
  }

  // MARK: - Row mapping

  private static let selectColumns = "SELECT id, item_id, offset_minutes, fired_at"

  static func read(_ s: Statement) throws -> Alert {
    Alert(
      id: s.text(at: 0),
      itemId: s.text(at: 1),
      offsetMinutes: s.int(at: 2),
      firedAt: s.optionalInt64(at: 3)
    )
  }
}
