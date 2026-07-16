import Foundation
import os
import SQLite3

private let storeLog = Logger(subsystem: "dev.smathdaddy.openwispr", category: "KordStore")
private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class KordStore {
    static let shared = KordStore()

    private let queue = DispatchQueue(label: "dev.smathdaddy.openwispr.kordstore")
    private var db: OpaquePointer?

    private init() {
        openDatabase()
        createSchema()
        migrateLegacyDefaultsIfNeeded()
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    func fetchNotes(limit: Int, fallback: [OpenwisprNote]) -> [OpenwisprNote] {
        withDatabase(fallback: fallback) { db in
            let sql = """
            SELECT id, title, body, created_at, updated_at
            FROM notes
            ORDER BY updated_at DESC
            LIMIT ?;
            """
            guard let statement = prepare(sql, on: db) else { return fallback }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int(statement, 1, Int32(limit))

            var notes: [OpenwisprNote] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                notes.append(OpenwisprNote(
                    id: columnText(statement, 0) ?? UUID().uuidString,
                    title: columnText(statement, 1) ?? "",
                    body: columnText(statement, 2) ?? "",
                    createdAt: sqlite3_column_double(statement, 3),
                    updatedAt: sqlite3_column_double(statement, 4)
                ))
            }
            return notes
        }
    }

    func replaceNotes(_ notes: [OpenwisprNote]) {
        withDatabase(fallback: ()) { db in
            transaction(on: db) {
                guard execute("DELETE FROM notes;", on: db) else { return false }
                return notes.allSatisfy { insertNote($0, on: db) }
            }
        }
    }

    func replaceNotesAndTombstones(notes: [OpenwisprNote], tombstones: [KordNoteTombstone]) {
        withDatabase(fallback: ()) { db in
            transaction(on: db) {
                guard execute("DELETE FROM notes;", on: db),
                      execute("DELETE FROM deleted_notes;", on: db) else {
                    return false
                }
                let notesOK = notes.allSatisfy { insertNote($0, on: db) }
                let tombstonesOK = tombstones.allSatisfy { insertNoteTombstone($0, on: db) }
                return notesOK && tombstonesOK
            }
        }
    }

    func saveNote(_ note: OpenwisprNote) {
        withDatabase(fallback: ()) { db in
            _ = insertNote(note, on: db)
        }
    }

    func deleteNote(id: String) {
        withDatabase(fallback: ()) { db in
            transaction(on: db) {
                let tombstoneOK = insertNoteTombstone(KordNoteTombstone(id: id), on: db)
                let deleteOK = deleteByID("DELETE FROM notes WHERE id = ?;", id: id, on: db, context: "delete note failed")
                return tombstoneOK && deleteOK
            }
        }
    }

    func fetchNoteTombstones() -> [KordNoteTombstone] {
        withDatabase(fallback: []) { db in
            let sql = "SELECT id, deleted_at FROM deleted_notes ORDER BY deleted_at DESC;"
            guard let statement = prepare(sql, on: db) else { return [] }
            defer { sqlite3_finalize(statement) }

            var tombstones: [KordNoteTombstone] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                tombstones.append(KordNoteTombstone(
                    id: columnText(statement, 0) ?? UUID().uuidString,
                    deletedAt: sqlite3_column_double(statement, 1)
                ))
            }
            return tombstones
        }
    }

    func replaceNoteTombstones(_ tombstones: [KordNoteTombstone]) {
        withDatabase(fallback: ()) { db in
            transaction(on: db) {
                guard execute("DELETE FROM deleted_notes;", on: db) else { return false }
                return tombstones.allSatisfy { insertNoteTombstone($0, on: db) }
            }
        }
    }

    func fetchTranscripts(limit: Int, fallback: [TranscriptEntry]) -> [TranscriptEntry] {
        withDatabase(fallback: fallback) { db in
            let sql = """
            SELECT id, created_at, raw, text, audio_relative_path, source, title
            FROM transcripts
            ORDER BY created_at DESC
            LIMIT ?;
            """
            guard let statement = prepare(sql, on: db) else { return fallback }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int(statement, 1, Int32(limit))

            var entries: [TranscriptEntry] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                entries.append(TranscriptEntry(
                    id: columnText(statement, 0) ?? UUID().uuidString,
                    createdAt: sqlite3_column_double(statement, 1),
                    raw: columnText(statement, 2),
                    text: columnText(statement, 3) ?? "",
                    audioRelativePath: columnText(statement, 4),
                    source: columnText(statement, 5),
                    title: columnText(statement, 6)
                ))
            }
            return entries
        }
    }

    func replaceTranscripts(_ entries: [TranscriptEntry]) {
        withDatabase(fallback: ()) { db in
            transaction(on: db) {
                guard execute("DELETE FROM transcripts;", on: db) else { return false }
                return entries.allSatisfy { insertTranscript($0, on: db) }
            }
        }
    }

    func deleteTranscript(id: String) {
        withDatabase(fallback: ()) { db in
            let sql = "DELETE FROM transcripts WHERE id = ?;"
            guard let statement = prepare(sql, on: db) else { return }
            defer { sqlite3_finalize(statement) }
            bindText(id, at: 1, in: statement)
            if sqlite3_step(statement) != SQLITE_DONE {
                logSQLiteError("delete transcript failed", db)
            }
        }
    }

    func clearTranscriptHistory() {
        withDatabase(fallback: ()) { db in
            transaction(on: db) {
                execute("DELETE FROM transcripts;", on: db) &&
                    execute("DELETE FROM recent_transcripts;", on: db)
            }
        }
    }

    func fetchRecentTranscripts(limit: Int, fallback: [String]) -> [String] {
        withDatabase(fallback: fallback) { db in
            let sql = """
            SELECT text
            FROM recent_transcripts
            ORDER BY position ASC
            LIMIT ?;
            """
            guard let statement = prepare(sql, on: db) else { return fallback }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int(statement, 1, Int32(limit))

            var recents: [String] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let text = columnText(statement, 0), !text.isEmpty {
                    recents.append(text)
                }
            }
            return recents
        }
    }

    func replaceRecentTranscripts(_ recents: [String]) {
        withDatabase(fallback: ()) { db in
            transaction(on: db) {
                guard execute("DELETE FROM recent_transcripts;", on: db) else { return false }
                for (index, text) in recents.enumerated() {
                    guard insertRecentTranscript(text, position: index, on: db) else { return false }
                }
                return true
            }
        }
    }

    func fetchPendingSharedImports(limit: Int, fallback: [PendingSharedImport]) -> [PendingSharedImport] {
        withDatabase(fallback: fallback) { db in
            let sql = """
            SELECT id, kind, source, title, relative_path, created_at
            FROM pending_shared_imports
            ORDER BY created_at DESC
            LIMIT ?;
            """
            guard let statement = prepare(sql, on: db) else { return fallback }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int(statement, 1, Int32(limit))

            var imports: [PendingSharedImport] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let rawKind = columnText(statement, 1) ?? PendingSharedImport.Kind.file.rawValue
                imports.append(PendingSharedImport(
                    id: columnText(statement, 0) ?? UUID().uuidString,
                    kind: PendingSharedImport.Kind(rawValue: rawKind) ?? .file,
                    source: columnText(statement, 2) ?? "Share Sheet",
                    title: columnText(statement, 3) ?? "Shared recording",
                    relativePath: columnText(statement, 4) ?? "",
                    createdAt: sqlite3_column_double(statement, 5)
                ))
            }
            return imports
        }
    }

    func replacePendingSharedImports(_ imports: [PendingSharedImport]) {
        withDatabase(fallback: ()) { db in
            transaction(on: db) {
                guard execute("DELETE FROM pending_shared_imports;", on: db) else { return false }
                return imports.allSatisfy { insertPendingSharedImport($0, on: db) }
            }
        }
    }

    private func openDatabase() {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedConfig.appGroup) else {
            storeLog.error("app group container unavailable")
            return
        }

        do {
            try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        } catch {
            storeLog.error("failed to create app group directory: \(error.localizedDescription, privacy: .public)")
            return
        }

        let url = container.appendingPathComponent("Kord.sqlite")
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        var opened: OpaquePointer?
        guard sqlite3_open_v2(url.path, &opened, flags, nil) == SQLITE_OK else {
            if let opened {
                logSQLiteError("open database failed", opened)
                sqlite3_close(opened)
            } else {
                storeLog.error("open database failed before sqlite handle was created")
            }
            return
        }

        db = opened
        _ = execute("PRAGMA journal_mode = WAL;", on: opened!)
        _ = execute("PRAGMA foreign_keys = ON;", on: opened!)
        _ = execute("PRAGMA busy_timeout = 3000;", on: opened!)
        storeLog.info("database opened")
    }

    private func createSchema() {
        guard let db else { return }
        let statements = [
            """
            CREATE TABLE IF NOT EXISTS metadata (
                key TEXT PRIMARY KEY NOT NULL,
                value TEXT NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS notes (
                id TEXT PRIMARY KEY NOT NULL,
                title TEXT NOT NULL,
                body TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );
            """,
            "CREATE INDEX IF NOT EXISTS idx_notes_updated_at ON notes(updated_at DESC);",
            """
            CREATE TABLE IF NOT EXISTS deleted_notes (
                id TEXT PRIMARY KEY NOT NULL,
                deleted_at REAL NOT NULL
            );
            """,
            "CREATE INDEX IF NOT EXISTS idx_deleted_notes_deleted_at ON deleted_notes(deleted_at DESC);",
            """
            CREATE TABLE IF NOT EXISTS transcripts (
                id TEXT PRIMARY KEY NOT NULL,
                created_at REAL NOT NULL,
                raw TEXT,
                text TEXT NOT NULL,
                audio_relative_path TEXT,
                source TEXT,
                title TEXT
            );
            """,
            "CREATE INDEX IF NOT EXISTS idx_transcripts_created_at ON transcripts(created_at DESC);",
            """
            CREATE TABLE IF NOT EXISTS recent_transcripts (
                text TEXT PRIMARY KEY NOT NULL,
                position INTEGER NOT NULL,
                updated_at REAL NOT NULL
            );
            """,
            "CREATE INDEX IF NOT EXISTS idx_recent_transcripts_position ON recent_transcripts(position ASC);",
            """
            CREATE TABLE IF NOT EXISTS pending_shared_imports (
                id TEXT PRIMARY KEY NOT NULL,
                kind TEXT NOT NULL,
                source TEXT NOT NULL,
                title TEXT NOT NULL,
                relative_path TEXT NOT NULL,
                created_at REAL NOT NULL
            );
            """,
            "CREATE INDEX IF NOT EXISTS idx_pending_shared_imports_created_at ON pending_shared_imports(created_at DESC);"
        ]

        for statement in statements {
            _ = execute(statement, on: db)
        }
    }

    private func migrateLegacyDefaultsIfNeeded() {
        guard let db else { return }
        let migrationKey = "legacy_defaults_v1"
        guard metadataValue(for: migrationKey, on: db) != "done" else { return }
        guard let defaults = UserDefaults(suiteName: SharedConfig.appGroup) else { return }

        transaction(on: db) {
            var ok = true
            if let notes = decodeLegacy([OpenwisprNote].self, key: "notes", defaults: defaults) {
                ok = ok && notes.allSatisfy { insertNote($0, on: db) }
            }

            if let transcripts = decodeLegacy([TranscriptEntry].self, key: "transcriptHistory", defaults: defaults) {
                ok = ok && transcripts.allSatisfy { insertTranscript($0, on: db) }
            }

            if let pending = decodeLegacy([PendingSharedImport].self, key: "pendingSharedImports", defaults: defaults) {
                ok = ok && pending.allSatisfy { insertPendingSharedImport($0, on: db) }
            }

            let recents = (defaults.array(forKey: "recentTranscripts") as? [String]) ?? []
            for (index, text) in recents.enumerated() {
                ok = ok && insertRecentTranscript(text, position: index, on: db)
            }

            ok = ok && setMetadataValue("done", for: migrationKey, on: db)
            return ok
        }
        storeLog.info("legacy defaults migration checked")
    }

    private func insertNote(_ note: OpenwisprNote, on db: OpaquePointer) -> Bool {
        let sql = """
        INSERT OR REPLACE INTO notes (id, title, body, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?);
        """
        guard let statement = prepare(sql, on: db) else { return false }
        defer { sqlite3_finalize(statement) }
        bindText(note.id, at: 1, in: statement)
        bindText(note.title, at: 2, in: statement)
        bindText(note.body, at: 3, in: statement)
        sqlite3_bind_double(statement, 4, note.createdAt)
        sqlite3_bind_double(statement, 5, note.updatedAt)
        return stepDone(statement, db, context: "insert note failed")
    }

    private func insertNoteTombstone(_ tombstone: KordNoteTombstone, on db: OpaquePointer) -> Bool {
        let sql = """
        INSERT OR REPLACE INTO deleted_notes (id, deleted_at)
        VALUES (?, ?);
        """
        guard let statement = prepare(sql, on: db) else { return false }
        defer { sqlite3_finalize(statement) }
        bindText(tombstone.id, at: 1, in: statement)
        sqlite3_bind_double(statement, 2, tombstone.deletedAt)
        return stepDone(statement, db, context: "insert note tombstone failed")
    }

    private func insertTranscript(_ entry: TranscriptEntry, on db: OpaquePointer) -> Bool {
        let sql = """
        INSERT OR REPLACE INTO transcripts
            (id, created_at, raw, text, audio_relative_path, source, title)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """
        guard let statement = prepare(sql, on: db) else { return false }
        defer { sqlite3_finalize(statement) }
        bindText(entry.id, at: 1, in: statement)
        sqlite3_bind_double(statement, 2, entry.createdAt)
        bindText(entry.raw, at: 3, in: statement)
        bindText(entry.text, at: 4, in: statement)
        bindText(entry.audioRelativePath, at: 5, in: statement)
        bindText(entry.source, at: 6, in: statement)
        bindText(entry.title, at: 7, in: statement)
        return stepDone(statement, db, context: "insert transcript failed")
    }

    private func insertRecentTranscript(_ text: String, position: Int, on db: OpaquePointer) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        let sql = """
        INSERT OR REPLACE INTO recent_transcripts (text, position, updated_at)
        VALUES (?, ?, ?);
        """
        guard let statement = prepare(sql, on: db) else { return false }
        defer { sqlite3_finalize(statement) }
        bindText(trimmed, at: 1, in: statement)
        sqlite3_bind_int(statement, 2, Int32(position))
        sqlite3_bind_double(statement, 3, Date().timeIntervalSince1970 * 1000)
        return stepDone(statement, db, context: "insert recent transcript failed")
    }

    private func insertPendingSharedImport(_ pending: PendingSharedImport, on db: OpaquePointer) -> Bool {
        let sql = """
        INSERT OR REPLACE INTO pending_shared_imports
            (id, kind, source, title, relative_path, created_at)
        VALUES (?, ?, ?, ?, ?, ?);
        """
        guard let statement = prepare(sql, on: db) else { return false }
        defer { sqlite3_finalize(statement) }
        bindText(pending.id, at: 1, in: statement)
        bindText(pending.kind.rawValue, at: 2, in: statement)
        bindText(pending.source, at: 3, in: statement)
        bindText(pending.title, at: 4, in: statement)
        bindText(pending.relativePath, at: 5, in: statement)
        sqlite3_bind_double(statement, 6, pending.createdAt)
        return stepDone(statement, db, context: "insert pending import failed")
    }

    private func metadataValue(for key: String, on db: OpaquePointer) -> String? {
        let sql = "SELECT value FROM metadata WHERE key = ? LIMIT 1;"
        guard let statement = prepare(sql, on: db) else { return nil }
        defer { sqlite3_finalize(statement) }
        bindText(key, at: 1, in: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return columnText(statement, 0)
    }

    private func setMetadataValue(_ value: String, for key: String, on db: OpaquePointer) -> Bool {
        let sql = "INSERT OR REPLACE INTO metadata (key, value) VALUES (?, ?);"
        guard let statement = prepare(sql, on: db) else { return false }
        defer { sqlite3_finalize(statement) }
        bindText(key, at: 1, in: statement)
        bindText(value, at: 2, in: statement)
        return stepDone(statement, db, context: "set metadata failed")
    }

    private func deleteByID(_ sql: String, id: String, on db: OpaquePointer, context: String) -> Bool {
        guard let statement = prepare(sql, on: db) else { return false }
        defer { sqlite3_finalize(statement) }
        bindText(id, at: 1, in: statement)
        return stepDone(statement, db, context: context)
    }

    private func withDatabase<T>(fallback: T, _ body: (OpaquePointer) -> T) -> T {
        queue.sync {
            guard let db else { return fallback }
            return body(db)
        }
    }

    @discardableResult
    private func transaction(on db: OpaquePointer, _ body: () -> Bool) -> Bool {
        guard execute("BEGIN IMMEDIATE TRANSACTION;", on: db) else { return false }
        if body() {
            return execute("COMMIT;", on: db)
        } else {
            _ = execute("ROLLBACK;", on: db)
            return false
        }
    }

    @discardableResult
    private func execute(_ sql: String, on db: OpaquePointer) -> Bool {
        var error: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &error)
        if result != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? "unknown sqlite error"
            storeLog.error("sqlite exec failed: \(message, privacy: .public)")
            sqlite3_free(error)
            return false
        }
        return true
    }

    private func prepare(_ sql: String, on db: OpaquePointer) -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            logSQLiteError("prepare failed", db)
            return nil
        }
        return statement
    }

    private func stepDone(_ statement: OpaquePointer?, _ db: OpaquePointer, context: String) -> Bool {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            logSQLiteError(context, db)
            return false
        }
        return true
    }

    private func bindText(_ text: String?, at index: Int32, in statement: OpaquePointer?) {
        if let text {
            sqlite3_bind_text(statement, index, text, -1, sqliteTransient)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: pointer)
    }

    private func logSQLiteError(_ context: String, _ db: OpaquePointer) {
        let message = sqlite3_errmsg(db).map { String(cString: $0) } ?? "unknown sqlite error"
        storeLog.error("\(context, privacy: .public): \(message, privacy: .public)")
    }

    private func decodeLegacy<T: Decodable>(_ type: T.Type, key: String, defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
