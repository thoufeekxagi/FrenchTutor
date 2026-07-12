import Foundation
import SQLite3

struct SRSState {
    var entryId: String
    var ease: Double = 2.5
    var intervalDays: Double = 0
    var reps: Int = 0
    var dueAt: Date?
    var lastGrade: Int?
}

struct WritingSubmission: Identifiable {
    let id: Int
    let taskId: String
    let content: String
    let feedback: String?
    let score: Double?
    let createdAt: String
}

/// Persistence for learning data. Shares french_tutor.db with StorageService
/// (which owns sessions/messages) — WAL + busy timeout make the two
/// connections coexist safely.
class LearningStore {
    private var db: OpaquePointer?
    private let iso = ISO8601DateFormatter()

    init() {
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dbPath = docsDir.appendingPathComponent("french_tutor.db").path

        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("LearningStore: failed to open DB")
            return
        }
        sqlite3_busy_timeout(db, 2000)
        exec("PRAGMA journal_mode=WAL;")

        exec("""
        CREATE TABLE IF NOT EXISTS vocab_srs (
            entry_id TEXT PRIMARY KEY,
            ease REAL NOT NULL DEFAULT 2.5,
            interval_days REAL NOT NULL DEFAULT 0,
            reps INTEGER NOT NULL DEFAULT 0,
            due_at TEXT,
            last_grade INTEGER,
            updated_at TEXT
        );
        """)
        exec("""
        CREATE TABLE IF NOT EXISTS lesson_progress (
            lesson_id TEXT PRIMARY KEY,
            status TEXT NOT NULL DEFAULT 'not_started',
            score REAL,
            completed_at TEXT
        );
        """)
        exec("""
        CREATE TABLE IF NOT EXISTS daily_activity (
            date TEXT NOT NULL,
            habit_id TEXT NOT NULL,
            minutes INTEGER NOT NULL DEFAULT 0,
            done INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (date, habit_id)
        );
        """)
        exec("""
        CREATE TABLE IF NOT EXISTS writing_submissions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            task_id TEXT NOT NULL,
            content TEXT NOT NULL,
            feedback TEXT,
            score REAL,
            created_at TEXT NOT NULL
        );
        """)
    }

    deinit {
        sqlite3_close(db)
    }

    private func exec(_ sql: String) {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            print("LearningStore SQL error: \(String(cString: sqlite3_errmsg(db)))")
        }
    }

    private func bindText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String) {
        sqlite3_bind_text(stmt, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }

    // MARK: - SRS

    func srsState(for entryId: String) -> SRSState? {
        let sql = "SELECT ease, interval_days, reps, due_at, last_grade FROM vocab_srs WHERE entry_id = ?;"
        var stmt: OpaquePointer?
        var state: SRSState?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, 1, entryId)
            if sqlite3_step(stmt) == SQLITE_ROW {
                var s = SRSState(entryId: entryId)
                s.ease = sqlite3_column_double(stmt, 0)
                s.intervalDays = sqlite3_column_double(stmt, 1)
                s.reps = Int(sqlite3_column_int(stmt, 2))
                if let dueCStr = sqlite3_column_text(stmt, 3) {
                    s.dueAt = iso.date(from: String(cString: dueCStr))
                }
                if sqlite3_column_type(stmt, 4) != SQLITE_NULL {
                    s.lastGrade = Int(sqlite3_column_int(stmt, 4))
                }
                state = s
            }
        }
        sqlite3_finalize(stmt)
        return state
    }

    func allSRSStates() -> [String: SRSState] {
        let sql = "SELECT entry_id, ease, interval_days, reps, due_at, last_grade FROM vocab_srs;"
        var stmt: OpaquePointer?
        var states: [String: SRSState] = [:]
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let entryId = String(cString: sqlite3_column_text(stmt, 0))
                var s = SRSState(entryId: entryId)
                s.ease = sqlite3_column_double(stmt, 1)
                s.intervalDays = sqlite3_column_double(stmt, 2)
                s.reps = Int(sqlite3_column_int(stmt, 3))
                if let dueCStr = sqlite3_column_text(stmt, 4) {
                    s.dueAt = iso.date(from: String(cString: dueCStr))
                }
                if sqlite3_column_type(stmt, 5) != SQLITE_NULL {
                    s.lastGrade = Int(sqlite3_column_int(stmt, 5))
                }
                states[entryId] = s
            }
        }
        sqlite3_finalize(stmt)
        return states
    }

    func upsertSRS(_ state: SRSState) {
        let sql = """
        INSERT OR REPLACE INTO vocab_srs (entry_id, ease, interval_days, reps, due_at, last_grade, updated_at)
        VALUES (?,?,?,?,?,?,?);
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, 1, state.entryId)
            sqlite3_bind_double(stmt, 2, state.ease)
            sqlite3_bind_double(stmt, 3, state.intervalDays)
            sqlite3_bind_int(stmt, 4, Int32(state.reps))
            if let due = state.dueAt {
                bindText(stmt, 5, iso.string(from: due))
            } else {
                sqlite3_bind_null(stmt, 5)
            }
            if let grade = state.lastGrade {
                sqlite3_bind_int(stmt, 6, Int32(grade))
            } else {
                sqlite3_bind_null(stmt, 6)
            }
            bindText(stmt, 7, iso.string(from: Date()))
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    /// Count of NEW cards (reps == 0 rows inserted today) — used for the daily new-card cap.
    func newEntriesIntroducedToday() -> Int {
        let today = dayString(Date())
        let sql = "SELECT COUNT(*) FROM vocab_srs WHERE reps <= 1 AND updated_at LIKE ?;"
        var stmt: OpaquePointer?
        var count = 0
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, 1, today + "%")
            if sqlite3_step(stmt) == SQLITE_ROW {
                count = Int(sqlite3_column_int(stmt, 0))
            }
        }
        sqlite3_finalize(stmt)
        return count
    }

    // MARK: - Lesson progress

    func lessonStatus(_ lessonId: String) -> (status: String, score: Double?) {
        let sql = "SELECT status, score FROM lesson_progress WHERE lesson_id = ?;"
        var stmt: OpaquePointer?
        var result: (String, Double?) = ("not_started", nil)
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, 1, lessonId)
            if sqlite3_step(stmt) == SQLITE_ROW {
                let status = String(cString: sqlite3_column_text(stmt, 0))
                let score: Double? = sqlite3_column_type(stmt, 1) != SQLITE_NULL ? sqlite3_column_double(stmt, 1) : nil
                result = (status, score)
            }
        }
        sqlite3_finalize(stmt)
        return result
    }

    func allLessonProgress() -> [String: (status: String, score: Double?)] {
        let sql = "SELECT lesson_id, status, score FROM lesson_progress;"
        var stmt: OpaquePointer?
        var result: [String: (String, Double?)] = [:]
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(stmt, 0))
                let status = String(cString: sqlite3_column_text(stmt, 1))
                let score: Double? = sqlite3_column_type(stmt, 2) != SQLITE_NULL ? sqlite3_column_double(stmt, 2) : nil
                result[id] = (status, score)
            }
        }
        sqlite3_finalize(stmt)
        return result
    }

    func setLessonStatus(_ lessonId: String, status: String, score: Double? = nil) {
        let sql = """
        INSERT OR REPLACE INTO lesson_progress (lesson_id, status, score, completed_at)
        VALUES (?,?,?,?);
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, 1, lessonId)
            bindText(stmt, 2, status)
            if let score = score {
                sqlite3_bind_double(stmt, 3, score)
            } else {
                sqlite3_bind_null(stmt, 3)
            }
            if status == "completed" {
                bindText(stmt, 4, iso.string(from: Date()))
            } else {
                sqlite3_bind_null(stmt, 4)
            }
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    // MARK: - Daily activity

    func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    func markHabit(date: Date, habitId: String, done: Bool, addMinutes: Int = 0) {
        let day = dayString(date)
        let existing = habits(on: date)[habitId]
        let minutes = (existing?.minutes ?? 0) + addMinutes
        let sql = """
        INSERT OR REPLACE INTO daily_activity (date, habit_id, minutes, done)
        VALUES (?,?,?,?);
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, 1, day)
            bindText(stmt, 2, habitId)
            sqlite3_bind_int(stmt, 3, Int32(minutes))
            sqlite3_bind_int(stmt, 4, done ? 1 : 0)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    func habits(on date: Date) -> [String: (minutes: Int, done: Bool)] {
        let day = dayString(date)
        let sql = "SELECT habit_id, minutes, done FROM daily_activity WHERE date = ?;"
        var stmt: OpaquePointer?
        var result: [String: (Int, Bool)] = [:]
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, 1, day)
            while sqlite3_step(stmt) == SQLITE_ROW {
                let habitId = String(cString: sqlite3_column_text(stmt, 0))
                let minutes = Int(sqlite3_column_int(stmt, 1))
                let done = sqlite3_column_int(stmt, 2) == 1
                result[habitId] = (minutes, done)
            }
        }
        sqlite3_finalize(stmt)
        return result
    }

    /// Distinct days (yyyy-MM-dd) with at least one habit done, newest first.
    func activeDays() -> [String] {
        let sql = "SELECT DISTINCT date FROM daily_activity WHERE done = 1 ORDER BY date DESC;"
        var stmt: OpaquePointer?
        var days: [String] = []
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                days.append(String(cString: sqlite3_column_text(stmt, 0)))
            }
        }
        sqlite3_finalize(stmt)
        return days
    }

    // MARK: - Writing submissions

    func saveSubmission(taskId: String, content: String, feedback: String?, score: Double?) {
        let sql = """
        INSERT INTO writing_submissions (task_id, content, feedback, score, created_at)
        VALUES (?,?,?,?,?);
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, 1, taskId)
            bindText(stmt, 2, content)
            if let feedback = feedback {
                bindText(stmt, 3, feedback)
            } else {
                sqlite3_bind_null(stmt, 3)
            }
            if let score = score {
                sqlite3_bind_double(stmt, 4, score)
            } else {
                sqlite3_bind_null(stmt, 4)
            }
            bindText(stmt, 5, iso.string(from: Date()))
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    func submissions(for taskId: String? = nil) -> [WritingSubmission] {
        let sql = taskId != nil
            ? "SELECT id, task_id, content, feedback, score, created_at FROM writing_submissions WHERE task_id = ? ORDER BY id DESC;"
            : "SELECT id, task_id, content, feedback, score, created_at FROM writing_submissions ORDER BY id DESC;"
        var stmt: OpaquePointer?
        var result: [WritingSubmission] = []
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            if let taskId = taskId {
                bindText(stmt, 1, taskId)
            }
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = Int(sqlite3_column_int(stmt, 0))
                let task = String(cString: sqlite3_column_text(stmt, 1))
                let content = String(cString: sqlite3_column_text(stmt, 2))
                let feedback = sqlite3_column_text(stmt, 3).map { String(cString: $0) }
                let score: Double? = sqlite3_column_type(stmt, 4) != SQLITE_NULL ? sqlite3_column_double(stmt, 4) : nil
                let createdAt = String(cString: sqlite3_column_text(stmt, 5))
                result.append(WritingSubmission(id: id, taskId: task, content: content, feedback: feedback, score: score, createdAt: createdAt))
            }
        }
        sqlite3_finalize(stmt)
        return result
    }
}
