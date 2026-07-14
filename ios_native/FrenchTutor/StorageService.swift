import Foundation
import SQLite3

class StorageService {
    private var db: OpaquePointer?

    init() {
        openDB()
    }

    private func openDB() {
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dbPath = docsDir.appendingPathComponent("french_tutor.db").path

        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("Failed to open DB")
            return
        }

        let createSessions = """
        CREATE TABLE IF NOT EXISTS sessions (
            id TEXT PRIMARY KEY,
            started_at TEXT NOT NULL,
            ended_at TEXT,
            summary TEXT,
            topic TEXT,
            vocabulary TEXT
        );
        """

        let createMessages = """
        CREATE TABLE IF NOT EXISTS messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL,
            role TEXT NOT NULL,
            content TEXT NOT NULL,
            created_at TEXT NOT NULL
        );
        """

        // Notes captured via the floating notetaker overlay. `tag` is the lesson/module the note
        // was taken during (e.g. "Vocabulary", "Listening"), used to group notes for review later.
        // `times_shown`/`last_shown_at` support a Readwise-style resurfacing pass down the line
        // (probability of resurfacing decays as a note is shown more).
        let createNotes = """
        CREATE TABLE IF NOT EXISTS notes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            tag TEXT,
            text TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            times_shown INTEGER NOT NULL DEFAULT 0,
            last_shown_at TEXT
        );
        """

