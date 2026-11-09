import json
import os
import sqlite3
import uuid
from pathlib import Path
from typing import Optional


PROJECT_ROOT = Path(__file__).resolve().parents[1]


def database_path() -> Path:
    configured = os.environ.get("STUDY_NOTES_DATA_DIR")
    data_dir = (
        Path(configured).expanduser().resolve()
        if configured
        else PROJECT_ROOT / "data"
    )
    data_dir.mkdir(parents=True, exist_ok=True)
    return data_dir / "app.sqlite3"


def connect() -> sqlite3.Connection:
    connection = sqlite3.connect(database_path(), timeout=5)
    connection.row_factory = sqlite3.Row
    return connection


def initialize_database() -> None:
    with connect() as connection:
        connection.executescript(
            """
            CREATE TABLE IF NOT EXISTS workspaces (
                path TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            );

            CREATE TABLE IF NOT EXISTS app_state (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS document_drafts (
                workspace_path TEXT NOT NULL,
                path TEXT NOT NULL,
                markdown TEXT NOT NULL,
                blocks_json TEXT NOT NULL,
                base_revision TEXT NOT NULL,
                updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (workspace_path, path)
            );

            CREATE TABLE IF NOT EXISTS source_citations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                workspace_path TEXT NOT NULL,
                path TEXT NOT NULL,
                page INTEGER NOT NULL,
                quote TEXT NOT NULL,
                pdf_sha256 TEXT NOT NULL,
                extractor_version TEXT NOT NULL,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            );

            CREATE INDEX IF NOT EXISTS source_citations_workspace_path
            ON source_citations (workspace_path, path, created_at);

            CREATE TABLE IF NOT EXISTS search_sources (
                workspace_path TEXT NOT NULL,
                path TEXT NOT NULL,
                kind TEXT NOT NULL,
                source_hash TEXT NOT NULL,
                parser_version TEXT NOT NULL,
                indexed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                error TEXT,
                PRIMARY KEY (workspace_path, path)
            );

            CREATE VIRTUAL TABLE IF NOT EXISTS search_fts USING fts5(
                workspace_path UNINDEXED,
                path UNINDEXED,
                kind UNINDEXED,
                block_id UNINDEXED,
                block_index UNINDEXED,
                heading_path UNINDEXED,
                page UNINDEXED,
                title,
                path_search,
                tags,
                heading_search,
                body,
                tokenize = 'trigram case_sensitive 0'
            );

            CREATE TABLE IF NOT EXISTS learning_sessions (
                id TEXT PRIMARY KEY,
                workspace_path TEXT NOT NULL,
                path TEXT NOT NULL,
                block_id TEXT,
                quote TEXT NOT NULL,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            );

            CREATE INDEX IF NOT EXISTS learning_sessions_workspace
            ON learning_sessions (workspace_path, updated_at);

            CREATE TABLE IF NOT EXISTS session_messages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                workspace_path TEXT NOT NULL,
                session_id TEXT NOT NULL,
                role TEXT NOT NULL,
                content TEXT NOT NULL,
                answer_type TEXT,
                citations_json TEXT,
                context_json TEXT,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            );

            CREATE INDEX IF NOT EXISTS session_messages_session
            ON session_messages (workspace_path, session_id, id);
            """
        )


def load_saved_workspace_path() -> Optional[Path]:
    with connect() as connection:
        row = connection.execute(
            "SELECT value FROM app_state WHERE key = 'active_workspace_path'"
        ).fetchone()
    return Path(row["value"]) if row is not None else None


def load_active_workspace() -> Optional[Path]:
    workspace = load_saved_workspace_path()
    if workspace is None:
        return None
    return workspace if workspace.is_dir() else None


def save_active_workspace(workspace: Path) -> None:
    with connect() as connection:
        connection.execute(
            """
            INSERT INTO workspaces (path, name)
            VALUES (?, ?)
            ON CONFLICT(path) DO UPDATE SET
                name = excluded.name,
                updated_at = CURRENT_TIMESTAMP
            """,
            (str(workspace), workspace.name or str(workspace)),
        )
        connection.execute(
            """
            INSERT INTO app_state (key, value)
            VALUES ('active_workspace_path', ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
            """,
            (str(workspace),),
        )


def load_app_setting(key: str, default: str = "") -> str:
    with connect() as connection:
        row = connection.execute(
            "SELECT value FROM app_state WHERE key = ?",
            (key,),
        ).fetchone()
    return str(row["value"]) if row is not None else default


def save_app_setting(key: str, value: str) -> None:
    with connect() as connection:
        connection.execute(
            """
            INSERT INTO app_state (key, value)
            VALUES (?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
            """,
            (key, value),
        )


def create_learning_session(
    workspace: Path,
    relative_path: str,
    block_id: str,
    quote: str,
) -> dict[str, object]:
    session_id = str(uuid.uuid4())
    with connect() as connection:
        connection.execute(
            """
            INSERT INTO learning_sessions (
                id,
                workspace_path,
                path,
                block_id,
                quote
            )
            VALUES (?, ?, ?, ?, ?)
            """,
            (
                session_id,
                str(workspace.resolve()),
                relative_path,
                block_id,
                quote,
            ),
        )
        row = connection.execute(
            "SELECT * FROM learning_sessions WHERE id = ?",
            (session_id,),
        ).fetchone()
    if row is None:
        raise RuntimeError("Learning session was not persisted.")
    return dict(row)


