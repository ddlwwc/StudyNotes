from __future__ import annotations

import json
import os
import sqlite3
import uuid
from pathlib import Path
from typing import Optional


PROJECT_ROOT = Path(__file__).resolve().parents[1]


def application_data_directory() -> Path:
    configured = os.environ.get("STUDY_NOTES_DATA_DIR")
    data_dir = (
        Path(configured).expanduser().resolve()
        if configured
        else PROJECT_ROOT / "data"
    )
    data_dir.mkdir(parents=True, exist_ok=True)
    return data_dir


def database_path() -> Path:
    data_dir = application_data_directory()
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

            CREATE TABLE IF NOT EXISTS qiniu_settings (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                bucket TEXT NOT NULL,
                domain TEXT NOT NULL,
                updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            );

            CREATE TABLE IF NOT EXISTS uploaded_images (
                workspace_path TEXT NOT NULL,
                object_key TEXT NOT NULL,
                url TEXT NOT NULL,
                mime_type TEXT NOT NULL,
                size INTEGER NOT NULL,
                cached_path TEXT,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (workspace_path, url)
            );

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

            CREATE TABLE IF NOT EXISTS embedding_entries (
                workspace_path TEXT NOT NULL,
                entry_key TEXT NOT NULL,
                path TEXT NOT NULL,
                kind TEXT NOT NULL,
                block_id TEXT,
                block_index INTEGER,
                heading_path TEXT NOT NULL,
                page INTEGER,
                title TEXT NOT NULL,
                tags TEXT NOT NULL,
                body TEXT NOT NULL,
                content_hash TEXT NOT NULL,
                embedding_model TEXT NOT NULL,
                embedding_json TEXT NOT NULL,
                indexed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (workspace_path, entry_key)
            );

            CREATE INDEX IF NOT EXISTS embedding_entries_workspace_model
            ON embedding_entries (workspace_path, embedding_model, path);

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
                page INTEGER,
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

            CREATE TABLE IF NOT EXISTS learning_session_sources (
                id TEXT PRIMARY KEY,
                workspace_path TEXT NOT NULL,
                session_id TEXT NOT NULL,
                kind TEXT NOT NULL,
                path TEXT NOT NULL,
                block_id TEXT,
                block_index INTEGER,
                page INTEGER,
                heading_path_json TEXT NOT NULL DEFAULT '[]',
                quote TEXT NOT NULL DEFAULT '',
                source_key TEXT NOT NULL,
                is_initial INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                UNIQUE(workspace_path, session_id, source_key)
            );

            CREATE INDEX IF NOT EXISTS learning_session_sources_session
            ON learning_session_sources (workspace_path, session_id, created_at, id);

            CREATE TABLE IF NOT EXISTS practice_sets (
                id TEXT PRIMARY KEY,
                workspace_path TEXT NOT NULL,
                session_id TEXT NOT NULL,
                question_count INTEGER NOT NULL,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            );

            CREATE INDEX IF NOT EXISTS practice_sets_session
            ON practice_sets (workspace_path, session_id, created_at);

            CREATE TABLE IF NOT EXISTS practice_items (
                id TEXT PRIMARY KEY,
                practice_set_id TEXT NOT NULL,
                workspace_path TEXT NOT NULL,
                session_id TEXT NOT NULL,
                ordinal INTEGER NOT NULL,
                stem TEXT NOT NULL,
                options_json TEXT NOT NULL,
                correct_index INTEGER NOT NULL,
                explanation TEXT NOT NULL,
                citation_json TEXT NOT NULL,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                UNIQUE (practice_set_id, ordinal)
            );

            CREATE INDEX IF NOT EXISTS practice_items_session
            ON practice_items (workspace_path, session_id, practice_set_id, ordinal);

            CREATE TABLE IF NOT EXISTS practice_attempts (
                id TEXT PRIMARY KEY,
                workspace_path TEXT NOT NULL,
                session_id TEXT NOT NULL,
                practice_set_id TEXT NOT NULL,
                practice_item_id TEXT NOT NULL,
                selected_index INTEGER NOT NULL,
                correct INTEGER NOT NULL,
                answered_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                UNIQUE (workspace_path, practice_item_id)
            );

            CREATE INDEX IF NOT EXISTS practice_attempts_session
            ON practice_attempts (workspace_path, session_id, practice_set_id);
            """
        )
        columns = {
            row["name"]
            for row in connection.execute("PRAGMA table_info(learning_sessions)")
        }
        if "page" not in columns:
            connection.execute(
                "ALTER TABLE learning_sessions ADD COLUMN page INTEGER"
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
    block_id: Optional[str],
    quote: str,
    page: Optional[int] = None,
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
                page,
                quote
            )
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (
                session_id,
                str(workspace.resolve()),
                relative_path,
                block_id,
                page,
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


def save_learning_session_source(
    workspace: Path,
    session_id: str,
    source: dict[str, object],
    *,
    is_initial: bool = False,
) -> tuple[dict[str, object], bool]:
    workspace_path = str(workspace.resolve())
    source_key = str(source["sourceKey"])
    with connect() as connection:
        existing = connection.execute(
            """
            SELECT *
            FROM learning_session_sources
            WHERE workspace_path = ? AND session_id = ? AND source_key = ?
            """,
            (workspace_path, session_id, source_key),
        ).fetchone()
        if existing is not None:
            return dict(existing), True

        source_id = str(uuid.uuid4())
        connection.execute(
            """
            INSERT INTO learning_session_sources (
                id,
                workspace_path,
                session_id,
                kind,
                path,
                block_id,
                block_index,
                page,
                heading_path_json,
                quote,
                source_key,
                is_initial
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                source_id,
                workspace_path,
                session_id,
                source["kind"],
                source["path"],
                source.get("blockId"),
                source.get("blockIndex"),
                source.get("page"),
                json.dumps(source.get("headingPath", []), ensure_ascii=False),
                source.get("quote", ""),
                source_key,
                1 if is_initial else 0,
            ),
        )
        row = connection.execute(
            "SELECT * FROM learning_session_sources WHERE id = ?",
            (source_id,),
        ).fetchone()
    if row is None:
        raise RuntimeError("Learning source was not persisted.")
    return dict(row), False


