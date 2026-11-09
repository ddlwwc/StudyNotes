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
            """
        )


def load_active_workspace() -> Optional[Path]:
    with connect() as connection:
        row = connection.execute(
            "SELECT value FROM app_state WHERE key = 'active_workspace_path'"
        ).fetchone()

    if row is None:
        return None

    workspace = Path(row["value"])
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
