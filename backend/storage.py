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
