from contextlib import asynccontextmanager
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from storage import initialize_database, load_active_workspace, save_active_workspace


active_workspace: Optional[Path] = None


@asynccontextmanager
async def lifespan(_: FastAPI):
    global active_workspace

    initialize_database()
    active_workspace = load_active_workspace()
    yield


app = FastAPI(title="StudyNotes API", lifespan=lifespan)


class OpenWorkspaceRequest(BaseModel):
    path: str


def workspace_tree(root: Path, current: Path) -> list[dict[str, object]]:
    nodes: list[dict[str, object]] = []

    for entry in sorted(
        current.iterdir(), key=lambda item: (not item.is_dir(), item.name.casefold())
    ):
        if entry.name.startswith("."):
            continue

        relative_path = entry.relative_to(root).as_posix()
        if entry.is_dir() and not entry.is_symlink():
            nodes.append(
                {
                    "name": entry.name,
                    "path": relative_path,
                    "type": "directory",
                    "children": workspace_tree(root, entry),
                }
            )
        elif entry.is_file() and entry.suffix.lower() == ".md":
            nodes.append(
                {
                    "name": entry.name,
                    "path": relative_path,
                    "type": "file",
                }
            )

    return nodes


def serialize_workspace(workspace: Path) -> dict[str, object]:
    return {
        "name": workspace.name or str(workspace),
        "path": str(workspace),
    }


def resolve_workspace_file(relative_path: str) -> Path:
    if active_workspace is None:
        raise HTTPException(status_code=404, detail="请先打开 Notebook workspace。")

    root = active_workspace.resolve()
    candidate = (root / relative_path).resolve()
    try:
        candidate.relative_to(root)
    except ValueError as error:
        raise HTTPException(status_code=400, detail="文件路径无效。") from error

    if not candidate.is_file() or candidate.suffix.lower() != ".md":
        raise HTTPException(status_code=404, detail="Markdown 页面不存在。")

    return candidate


@app.get("/api/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/api/workspace")
def workspace() -> dict[str, object]:
    if active_workspace is None:
        return {"workspace": None, "tree": []}

    return {
        "workspace": serialize_workspace(active_workspace),
        "tree": workspace_tree(active_workspace, active_workspace),
    }


@app.post("/api/workspace")
def open_workspace(request: OpenWorkspaceRequest) -> dict[str, object]:
    global active_workspace

    candidate = Path(request.path).expanduser().resolve()
    if not candidate.is_dir():
        raise HTTPException(status_code=400, detail="Notebook workspace 不存在。")

    save_active_workspace(candidate)
    active_workspace = candidate
    return {
        "workspace": serialize_workspace(candidate),
        "tree": workspace_tree(candidate, candidate),
    }


@app.get("/api/file")
def read_file(path: str) -> dict[str, str]:
    file_path = resolve_workspace_file(path)
    try:
        content = file_path.read_text(encoding="utf-8")
    except UnicodeDecodeError as error:
        raise HTTPException(
            status_code=422, detail="这个 Markdown 文件不是 UTF-8 编码。"
        ) from error

    return {
        "path": file_path.relative_to(active_workspace).as_posix(),
        "title": file_path.stem,
        "content": content,
    }
