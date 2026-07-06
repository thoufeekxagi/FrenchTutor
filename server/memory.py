import sqlite3
import logging
import json
from datetime import datetime
from config import DB_PATH

logger = logging.getLogger(__name__)


def _get_conn() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    """Create database tables if they don't exist."""
    conn = _get_conn()
    try:
        conn.executescript("""
            CREATE TABLE IF NOT EXISTS sessions (
                id TEXT PRIMARY KEY,
                user_id TEXT NOT NULL,
                started_at TEXT NOT NULL,
                ended_at TEXT,
                summary TEXT,
                topic TEXT,
                vocabulary TEXT
            );

            CREATE TABLE IF NOT EXISTS messages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT NOT NULL,
                role TEXT NOT NULL,
                content TEXT NOT NULL,
                created_at TEXT NOT NULL,
                FOREIGN KEY (session_id) REFERENCES sessions(id)
            );

            CREATE INDEX IF NOT EXISTS idx_messages_session
                ON messages(session_id);
        """)
        conn.commit()
        logger.info("Database initialized")
    finally:
        conn.close()


def create_session(session_id: str, user_id: str = "default") -> str:
    """Create a new session record."""
    conn = _get_conn()
    try:
        conn.execute(
            "INSERT INTO sessions (id, user_id, started_at) VALUES (?, ?, ?)",
            (session_id, user_id, datetime.utcnow().isoformat()),
        )
        conn.commit()
        logger.info(f"Session created: {session_id}")
        return session_id
    finally:
        conn.close()


def save_message(session_id: str, role: str, content: str):
    """Save a message to the database."""
    conn = _get_conn()
    try:
        conn.execute(
            "INSERT INTO messages (session_id, role, content, created_at) VALUES (?, ?, ?, ?)",
            (session_id, role, content, datetime.utcnow().isoformat()),
        )
        conn.commit()
    finally:
        conn.close()


def get_history(session_id: str, limit: int = 20) -> list[dict]:
    """Get recent messages for a session."""
    conn = _get_conn()
    try:
        rows = conn.execute(
            "SELECT role, content FROM messages WHERE session_id = ? ORDER BY id DESC LIMIT ?",
            (session_id, limit),
        ).fetchall()
        return list(reversed([{"role": r["role"], "content": r["content"]} for r in rows]))
    finally:
        conn.close()


def end_session(session_id: str, summary: str, topic: str = "", vocabulary: list[str] = None):
    """Mark session as ended and store summary."""
    conn = _get_conn()
    try:
        conn.execute(
            "UPDATE sessions SET ended_at = ?, summary = ?, topic = ?, vocabulary = ? WHERE id = ?",
            (
                datetime.utcnow().isoformat(),
                summary,
                topic,
                json.dumps(vocabulary or []),
                session_id,
            ),
        )
        conn.commit()
        logger.info(f"Session ended: {session_id}")
    finally:
        conn.close()


def get_last_session_summary(user_id: str = "default") -> str:
    """Get the summary from the user's most recent completed session."""
    conn = _get_conn()
    try:
        row = conn.execute(
            "SELECT summary FROM sessions WHERE user_id = ? AND ended_at IS NOT NULL ORDER BY ended_at DESC LIMIT 1",
            (user_id,),
        ).fetchone()
        return row["summary"] if row else ""
    finally:
        conn.close()


def get_session_transcript(session_id: str) -> str:
    """Get full transcript text for a session (for summary generation)."""
    conn = _get_conn()
    try:
        rows = conn.execute(
            "SELECT role, content FROM messages WHERE session_id = ? ORDER BY id",
            (session_id,),
        ).fetchall()
        lines = []
        for r in rows:
            prefix = "User" if r["role"] == "user" else "Tutor"
            lines.append(f"{prefix}: {r['content']}")
        return "\n".join(lines)
    finally:
        conn.close()


def get_all_sessions(user_id: str = "default") -> list[dict]:
    """Get all sessions for a user."""
    conn = _get_conn()
    try:
        rows = conn.execute(
            "SELECT id, started_at, ended_at, summary, topic, vocabulary FROM sessions WHERE user_id = ? ORDER BY started_at DESC",
            (user_id,),
        ).fetchall()
        return [dict(r) for r in rows]
    finally:
        conn.close()