def list_learning_session_sources(
    workspace: Path,
    session_id: str,
) -> list[dict[str, object]]:
    with connect() as connection:
        rows = connection.execute(
            """
            SELECT *
            FROM learning_session_sources
            WHERE workspace_path = ? AND session_id = ?
            ORDER BY is_initial DESC, created_at ASC, id ASC
            """,
            (str(workspace.resolve()), session_id),
        ).fetchall()
    return [dict(row) for row in rows]


def delete_learning_session_source(
    workspace: Path,
    session_id: str,
    source_id: str,
) -> bool:
    with connect() as connection:
        row = connection.execute(
            """
            SELECT is_initial
            FROM learning_session_sources
            WHERE workspace_path = ? AND session_id = ? AND id = ?
            """,
            (str(workspace.resolve()), session_id, source_id),
        ).fetchone()
        if row is None:
            return False
        if bool(row["is_initial"]):
            raise ValueError("会话起点不可移除。")
        connection.execute(
            """
            DELETE FROM learning_session_sources
            WHERE workspace_path = ? AND session_id = ? AND id = ?
            """,
            (str(workspace.resolve()), session_id, source_id),
        )
    return True


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


def list_session_messages(
    workspace: Path,
    session_id: str,
    *,
    limit: int = 8,
) -> list[dict[str, object]]:
    with connect() as connection:
        rows = connection.execute(
            """
            SELECT *
            FROM (
                SELECT *
                FROM session_messages
                WHERE workspace_path = ? AND session_id = ?
                ORDER BY id DESC
                LIMIT ?
            )
            ORDER BY id ASC
            """,
            (str(workspace.resolve()), session_id, limit),
        ).fetchall()
    return [dict(row) for row in rows]


