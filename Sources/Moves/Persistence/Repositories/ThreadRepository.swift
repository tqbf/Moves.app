import Foundation

struct ThreadRepository: Sendable {
  private let db: Database

  init(database: Database) {
    self.db = database
  }

  // MARK: - Reads

  func all() async throws -> [Thread] {
    try await db.query(
      """
      \(Self.selectColumns)
      FROM threads
      ORDER BY (last_touched_at IS NULL), last_touched_at DESC, created_at DESC;
      """,
      row: Self.read
    )
  }

  func withStatus(_ status: ThreadStatus) async throws -> [Thread] {
    try await db.query(
      """
      \(Self.selectColumns)
      FROM threads
      WHERE status = ?
      ORDER BY (last_touched_at IS NULL), last_touched_at DESC, created_at DESC;
      """,
      bind: { $0.bindText(status.rawValue, at: 1) },
      row: Self.read
    )
  }

  func find(id: String) async throws -> Thread? {
    try await db.queryOne(
      """
      \(Self.selectColumns)
      FROM threads
      WHERE id = ?;
      """,
      bind: { $0.bindText(id, at: 1) },
      row: Self.read
    )
  }

  // MARK: - Writes

  func insert(_ thread: Thread) async throws {
    try await db.execute(
      """
      INSERT INTO threads (
        id, title, status, kind, visibility, breadcrumb, detail_markdown,
        created_at, updated_at, last_touched_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
      """
    ) { stmt in
      stmt.bindText(thread.id, at: 1)
      stmt.bindText(thread.title, at: 2)
      stmt.bindText(thread.status.rawValue, at: 3)
      stmt.bindText(thread.kind.rawValue, at: 4)
      stmt.bindText(thread.visibility.rawValue, at: 5)
      stmt.bindText(thread.breadcrumb, at: 6)
      stmt.bindText(thread.detailMarkdown, at: 7)
      stmt.bindInt64(thread.createdAt, at: 8)
      stmt.bindInt64(thread.updatedAt, at: 9)
      stmt.bindInt64(thread.lastTouchedAt, at: 10)
    }
  }

  func update(_ thread: Thread) async throws {
    try await db.execute(
      """
      UPDATE threads SET
        title = ?,
        status = ?,
        kind = ?,
        visibility = ?,
        breadcrumb = ?,
        detail_markdown = ?,
        updated_at = ?,
        last_touched_at = ?
      WHERE id = ?;
      """
    ) { stmt in
      stmt.bindText(thread.title, at: 1)
      stmt.bindText(thread.status.rawValue, at: 2)
      stmt.bindText(thread.kind.rawValue, at: 3)
      stmt.bindText(thread.visibility.rawValue, at: 4)
      stmt.bindText(thread.breadcrumb, at: 5)
      stmt.bindText(thread.detailMarkdown, at: 6)
      stmt.bindInt64(thread.updatedAt, at: 7)
      stmt.bindInt64(thread.lastTouchedAt, at: 8)
      stmt.bindText(thread.id, at: 9)
    }
  }

  func delete(id: String) async throws {
    try await db.execute("DELETE FROM threads WHERE id = ?;") { stmt in
      stmt.bindText(id, at: 1)
    }
  }

  // MARK: - Row mapping

  private static let selectColumns = """
    SELECT id, title, status, kind, visibility, breadcrumb, detail_markdown,
           created_at, updated_at, last_touched_at
    """

  static func read(_ s: Statement) throws -> Thread {
    let statusRaw = s.text(at: 2)
    let kindRaw = s.text(at: 3)
    let visRaw = s.text(at: 4)
    guard
      let status = ThreadStatus(rawValue: statusRaw),
      let kind = ThreadKind(rawValue: kindRaw),
      let visibility = ThreadVisibility(rawValue: visRaw)
    else {
      throw PersistenceError.unexpectedRowShape(
        "thread enum: status=\(statusRaw) kind=\(kindRaw) visibility=\(visRaw)"
      )
    }
    return Thread(
      id: s.text(at: 0),
      title: s.text(at: 1),
      status: status,
      kind: kind,
      visibility: visibility,
      breadcrumb: s.text(at: 5),
      detailMarkdown: s.text(at: 6),
      createdAt: s.int64(at: 7),
      updatedAt: s.int64(at: 8),
      lastTouchedAt: s.optionalInt64(at: 9)
    )
  }
}
