import Foundation
import SQLite3

enum DatabaseError: Error {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

actor Database {
    private var db: OpaquePointer?

    init(path: String) throws {
        var handle: OpaquePointer?
        guard sqlite3_open(path, &handle) == SQLITE_OK, let handle else {
            let msg = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            if let handle { sqlite3_close(handle) }
            throw DatabaseError.openFailed(msg)
        }
        self.db = handle

        let schema = """
            CREATE TABLE IF NOT EXISTS moves (
                id TEXT PRIMARY KEY NOT NULL,
                title TEXT NOT NULL,
                done INTEGER NOT NULL DEFAULT 0,
                created REAL NOT NULL
            );
        """
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, schema, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "schema failed"
            sqlite3_free(err)
            sqlite3_close(handle)
            throw DatabaseError.openFailed(msg)
        }
    }

    func all() throws -> [Move] {
        let sql = "SELECT id, title, done, created FROM moves ORDER BY created DESC;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastError())
        }
        defer { sqlite3_finalize(stmt) }

        var rows: [Move] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard
                let idC = sqlite3_column_text(stmt, 0),
                let titleC = sqlite3_column_text(stmt, 1),
                let uuid = UUID(uuidString: String(cString: idC))
            else { continue }
            let title = String(cString: titleC)
            let done = sqlite3_column_int(stmt, 2) != 0
            let created = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))
            rows.append(Move(id: uuid, title: title, done: done, created: created))
        }
        return rows
    }

    func upsert(_ move: Move) throws {
        let sql = """
            INSERT INTO moves (id, title, done, created)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title = excluded.title,
                done  = excluded.done,
                created = excluded.created;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastError())
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, move.id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, move.title, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 3, move.done ? 1 : 0)
        sqlite3_bind_double(stmt, 4, move.created.timeIntervalSince1970)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.stepFailed(lastError())
        }
    }

    func delete(id: UUID) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM moves WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastError())
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.stepFailed(lastError())
        }
    }

    private func lastError() -> String {
        guard let db else { return "no db" }
        return String(cString: sqlite3_errmsg(db))
    }

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
