import Foundation

/// Key-value `settings` table. Values are stored as TEXT — callers are
/// responsible for encoding (e.g. JSON) when storing structured data.
struct SettingsRepository: Sendable {
  private let db: Database

  init(database: Database) {
    self.db = database
  }

  func get(_ key: String) async throws -> String? {
    try await db.queryOne(
      "SELECT value FROM settings WHERE key = ?;",
      bind: { $0.bindText(key, at: 1) },
      row: { $0.text(at: 0) }
    )
  }

  func set(_ key: String, value: String) async throws {
    try await db.execute(
      """
      INSERT INTO settings (key, value) VALUES (?, ?)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value;
      """
    ) { stmt in
      stmt.bindText(key, at: 1)
      stmt.bindText(value, at: 2)
    }
  }

  func delete(_ key: String) async throws {
    try await db.execute("DELETE FROM settings WHERE key = ?;") { stmt in
      stmt.bindText(key, at: 1)
    }
  }

  func all() async throws -> [String: String] {
    let pairs = try await db.query(
      "SELECT key, value FROM settings;",
      row: { ($0.text(at: 0), $0.text(at: 1)) }
    )
    return Dictionary(uniqueKeysWithValues: pairs)
  }
}
