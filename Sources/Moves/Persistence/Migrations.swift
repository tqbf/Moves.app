import Foundation

/// A single, ordered SQLite migration. Migrations run inside a transaction;
/// failures roll back. Add new migrations by appending; never edit a shipped
/// migration in place.
struct Migration: Sendable {
  let version: Int
  let name: String
  /// All statements run as one `sqlite3_exec` call. They may include
  /// multiple semicolon-terminated statements.
  let sql: String
}

enum Migrations {

  /// All known migrations, in order. The current schema version is the last
  /// entry's `version`. Phase 1 ships v1 only.
  static let all: [Migration] = [
    Migration(version: 1, name: "initial_schema", sql: v1_schema),
  ]

  // MARK: - v1

  /// Initial schema: every table from INITIAL-PLAN.md §10 + the indexes
  /// listed in that section. Timestamps are INTEGER Unix seconds (per the
  /// Phase 1 decision).
  private static let v1_schema = """
    CREATE TABLE threads (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      status TEXT NOT NULL CHECK (status IN ('active', 'parked', 'done')),
      kind TEXT NOT NULL CHECK (kind IN ('normal', 'regimented')),
      visibility TEXT NOT NULL CHECK (
        visibility IN ('normal', 'hide_work', 'downweight_work', 'only_work')
      ),
      breadcrumb TEXT NOT NULL DEFAULT '',
      detail_markdown TEXT NOT NULL DEFAULT '',
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      last_touched_at INTEGER
    );

    CREATE TABLE segments (
      id TEXT PRIMARY KEY,
      thread_id TEXT NOT NULL REFERENCES threads(id) ON DELETE CASCADE,
      title TEXT NOT NULL,
      order_index INTEGER NOT NULL,
      body_markdown TEXT NOT NULL DEFAULT '',
      built_in_move TEXT NOT NULL DEFAULT '',
      status TEXT NOT NULL CHECK (status IN ('pending', 'active', 'done', 'skipped')),
      scheduled_at INTEGER,
      due_at INTEGER,
      estimate_minutes INTEGER,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    );

    CREATE TABLE items (
      id TEXT PRIMARY KEY,
      thread_id TEXT REFERENCES threads(id) ON DELETE SET NULL,
      segment_id TEXT REFERENCES segments(id) ON DELETE SET NULL,
      title TEXT NOT NULL,
      body_markdown TEXT NOT NULL DEFAULT '',
      status TEXT NOT NULL CHECK (status IN ('captured', 'open', 'done', 'canceled')),
      kind TEXT NOT NULL CHECK (kind IN ('capture', 'task', 'reminder')),
      due_at INTEGER,
      due_kind TEXT NOT NULL CHECK (due_kind IN ('none', 'date', 'datetime')),
      interruption_kind TEXT NOT NULL CHECK (interruption_kind IN ('none', 'soft', 'hard')),
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      completed_at INTEGER
    );

    CREATE TABLE alerts (
      id TEXT PRIMARY KEY,
      item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
      offset_minutes INTEGER NOT NULL,
      fired_at INTEGER
    );

    CREATE TABLE current_state (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      thread_id TEXT REFERENCES threads(id) ON DELETE SET NULL,
      segment_id TEXT REFERENCES segments(id) ON DELETE SET NULL,
      started_at INTEGER
    );

    CREATE TABLE time_log (
      id TEXT PRIMARY KEY,
      thread_id TEXT NOT NULL REFERENCES threads(id) ON DELETE CASCADE,
      segment_id TEXT REFERENCES segments(id) ON DELETE SET NULL,
      week_start TEXT NOT NULL,
      rough_minutes INTEGER NOT NULL,
      created_at INTEGER NOT NULL
    );

    CREATE TABLE settings (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    );

    CREATE INDEX idx_threads_status         ON threads(status);
    CREATE INDEX idx_segments_thread_status ON segments(thread_id, status);
    CREATE INDEX idx_items_due_at           ON items(due_at);
    CREATE INDEX idx_items_status_due       ON items(status, due_at);
    CREATE INDEX idx_items_thread           ON items(thread_id);
    CREATE INDEX idx_time_log_week          ON time_log(week_start);

    -- Seed the single current_state row so callers can update-by-id without
    -- a special-cased first-write path.
    INSERT INTO current_state (id, thread_id, segment_id, started_at)
    VALUES (1, NULL, NULL, NULL);
    """
}
