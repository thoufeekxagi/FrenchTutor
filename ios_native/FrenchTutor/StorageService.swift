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

        exec(createSessions)
        exec(createMessages)
    }

    private func exec(_ sql: String) {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            print("SQL error: \(String(cString: sqlite3_errmsg(db)))")
        }
    }

    func saveSession(_ session: Session) {
        let sql = "INSERT OR REPLACE INTO sessions (id, started_at, ended_at, summary, topic, vocabulary) VALUES (?,?,?,?,?,?);"
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
        let sql = "SELECT id, started_at, ended_at, summary, topic, vocabulary FROM sessions ORDER BY started_at DESC;"
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
                sessions.append(Session(id: id, startedAt: startedAt, endedAt: endedAt, summary: summary, topic: topic, vocabulary: vocabulary))
            }
        }
        sqlite3_finalize(stmt)
        return sessions
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
}