def load_learning_session(
    workspace: Path,
    session_id: str,
) -> Optional[dict[str, object]]:
    with connect() as connection:
        row = connection.execute(
            """
            SELECT *
            FROM learning_sessions
            WHERE workspace_path = ? AND id = ?
            """,
            (str(workspace.resolve()), session_id),
        ).fetchone()
    return dict(row) if row is not None else None


def save_session_message(
    workspace: Path,
    session_id: str,
    role: str,
    content: str,
    *,
    answer_type: Optional[str] = None,
    citations: object = None,
    context: object = None,
) -> dict[str, object]:
    citations_json = (
        json.dumps(citations, ensure_ascii=False)
        if citations is not None
        else None
    )
    context_json = (
        json.dumps(context, ensure_ascii=False)
        if context is not None
        else None
    )
    with connect() as connection:
        cursor = connection.execute(
            """
            INSERT INTO session_messages (
                workspace_path,
                session_id,
                role,
                content,
                answer_type,
                citations_json,
                context_json
            )
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                str(workspace.resolve()),
                session_id,
                role,
                content,
                answer_type,
                citations_json,
                context_json,
            ),
        )
        connection.execute(
            """
            UPDATE learning_sessions
            SET updated_at = CURRENT_TIMESTAMP
            WHERE workspace_path = ? AND id = ?
            """,
            (str(workspace.resolve()), session_id),
        )
        row = connection.execute(
            "SELECT * FROM session_messages WHERE id = ?",
            (cursor.lastrowid,),
        ).fetchone()
    if row is None:
        raise RuntimeError("Session message was not persisted.")
    return dict(row)


def save_document_draft(
    workspace: Path,
    relative_path: str,
    markdown: str,
    blocks_json: str,
    base_revision: str,
) -> dict[str, object]:
    with connect() as connection:
        connection.execute(
            """
            INSERT INTO document_drafts (
                workspace_path,
                path,
                markdown,
                blocks_json,
                base_revision
            )
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(workspace_path, path) DO UPDATE SET
                markdown = excluded.markdown,
                blocks_json = excluded.blocks_json,
                base_revision = excluded.base_revision,
                updated_at = CURRENT_TIMESTAMP
            """,
            (
                str(workspace.resolve()),
                relative_path,
                markdown,
                blocks_json,
                base_revision,
            ),
        )
        row = connection.execute(
            """
            SELECT *
            FROM document_drafts
            WHERE workspace_path = ? AND path = ?
            """,
            (str(workspace.resolve()), relative_path),
        ).fetchone()

    if row is None:
        raise RuntimeError("Document draft was not persisted.")
    return dict(row)


def load_document_draft(
    workspace: Path,
    relative_path: str,
) -> Optional[dict[str, object]]:
    with connect() as connection:
        row = connection.execute(
            """
            SELECT *
            FROM document_drafts
            WHERE workspace_path = ? AND path = ?
            """,
            (str(workspace.resolve()), relative_path),
        ).fetchone()
    return dict(row) if row is not None else None


def delete_document_draft(workspace: Path, relative_path: str) -> None:
    with connect() as connection:
        connection.execute(
            """
            DELETE FROM document_drafts
            WHERE workspace_path = ? AND path = ?
            """,
            (str(workspace.resolve()), relative_path),
        )


def move_document_draft(
    workspace: Path,
    old_path: str,
    new_path: str,
) -> None:
    with connect() as connection:
        connection.execute(
            """
            UPDATE document_drafts
            SET path = ?
            WHERE workspace_path = ? AND path = ?
            """,
            (new_path, str(workspace.resolve()), old_path),
        )


def save_source_citation(
    workspace: Path,
    relative_path: str,
    page: int,
    quote: str,
    pdf_sha256: str,
    extractor_version: str,
) -> dict[str, object]:
    with connect() as connection:
        cursor = connection.execute(
            """
            INSERT INTO source_citations (
                workspace_path,
                path,
                page,
                quote,
                pdf_sha256,
                extractor_version
            )
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (
                str(workspace.resolve()),
                relative_path,
                page,
                quote,
                pdf_sha256,
                extractor_version,
            ),
        )
        row = connection.execute(
            "SELECT * FROM source_citations WHERE id = ?",
            (cursor.lastrowid,),
        ).fetchone()

    if row is None:
        raise RuntimeError("Citation was not persisted.")
    return dict(row)


def list_source_citations(
    workspace: Path,
    relative_path: str,
) -> list[dict[str, object]]:
    with connect() as connection:
        rows = connection.execute(
            """
            SELECT *
            FROM source_citations
            WHERE workspace_path = ? AND path = ?
            ORDER BY created_at ASC, id ASC
            """,
            (str(workspace.resolve()), relative_path),
        ).fetchall()
    return [dict(row) for row in rows]


def load_source_citation(
    workspace: Path,
    citation_id: int,
) -> Optional[dict[str, object]]:
    with connect() as connection:
        row = connection.execute(
            """
            SELECT *
            FROM source_citations
            WHERE workspace_path = ? AND id = ?
            """,
            (str(workspace.resolve()), citation_id),
        ).fetchone()
    return dict(row) if row is not None else None
