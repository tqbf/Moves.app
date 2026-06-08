import Foundation
import SQLite3

// MARK: - Errors

enum PersistenceError: Error, CustomStringConvertible {
  case openFailed(String)
  case migrationFailed(version: Int, name: String, message: String)
  case prepareFailed(String)
  case stepFailed(String)
  case unexpectedRowShape(String)

  var description: String {
    switch self {
    case let .openFailed(message):
      return "SQLite open failed: \(message)"
    case let .migrationFailed(version, name, message):
      return "Migration v\(version) (\(name)) failed: \(message)"
    case let .prepareFailed(message):
      return "SQLite prepare failed: \(message)"
    case let .stepFailed(message):
      return "SQLite step failed: \(message)"
    case let .unexpectedRowShape(message):
      return "Unexpected SQLite row shape: \(message)"
    }
  }
}

// MARK: - Statement wrapper

/// Thin wrapper around a prepared SQLite statement with typed bind/read
/// helpers. Lives only inside a `Database` call — never escape it.
///
/// Index conventions:
///   - bind indexes are 1-based (SQLite native).
///   - column indexes are 0-based (SQLite native).
struct Statement {
  fileprivate let handle: OpaquePointer

  func bindText(_ value: String, at index: Int32) {
    sqlite3_bind_text(handle, index, value, -1, Database.transient)
  }

  func bindText(_ value: String?, at index: Int32) {
    if let value {
      sqlite3_bind_text(handle, index, value, -1, Database.transient)
    } else {
      sqlite3_bind_null(handle, index)
    }
  }

  func bindInt(_ value: Int, at index: Int32) {
    sqlite3_bind_int64(handle, index, Int64(value))
  }

  func bindInt(_ value: Int?, at index: Int32) {
    if let value {
      sqlite3_bind_int64(handle, index, Int64(value))
    } else {
      sqlite3_bind_null(handle, index)
    }
  }

  func bindInt64(_ value: Int64, at index: Int32) {
    sqlite3_bind_int64(handle, index, value)
  }

  func bindInt64(_ value: Int64?, at index: Int32) {
    if let value {
      sqlite3_bind_int64(handle, index, value)
    } else {
      sqlite3_bind_null(handle, index)
    }
  }

  func text(at column: Int32) -> String {
    guard let cString = sqlite3_column_text(handle, column) else { return "" }
    return String(cString: cString)
  }

  func optionalText(at column: Int32) -> String? {
    if sqlite3_column_type(handle, column) == SQLITE_NULL { return nil }
    guard let cString = sqlite3_column_text(handle, column) else { return nil }
    return String(cString: cString)
  }

  func int(at column: Int32) -> Int {
    Int(sqlite3_column_int64(handle, column))
  }

  func optionalInt(at column: Int32) -> Int? {
    if sqlite3_column_type(handle, column) == SQLITE_NULL { return nil }
    return Int(sqlite3_column_int64(handle, column))
  }

  func int64(at column: Int32) -> Int64 {
    sqlite3_column_int64(handle, column)
  }

  func optionalInt64(at column: Int32) -> Int64? {
    if sqlite3_column_type(handle, column) == SQLITE_NULL { return nil }
    return sqlite3_column_int64(handle, column)
  }
}

// MARK: - Database