        exec(createSessions)
        exec(createMessages)
        exec(createNotes)
        // Added after the sessions table already shipped — ALTER TABLE ADD COLUMN fails on a DB
        // that already has it, which `exec` just logs and ignores, so this is safe to run on
        // every launch rather than needing a real migration system.
        exec("ALTER TABLE sessions ADD COLUMN stage TEXT;")
    }

    private func exec(_ sql: String) {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            print("SQL error: \(String(cString: sqlite3_errmsg(db)))")
        }
    }

    func saveSession(_ session: Session) {
        let sql = "INSERT OR REPLACE INTO sessions (id, started_at, ended_at, summary, topic, vocabulary, stage) VALUES (?,?,?,?,?,?,?);"
        var stmt: OpaquePointer?

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, session.id, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(stmt, 2, session.startedAt, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            if let endedAt = session.endedAt {
                sqlite3_bind_text(stmt, 3, endedAt, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            } else {
                sqlite3_bind_null(stmt, 3)
            }
            if let summary = session.summary {
                sqlite3_bind_text(stmt, 4, summary, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            } else {
                sqlite3_bind_null(stmt, 4)
            }
            if let topic = session.topic {
                sqlite3_bind_text(stmt, 5, topic, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            } else {
                sqlite3_bind_null(stmt, 5)
            }
            let vocabData = try? JSONSerialization.data(withJSONObject: session.vocabulary)
            let vocabStr = vocabData.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            sqlite3_bind_text(stmt, 6, vocabStr, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            if let stage = session.stage {
                sqlite3_bind_text(stmt, 7, stage, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            } else {
                sqlite3_bind_null(stmt, 7)
            }

            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    func saveMessage(sessionId: String, role: String, content: String) {
        let sql = "INSERT INTO messages (session_id, role, content, created_at) VALUES (?,?,?,?);"
        var stmt: OpaquePointer?

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            let now = ISO8601DateFormatter().string(from: Date())
            sqlite3_bind_text(stmt, 1, sessionId, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(stmt, 2, role, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(stmt, 3, content, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(stmt, 4, now, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    func getAllSessions() -> [Session] {
        let sql = "SELECT id, started_at, ended_at, summary, topic, vocabulary, stage FROM sessions ORDER BY started_at DESC;"
        var stmt: OpaquePointer?
        var sessions: [Session] = []

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(stmt, 0))
                let startedAt = String(cString: sqlite3_column_text(stmt, 1))
                let endedAt = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
                let summary = sqlite3_column_text(stmt, 3).map { String(cString: $0) }
                let topic = sqlite3_column_text(stmt, 4).map { String(cString: $0) }
                var vocabulary: [String] = []
                if let vocabCStr = sqlite3_column_text(stmt, 5) {
                    let vocabStr = String(cString: vocabCStr)
                    if let data = vocabStr.data(using: .utf8),
                       let arr = try? JSONSerialization.jsonObject(with: data) as? [String] {
                        vocabulary = arr
                    }
                }
                let stage = sqlite3_column_text(stmt, 6).map { String(cString: $0) }
                sessions.append(Session(id: id, startedAt: startedAt, endedAt: endedAt, summary: summary, topic: topic, vocabulary: vocabulary, stage: stage))
            }
        }
        sqlite3_finalize(stmt)
        return sessions
    }

    /// Most recent completed session tagged with the given stage — used by the Grammar stage to
    /// pull the just-finished Vocab session's transcript (words practiced, how it went) to build
    /// today's grammar practice around, per STRUCTURE.md's "pre-generate once" rule: this is read
    /// once, before the grammar session starts, never polled live during teaching.
    func mostRecentSession(stage: String) -> Session? {
        let sql = "SELECT id, started_at, ended_at, summary, topic, vocabulary, stage FROM sessions WHERE stage = ? ORDER BY started_at DESC LIMIT 1;"
        var stmt: OpaquePointer?
        var result: Session?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, stage, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            if sqlite3_step(stmt) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(stmt, 0))
                let startedAt = String(cString: sqlite3_column_text(stmt, 1))
                let endedAt = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
                let summary = sqlite3_column_text(stmt, 3).map { String(cString: $0) }
                let topic = sqlite3_column_text(stmt, 4).map { String(cString: $0) }
                let stageValue = sqlite3_column_text(stmt, 6).map { String(cString: $0) }
                result = Session(id: id, startedAt: startedAt, endedAt: endedAt, summary: summary, topic: topic, vocabulary: [], stage: stageValue)
            }
        }
        sqlite3_finalize(stmt)
        return result
    }

    func getSessionMessages(sessionId: String) -> [(role: String, content: String)] {
        let sql = "SELECT role, content FROM messages WHERE session_id = ? ORDER BY id ASC;"
        var stmt: OpaquePointer?
        var messages: [(String, String)] = []

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, sessionId, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            while sqlite3_step(stmt) == SQLITE_ROW {
                let role = String(cString: sqlite3_column_text(stmt, 0))
                let content = String(cString: sqlite3_column_text(stmt, 1))
                messages.append((role, content))
            }
        }
        sqlite3_finalize(stmt)
        return messages
    }

    func deleteSession(sessionId: String) {
        exec("DELETE FROM messages WHERE session_id = '\(sessionId)';")
        exec("DELETE FROM sessions WHERE id = '\(sessionId)';")
    }

    // MARK: - Notes (floating notetaker)

    /// Inserts a new note and returns its row id, or updates an existing one in place when
    /// `id` is passed — the same call handles the periodic autosave and the final manual save.
    @discardableResult
    func saveNote(id: Int64?, tag: String?, text: String) -> Int64 {
        let now = ISO8601DateFormatter().string(from: Date())
        if let id {
            let sql = "UPDATE notes SET text = ?, tag = ?, updated_at = ? WHERE id = ?;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, text, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                if let tag {
                    sqlite3_bind_text(stmt, 2, tag, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                } else {
                    sqlite3_bind_null(stmt, 2)
                }
                sqlite3_bind_text(stmt, 3, now, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_int64(stmt, 4, id)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
            return id
        } else {
            let sql = "INSERT INTO notes (tag, text, created_at, updated_at, times_shown, last_shown_at) VALUES (?,?,?,?,0,NULL);"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                if let tag {
                    sqlite3_bind_text(stmt, 1, tag, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                } else {
                    sqlite3_bind_null(stmt, 1)
                }
                sqlite3_bind_text(stmt, 2, text, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_text(stmt, 3, now, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_text(stmt, 4, now, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
            return sqlite3_last_insert_rowid(db)
        }
    }

    func getAllNotes() -> [Note] {
        let sql = "SELECT id, tag, text, created_at, updated_at, times_shown FROM notes ORDER BY updated_at DESC;"
        var stmt: OpaquePointer?
        var notes: [Note] = []
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                let tag = sqlite3_column_text(stmt, 1).map { String(cString: $0) }
                let text = String(cString: sqlite3_column_text(stmt, 2))
                let createdAt = String(cString: sqlite3_column_text(stmt, 3))
                let updatedAt = String(cString: sqlite3_column_text(stmt, 4))
                let timesShown = Int(sqlite3_column_int(stmt, 5))
                notes.append(Note(id: id, tag: tag, text: text, createdAt: createdAt, updatedAt: updatedAt, timesShown: timesShown))
            }
        }
        sqlite3_finalize(stmt)
        return notes
    }

    func deleteNote(id: Int64) {
        exec("DELETE FROM notes WHERE id = \(id);")
    }
}
