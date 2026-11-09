import os
import sqlite3
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
            """
        )


def load_saved_workspace_path() -> Optional[Path]:
    with connect() as connection:
        row = connection.execute(
            "SELECT value FROM app_state WHERE key = 'active_workspace_path'"
        ).fetchone()

    if row is None:
        return None

    return Path(row["value"])


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
