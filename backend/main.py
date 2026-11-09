from contextlib import asynccontextmanager
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from storage import (
    initialize_database,
    load_active_workspace,
    load_saved_workspace_path,
    save_active_workspace,
)


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


class CreatePageRequest(BaseModel):
    directory: str = ""
    name: str


class MoveEntryRequest(BaseModel):
    path: str
    new_path: str


def require_active_workspace() -> Path:
    if active_workspace is None:
        raise HTTPException(status_code=404, detail="请先打开 Notebook workspace。")
    if not active_workspace.is_dir():
        raise HTTPException(
            status_code=410, detail="Notebook workspace 已移动或不可用。"
        )
    return active_workspace.resolve()


def resolve_workspace_directory(relative_path: str) -> Path:
    root = require_active_workspace()
    candidate = (root / relative_path).resolve()
    try:
        candidate.relative_to(root)
    except ValueError as error:
        raise HTTPException(status_code=400, detail="目录路径无效。") from error

    if not candidate.is_dir():
        raise HTTPException(status_code=404, detail="目标目录不存在。")
    return candidate


def resolve_workspace_entry(relative_path: str) -> Path:
    root = require_active_workspace()
    candidate = (root / relative_path).resolve()
    try:
        relative = candidate.relative_to(root)
    except ValueError as error:
        raise HTTPException(status_code=400, detail="文件路径无效。") from error

    if not relative.parts or not candidate.exists():
        raise HTTPException(status_code=404, detail="页面或目录不存在。")
    if candidate.is_dir() and not candidate.is_symlink():
        return candidate
    if candidate.is_file() and candidate.suffix.lower() == ".md":
        return candidate
    raise HTTPException(status_code=400, detail="只支持管理 Markdown 页面或目录。")


def resolve_workspace_destination(relative_path: str) -> Path:
    root = require_active_workspace()
    destination = (root / relative_path).resolve()
    try:
        destination.relative_to(root)
    except ValueError as error:
        raise HTTPException(status_code=400, detail="目标路径无效。") from error

    if destination == root:
        raise HTTPException(status_code=400, detail="不能替换 workspace 根目录。")
    if destination.exists():
        raise HTTPException(status_code=409, detail="目标路径已经存在。")
    return destination


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


def serialize_stale_workspace(workspace: Path) -> dict[str, str]:
    return {"path": str(workspace)}


def resolve_workspace_file(relative_path: str) -> Path:
    root = require_active_workspace()
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
    saved_workspace = load_saved_workspace_path()
    if active_workspace is None:
        return {
            "staleWorkspace": (
                serialize_stale_workspace(saved_workspace)
                if saved_workspace is not None and not saved_workspace.is_dir()
                else None
            ),
            "tree": [],
            "workspace": None,
        }
    if not active_workspace.is_dir():
        return {
            "staleWorkspace": serialize_stale_workspace(active_workspace),
            "tree": [],
            "workspace": None,
        }

    return {
        "staleWorkspace": None,
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
        "staleWorkspace": None,
        "workspace": serialize_workspace(candidate),
        "tree": workspace_tree(candidate, candidate),
    }


@app.post("/api/pages")
def create_page(request: CreatePageRequest) -> dict[str, object]:
    directory = resolve_workspace_directory(request.directory)
    name = request.name.strip()
    if not name or "/" in name or "\\" in name:
        raise HTTPException(status_code=400, detail="页面名称无效。")
    if Path(name).suffix.lower() != ".md":
        name = f"{name}.md"

    page_path = directory / name
    try:
        with page_path.open("x", encoding="utf-8") as page:
            page.write(f"# {page_path.stem}\n\n")
    except FileExistsError as error:
        raise HTTPException(status_code=409, detail="同名页面已经存在。") from error

    root = require_active_workspace()
    return {
        "path": page_path.relative_to(root).as_posix(),
        "tree": workspace_tree(root, root),
    }


@app.patch("/api/entries")
def move_entry(request: MoveEntryRequest) -> dict[str, object]:
    root = require_active_workspace()
    source = resolve_workspace_entry(request.path)
    destination = resolve_workspace_destination(request.new_path)

    if source.is_dir():
        try:
            destination.relative_to(source)
        except ValueError:
            pass
        else:
            raise HTTPException(status_code=400, detail="目录不能移动到自身内部。")
    elif destination.suffix.lower() != ".md":
        raise HTTPException(status_code=400, detail="Markdown 页面必须保留 .md 后缀。")

    if not destination.parent.is_dir():
        raise HTTPException(status_code=400, detail="目标目录不存在。")

    source.rename(destination)
    return {
        "newPath": destination.relative_to(root).as_posix(),
        "oldPath": source.relative_to(root).as_posix(),
        "tree": workspace_tree(root, root),
    }


@app.delete("/api/entries")
def delete_entry(path: str) -> dict[str, object]:
    root = require_active_workspace()
    source = resolve_workspace_entry(path)
    deleted_path = source.relative_to(root).as_posix()

    if source.is_dir():
        raise HTTPException(status_code=400, detail="只能删除 Markdown 页面。")
    source.unlink()

    return {
        "deletedPath": deleted_path,
        "tree": workspace_tree(root, root),
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