/// SQLite-backed persistence root. Opens with WAL mode, runs migrations,
/// and serializes all access through actor isolation.
///
/// Repositories take a `Database` and call `execute` / `query` / `queryOne`
/// from their own (non-isolated) entry points.
actor Database {
  /// SQLITE_TRANSIENT macro re-expressed as a Swift function pointer. SQLite
  /// expects this constant for "copy the bound buffer immediately" — the
  /// macro can't be imported into Swift.
  static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

  private var handle: OpaquePointer?

  init(path: String) throws {
    var rawHandle: OpaquePointer?
    let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
    guard sqlite3_open_v2(path, &rawHandle, flags, nil) == SQLITE_OK, let rawHandle else {
      let message = rawHandle.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
      if let rawHandle { sqlite3_close(rawHandle) }
      throw PersistenceError.openFailed(message)
    }
    self.handle = rawHandle

    // Init can't call actor-isolated methods on `self`, so set up pragmas +
    // migrations inline against `rawHandle`.
    try Database.configure(rawHandle: rawHandle)
    try Database.runMigrations(rawHandle: rawHandle)
  }

  // MARK: - Connection setup

  private static func configure(rawHandle: OpaquePointer) throws {
    try exec(rawHandle: rawHandle, sql: "PRAGMA journal_mode = WAL;")
    try exec(rawHandle: rawHandle, sql: "PRAGMA synchronous = NORMAL;")
    try exec(rawHandle: rawHandle, sql: "PRAGMA foreign_keys = ON;")
    try exec(rawHandle: rawHandle, sql: "PRAGMA busy_timeout = 3000;")
  }

  private static func runMigrations(rawHandle: OpaquePointer) throws {
    try exec(
      rawHandle: rawHandle,
      sql: "CREATE TABLE IF NOT EXISTS schema_migrations (version INTEGER PRIMARY KEY, name TEXT NOT NULL, applied_at INTEGER NOT NULL);"
    )

    let appliedVersions = Set(try queryInts(rawHandle: rawHandle, sql: "SELECT version FROM schema_migrations;"))

    for migration in Migrations.all where !appliedVersions.contains(migration.version) {
      try exec(rawHandle: rawHandle, sql: "BEGIN;")
      do {
        try exec(rawHandle: rawHandle, sql: migration.sql)
        let recordSQL = "INSERT INTO schema_migrations (version, name, applied_at) VALUES (\(migration.version), '\(migration.name)', \(Int64(Date().timeIntervalSince1970)));"
        try exec(rawHandle: rawHandle, sql: recordSQL)
        try exec(rawHandle: rawHandle, sql: "COMMIT;")
      } catch {
        _ = sqlite3_exec(rawHandle, "ROLLBACK;", nil, nil, nil)
        let message = (error as? PersistenceError).map(\.description) ?? String(describing: error)
        throw PersistenceError.migrationFailed(version: migration.version, name: migration.name, message: message)
      }
    }
  }

  // MARK: - Public exec / query API

  /// Run an INSERT/UPDATE/DELETE (or any non-row-returning SQL). The bind
  /// closure runs against the prepared statement before stepping.
  func execute(_ sql: String, bind: (Statement) -> Void = { _ in }) throws {
    guard let handle else { throw PersistenceError.openFailed("connection closed") }
    let statement = try prepare(rawHandle: handle, sql: sql)
    defer { sqlite3_finalize(statement) }
    bind(Statement(handle: statement))
    let result = sqlite3_step(statement)
    guard result == SQLITE_DONE || result == SQLITE_ROW else {
      throw PersistenceError.stepFailed(String(cString: sqlite3_errmsg(handle)))
    }
  }

  /// Run a SELECT, mapping each row through `row`. The bind closure runs
  /// once before stepping; the row closure runs once per row.
  func query<T>(
    _ sql: String,
    bind: (Statement) -> Void = { _ in },
    row: (Statement) throws -> T
  ) throws -> [T] {
    guard let handle else { throw PersistenceError.openFailed("connection closed") }
    let statement = try prepare(rawHandle: handle, sql: sql)
    defer { sqlite3_finalize(statement) }
    bind(Statement(handle: statement))
    let wrapper = Statement(handle: statement)
    var results: [T] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      results.append(try row(wrapper))
    }
    return results
  }

  /// Convenience for SELECT-expecting-at-most-one-row.
  func queryOne<T>(
    _ sql: String,
    bind: (Statement) -> Void = { _ in },
    row: (Statement) throws -> T
  ) throws -> T? {
    try query(sql, bind: bind, row: row).first
  }

  // MARK: - Static helpers (used during init only)

  private static func exec(rawHandle: OpaquePointer, sql: String) throws {
    var errMsg: UnsafeMutablePointer<CChar>?
    if sqlite3_exec(rawHandle, sql, nil, nil, &errMsg) != SQLITE_OK {
      let message = errMsg.map { String(cString: $0) } ?? "exec failed"
      sqlite3_free(errMsg)
      throw PersistenceError.stepFailed(message)
    }
  }

  private static func queryInts(rawHandle: OpaquePointer, sql: String) throws -> [Int] {
    let statement = try prepare(rawHandle: rawHandle, sql: sql)
    defer { sqlite3_finalize(statement) }
    var results: [Int] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      results.append(Int(sqlite3_column_int64(statement, 0)))
    }
    return results
  }

  private static func prepare(rawHandle: OpaquePointer, sql: String) throws -> OpaquePointer {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(rawHandle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
      throw PersistenceError.prepareFailed(String(cString: sqlite3_errmsg(rawHandle)))
    }
    return statement
  }

  private func prepare(rawHandle: OpaquePointer, sql: String) throws -> OpaquePointer {
    try Database.prepare(rawHandle: rawHandle, sql: sql)
  }

  // MARK: - Default location

  /// `~/Library/Application Support/Moves/moves.sqlite3` (created if missing).
  static func defaultURL() -> URL {
    let fm = FileManager.default
    let base = (try? fm.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )) ?? fm.temporaryDirectory
    let dir = base.appending(path: "Moves", directoryHint: .isDirectory)
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appending(path: "moves.sqlite3")
  }
}
