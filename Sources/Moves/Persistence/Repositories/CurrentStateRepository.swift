import Foundation

/// Wraps the single-row `current_state` table. The migration seeds row id=1
/// so reads and writes are simple UPDATE-by-id; there is no insert path.
struct CurrentStateRepository: Sendable {
  private let db: Database

  init(database: Database) {
    self.db = database
  }

  func get() async throws -> CurrentState {
    let result = try await db.queryOne(
      "SELECT thread_id, segment_id, started_at FROM current_state WHERE id = 1;"
    ) { s in
      CurrentState(
        threadId: s.optionalText(at: 0),
        segmentId: s.optionalText(at: 1),
        startedAt: s.optionalInt64(at: 2)
      )
    }
    return result ?? .empty
  }

  func set(_ state: CurrentState) async throws {
    try await db.execute(
      "UPDATE current_state SET thread_id = ?, segment_id = ?, started_at = ? WHERE id = 1;"
    ) { stmt in
      stmt.bindText(state.threadId, at: 1)
      stmt.bindText(state.segmentId, at: 2)
      stmt.bindInt64(state.startedAt, at: 3)
    }
  }

  func clear() async throws {
    try await set(.empty)
  }
}
