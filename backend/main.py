from contextlib import asynccontextmanager
import hashlib
from pathlib import Path
from typing import Optional

import fitz
from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel

from storage import (
    initialize_database,
    list_source_citations,
    load_active_workspace,
    load_source_citation,
    save_active_workspace,
    save_source_citation,
)


active_workspace: Optional[Path] = None
PDF_EXTRACTOR_VERSION = "pymupdf-1.26.5"


@asynccontextmanager
async def lifespan(_: FastAPI):
    global active_workspace

    initialize_database()
    active_workspace = load_active_workspace()
    yield


app = FastAPI(title="StudyNotes API", lifespan=lifespan)


class OpenWorkspaceRequest(BaseModel):
    path: str


class CreateCitationRequest(BaseModel):
    path: str
    page: int
    quote: str


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
        elif entry.is_file() and entry.suffix.lower() in {".md", ".pdf"}:
            nodes.append(
                {
                    "name": entry.name,
                    "path": relative_path,
                    "type": "file",
                    "kind": "pdf" if entry.suffix.lower() == ".pdf" else "markdown",
                }
            )

    return nodes


def serialize_workspace(workspace: Path) -> dict[str, object]:
    return {
        "name": workspace.name or str(workspace),
        "path": str(workspace),
    }


def resolve_workspace_file(
    relative_path: str,
    allowed_suffixes: set[str],
) -> Path:
    if active_workspace is None:
        raise HTTPException(status_code=404, detail="请先打开 Notebook workspace。")

    root = active_workspace.resolve()
    candidate = (root / relative_path).resolve()
    try:
        candidate.relative_to(root)
    except ValueError as error:
        raise HTTPException(status_code=400, detail="文件路径无效。") from error

    if not candidate.is_file() or candidate.suffix.lower() not in allowed_suffixes:
        raise HTTPException(status_code=404, detail="资料文件不存在。")

    return candidate


def normalize_quote(value: str) -> str:
    return " ".join(value.split())


def open_pdf(file_path: Path) -> tuple[bytes, fitz.Document]:
    try:
        pdf_bytes = file_path.read_bytes()
        document = fitz.open(stream=pdf_bytes, filetype="pdf")
    except (OSError, RuntimeError, ValueError) as error:
        raise HTTPException(status_code=422, detail="无法读取这个 PDF 文件。") from error

    return pdf_bytes, document


def pdf_metadata(file_path: Path, relative_path: str) -> dict[str, object]:
    pdf_bytes, document = open_pdf(file_path)
    try:
        pages = []
        for index, page in enumerate(document):
            text = page.get_text("text", sort=True)
            pages.append(
                {
                    "page": index + 1,
                    "hasText": bool(text.strip()),
                }
            )

        return {
            "path": relative_path,
            "title": file_path.stem,
            "pageCount": document.page_count,
            "pages": pages,
            "pdfSha256": hashlib.sha256(pdf_bytes).hexdigest(),
            "extractorVersion": PDF_EXTRACTOR_VERSION,
        }
    finally:
        document.close()


def serialize_citation(citation: dict[str, object]) -> dict[str, object]:
    return {
        "id": citation["id"],
        "path": citation["path"],
        "page": citation["page"],
        "quote": citation["quote"],
        "pdfSha256": citation["pdf_sha256"],
        "extractorVersion": citation["extractor_version"],
        "createdAt": citation["created_at"],
    }


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
    file_path = resolve_workspace_file(path, {".md"})
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


@app.get("/api/pdf")
def pdf(path: str) -> dict[str, object]:
    file_path = resolve_workspace_file(path, {".pdf"})
    return pdf_metadata(file_path, path)


@app.get("/api/pdf/content")
def pdf_content(path: str) -> FileResponse:
    file_path = resolve_workspace_file(path, {".pdf"})
    return FileResponse(
        file_path,
        media_type="application/pdf",
        filename=file_path.name,
        headers={"Cache-Control": "no-store"},
    )


@app.get("/api/citations")
def citations(path: str) -> list[dict[str, object]]:
    if active_workspace is None:
        raise HTTPException(status_code=404, detail="请先打开 Notebook workspace。")

    resolve_workspace_file(path, {".pdf"})
    return [
        serialize_citation(citation)
        for citation in list_source_citations(active_workspace, path)
    ]


@app.post("/api/citations")
def create_citation(request: CreateCitationRequest) -> dict[str, object]:
    if active_workspace is None:
        raise HTTPException(status_code=404, detail="请先打开 Notebook workspace。")

    file_path = resolve_workspace_file(request.path, {".pdf"})
    quote = normalize_quote(request.quote)
    if not quote:
        raise HTTPException(status_code=422, detail="请先选择 PDF 文本。")

    pdf_bytes, document = open_pdf(file_path)
    try:
        if request.page < 1 or request.page > document.page_count:
            raise HTTPException(status_code=422, detail="引用页码超出 PDF 范围。")

        page_text = normalize_quote(
            document[request.page - 1].get_text("text", sort=True)
        )
        if not page_text or quote not in page_text:
            raise HTTPException(
                status_code=422,
                detail="选中的文本不属于当前 PDF 页面。",
            )
    finally:
        document.close()

    citation = save_source_citation(
        active_workspace,
        request.path,
        request.page,
        quote,
        hashlib.sha256(pdf_bytes).hexdigest(),
        PDF_EXTRACTOR_VERSION,
    )
    return serialize_citation(citation)


@app.post("/api/citations/{citation_id}/validate")
def validate_citation(citation_id: int) -> dict[str, object]:
    if active_workspace is None:
        raise HTTPException(status_code=404, detail="请先打开 Notebook workspace。")

    citation = load_source_citation(active_workspace, citation_id)
    if citation is None:
        raise HTTPException(status_code=404, detail="引用不存在。")

    relative_path = str(citation["path"])
    file_path = resolve_workspace_file(relative_path, {".pdf"})
    pdf_bytes, document = open_pdf(file_path)
    current_sha256 = hashlib.sha256(pdf_bytes).hexdigest()
    try:
        if current_sha256 != citation["pdf_sha256"]:
            status = "source_changed"
        elif int(citation["page"]) > document.page_count:
            status = "unresolved"
        else:
            quote = normalize_quote(str(citation["quote"]))
            page_text = normalize_quote(
                document[int(citation["page"]) - 1].get_text("text", sort=True)
            )
            if not page_text:
                status = "unsupported_no_text"
            elif quote in page_text:
                status = "resolved"
            elif any(
                quote in normalize_quote(page.get_text("text", sort=True))
                for page in document
            ):
                status = "moved"
            else:
                status = "unresolved"
    finally:
        document.close()

    return {
        "citation": serialize_citation(citation),
        "status": status,
    }
