import Foundation
import SQLite3

enum DBError: Error {
    case open(String)
    case exec(String)
    case prepare(String)
}

/// Envoltorio mínimo sobre la API C de SQLite. Sin dependencias externas.
final class Database {
    private var db: OpaquePointer?
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(path: String) throws {
        if sqlite3_open(path, &db) != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(db))
            sqlite3_close(db)
            throw DBError.open(msg)
        }
        try exec("PRAGMA journal_mode=WAL;")
        try exec("PRAGMA foreign_keys=ON;")
        try migrate()
    }

    deinit {
        sqlite3_close(db)
    }

    private func migrate() throws {
        try exec("""
        CREATE TABLE IF NOT EXISTS items (
            id            TEXT PRIMARY KEY,
            kind          TEXT NOT NULL,
            text          TEXT,
            image_path    TEXT,
            thumb_path    TEXT,
            ocr_text      TEXT,
            source_app    TEXT,
            source_bundle TEXT,
            created_at    REAL NOT NULL,
            pinned        INTEGER NOT NULL DEFAULT 0,
            category      TEXT,
            content_hash  TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_items_created ON items(created_at DESC);
        CREATE INDEX IF NOT EXISTS idx_items_hash ON items(content_hash);
        CREATE INDEX IF NOT EXISTS idx_items_kind ON items(kind);
        """)
    }

    // MARK: - Primitivas

    func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "sqlite error"
            sqlite3_free(err)
            throw DBError.exec(msg)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw DBError.prepare(String(cString: sqlite3_errmsg(db)))
        }
        return stmt
    }

    private func bind(_ stmt: OpaquePointer, _ values: [Any?]) {
        for (i, value) in values.enumerated() {
            let idx = Int32(i + 1)
            guard let v = value else {
                sqlite3_bind_null(stmt, idx)
                continue
            }
            // Se comprueba el tipo dinámico exacto para evitar el bridging Bool/Int/Double de NSNumber.
            let t = type(of: v)
            if t == Bool.self {
                sqlite3_bind_int(stmt, idx, (v as! Bool) ? 1 : 0)
            } else if t == Int.self {
                sqlite3_bind_int64(stmt, idx, Int64(v as! Int))
            } else if t == Double.self {
                sqlite3_bind_double(stmt, idx, v as! Double)
            } else if let s = v as? String {
                sqlite3_bind_text(stmt, idx, s, -1, Database.transient)
            } else {
                sqlite3_bind_null(stmt, idx)
            }
        }
    }

    func run(_ sql: String, _ values: [Any?] = []) throws {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, values)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DBError.exec(String(cString: sqlite3_errmsg(db)))
        }
    }

    func query(_ sql: String, _ values: [Any?] = []) throws -> [[String: Any]] {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, values)
        var rows: [[String: Any]] = []
        let count = sqlite3_column_count(stmt)
        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [String: Any] = [:]
            for c in 0..<count {
                let name = String(cString: sqlite3_column_name(stmt, c))
                switch sqlite3_column_type(stmt, c) {
                case SQLITE_INTEGER: row[name] = Int(sqlite3_column_int64(stmt, c))
                case SQLITE_FLOAT: row[name] = sqlite3_column_double(stmt, c)
                case SQLITE_TEXT:
                    if let p = sqlite3_column_text(stmt, c) { row[name] = String(cString: p) }
                default: break
                }
            }
            rows.append(row)
        }
        return rows
    }
}

// MARK: - Operaciones sobre items

extension Database {
    func insert(_ it: ClipItem) throws {
        try run("""
        INSERT INTO items (id, kind, text, image_path, thumb_path, ocr_text, source_app, source_bundle,
                           created_at, pinned, category, content_hash)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, [
            it.id, it.kind.rawValue, it.text, it.imagePath, it.thumbPath, it.ocrText,
            it.sourceAppName, it.sourceBundleID, it.createdAt.timeIntervalSince1970,
            it.pinned, it.category, it.contentHash,
        ])
    }

    func findByHash(_ hash: String) throws -> ClipItem? {
        try query("SELECT * FROM items WHERE content_hash = ? LIMIT 1", [hash])
            .compactMap(ClipItem.init(row:)).first
    }

    func touch(id: String, source: SourceApp) throws {
        try run("UPDATE items SET created_at = ?, source_app = COALESCE(?, source_app), source_bundle = COALESCE(?, source_bundle) WHERE id = ?",
                [Date().timeIntervalSince1970, source.name, source.bundleID, id])
    }

    func fetch(search: String, kind: ClipKind?, bundle: String?, limit: Int) throws -> [ClipItem] {
        var sql = "SELECT * FROM items WHERE 1=1"
        var vals: [Any?] = []
        if let kind {
            sql += " AND kind = ?"
            vals.append(kind.rawValue)
        }
        if let bundle {
            sql += " AND source_bundle = ?"
            vals.append(bundle)
        }
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            let like = "%\(q)%"
            sql += " AND (text LIKE ? OR ocr_text LIKE ? OR source_app LIKE ? OR category LIKE ?)"
            vals.append(contentsOf: [like, like, like, like] as [Any?])
        }
        sql += " ORDER BY pinned DESC, created_at DESC LIMIT ?"
        vals.append(limit)
        return try query(sql, vals).compactMap(ClipItem.init(row:))
    }

    func recent(limit: Int) throws -> [ClipItem] {
        try query("SELECT * FROM items ORDER BY created_at DESC LIMIT ?", [limit])
            .compactMap(ClipItem.init(row:))
    }

    func distinctApps() throws -> [(bundle: String, name: String)] {
        try query("""
        SELECT source_bundle AS b, MAX(source_app) AS n, COUNT(*) AS c
        FROM items WHERE source_bundle IS NOT NULL
        GROUP BY source_bundle ORDER BY c DESC
        """).compactMap { row in
            guard let b = row["b"] as? String else { return nil }
            return (bundle: b, name: (row["n"] as? String) ?? b)
        }
    }

    func setPinned(id: String, _ pinned: Bool) throws {
        try run("UPDATE items SET pinned = ? WHERE id = ?", [pinned, id])
    }

    func setOCR(id: String, text: String?) throws {
        try run("UPDATE items SET ocr_text = ? WHERE id = ?", [text, id])
    }

    func setCategory(id: String, category: String?) throws {
        try run("UPDATE items SET category = ? WHERE id = ?", [category, id])
    }

    func delete(id: String) throws {
        try run("DELETE FROM items WHERE id = ?", [id])
    }

    /// Devuelve los items no fijados que sobran por encima de `keep`, del más antiguo al más nuevo.
    func overflow(keep: Int) throws -> [ClipItem] {
        try query("SELECT * FROM items WHERE pinned = 0 ORDER BY created_at DESC LIMIT -1 OFFSET ?", [keep])
            .compactMap(ClipItem.init(row:))
    }

    func allUnpinned() throws -> [ClipItem] {
        try query("SELECT * FROM items WHERE pinned = 0").compactMap(ClipItem.init(row:))
    }
}