def save_practice_set(
    workspace: Path,
    session_id: str,
    questions: list[dict[str, object]],
) -> dict[str, object]:
    practice_set_id = str(uuid.uuid4())
    workspace_path = str(workspace.resolve())
    with connect() as connection:
        connection.execute(
            """
            INSERT INTO practice_sets (
                id,
                workspace_path,
                session_id,
                question_count
            )
            VALUES (?, ?, ?, ?)
            """,
            (practice_set_id, workspace_path, session_id, len(questions)),
        )
        for ordinal, question in enumerate(questions, start=1):
            item_id = str(uuid.uuid4())
            connection.execute(
                """
                INSERT INTO practice_items (
                    id,
                    practice_set_id,
                    workspace_path,
                    session_id,
                    ordinal,
                    stem,
                    options_json,
                    correct_index,
                    explanation,
                    citation_json
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    item_id,
                    practice_set_id,
                    workspace_path,
                    session_id,
                    ordinal,
                    str(question["stem"]),
                    json.dumps(question["options"], ensure_ascii=False),
                    int(question["correctIndex"]),
                    str(question["explanation"]),
                    json.dumps(question["citation"], ensure_ascii=False),
                ),
            )
        connection.execute(
            """
            UPDATE learning_sessions
            SET updated_at = CURRENT_TIMESTAMP
            WHERE workspace_path = ? AND id = ?
            """,
            (workspace_path, session_id),
        )

    loaded = load_practice_set(workspace, session_id)
    if loaded is None or loaded["practice"]["id"] != practice_set_id:
        raise RuntimeError("Practice set was not persisted.")
    return loaded


def load_practice_set(
    workspace: Path,
    session_id: str,
) -> Optional[dict[str, object]]:
    workspace_path = str(workspace.resolve())
    with connect() as connection:
        practice = connection.execute(
            """
            SELECT *
            FROM practice_sets
            WHERE workspace_path = ? AND session_id = ?
            ORDER BY created_at DESC, rowid DESC
            LIMIT 1
            """,
            (workspace_path, session_id),
        ).fetchone()
        if practice is None:
            return None
        items = connection.execute(
            """
            SELECT *
            FROM practice_items
            WHERE workspace_path = ?
              AND session_id = ?
              AND practice_set_id = ?
            ORDER BY ordinal ASC
            """,
            (workspace_path, session_id, practice["id"]),
        ).fetchall()
    return {"practice": dict(practice), "items": [dict(row) for row in items]}


def list_practice_attempts(
    workspace: Path,
    session_id: str,
    practice_set_id: str,
) -> list[dict[str, object]]:
    with connect() as connection:
        rows = connection.execute(
            """
            SELECT *
            FROM practice_attempts
            WHERE workspace_path = ?
              AND session_id = ?
              AND practice_set_id = ?
            ORDER BY answered_at ASC, rowid ASC
            """,
            (str(workspace.resolve()), session_id, practice_set_id),
        ).fetchall()
    return [dict(row) for row in rows]


def save_practice_attempt(
    workspace: Path,
    session_id: str,
    item_id: str,
    selected_index: int,
) -> Optional[dict[str, object]]:
    workspace_path = str(workspace.resolve())
    with connect() as connection:
        item = connection.execute(
            """
            SELECT *
            FROM practice_items
            WHERE id = ?
              AND workspace_path = ?
              AND session_id = ?
            """,
            (item_id, workspace_path, session_id),
        ).fetchone()
        if item is None:
            return None
        try:
            options = json.loads(str(item["options_json"]))
        except json.JSONDecodeError as error:
            raise ValueError("Practice item options are invalid.") from error
        if (
            not isinstance(options, list)
            or selected_index < 0
            or selected_index >= len(options)
        ):
            raise ValueError("请选择有效答案。")

        attempt_id = str(uuid.uuid4())
        correct = int(selected_index == int(item["correct_index"]))
        connection.execute(
            """
            INSERT INTO practice_attempts (
                id,
                workspace_path,
                session_id,
                practice_set_id,
                practice_item_id,
                selected_index,
                correct
            )
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(workspace_path, practice_item_id) DO UPDATE SET
                selected_index = excluded.selected_index,
                correct = excluded.correct,
                answered_at = CURRENT_TIMESTAMP
            """,
            (
                attempt_id,
                workspace_path,
                session_id,
                str(item["practice_set_id"]),
                item_id,
                selected_index,
                correct,
            ),
        )
        connection.execute(
            """
            UPDATE learning_sessions
            SET updated_at = CURRENT_TIMESTAMP
            WHERE workspace_path = ? AND id = ?
            """,
            (workspace_path, session_id),
        )
        row = connection.execute(
            """
            SELECT *
            FROM practice_attempts
            WHERE workspace_path = ? AND practice_item_id = ?
            """,
            (workspace_path, item_id),
        ).fetchone()
    if row is None:
        raise RuntimeError("Practice attempt was not persisted.")
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


def load_qiniu_settings() -> Optional[dict[str, object]]:
    with connect() as connection:
        row = connection.execute(
            "SELECT * FROM qiniu_settings WHERE id = 1"
        ).fetchone()
    return dict(row) if row is not None else None


def save_qiniu_settings(bucket: str, domain: str) -> dict[str, object]:
    with connect() as connection:
        connection.execute(
            """
            INSERT INTO qiniu_settings (id, bucket, domain)
            VALUES (1, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                bucket = excluded.bucket,
                domain = excluded.domain,
                updated_at = CURRENT_TIMESTAMP
            """,
            (bucket, domain),
        )
        row = connection.execute(
            "SELECT * FROM qiniu_settings WHERE id = 1"
        ).fetchone()

    if row is None:
        raise RuntimeError("Qiniu settings were not persisted.")
    return dict(row)


def save_uploaded_image(
    workspace: Path,
    object_key: str,
    url: str,
    mime_type: str,
    size: int,
    cached_path: str | None,
) -> dict[str, object]:
    with connect() as connection:
        connection.execute(
            """
            INSERT INTO uploaded_images (
                workspace_path,
                object_key,
                url,
                mime_type,
                size,
                cached_path
            )
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(workspace_path, url) DO UPDATE SET
                object_key = excluded.object_key,
                mime_type = excluded.mime_type,
                size = excluded.size,
                cached_path = excluded.cached_path
            """,
            (
                str(workspace.resolve()),
                object_key,
                url,
                mime_type,
                size,
                cached_path,
            ),
        )
        row = connection.execute(
            """
            SELECT *
            FROM uploaded_images
            WHERE workspace_path = ? AND url = ?
            """,
            (str(workspace.resolve()), url),
        ).fetchone()

    if row is None:
        raise RuntimeError("Uploaded image was not persisted.")
    return dict(row)
