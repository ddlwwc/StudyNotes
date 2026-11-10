from __future__ import annotations

from contextlib import asynccontextmanager
import hashlib
import json
import mimetypes
import posixpath
from pathlib import Path
from typing import Optional
from urllib.parse import unquote, urlsplit

import fitz
from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.responses import FileResponse, StreamingResponse
from pydantic import BaseModel, Field

from credentials import (
    ACCESS_KEY_ACCOUNT,
    SECRET_KEY_ACCOUNT,
    credential_store,
    save_qiniu_credentials,
)
from documents import (
    DocumentConflictError,
    load_document,
    save_document,
    sidecar_path_for,
)
from model_client import (
    EmbeddingConfig,
    ModelConfig,
    ModelRequestError,
    test_embedding_connection,
    test_model_connection,
)
from practice import (
    PracticeGenerationError,
    generate_practice,
    serialize_practice,
)
from qiniu_images import MAX_IMAGE_BYTES, QiniuError, delete_image, upload_image
from search_index import rebuild_workspace_index, search_workspace
from secret_store import has_api_key, load_api_key, save_api_key
from storage import (
    create_learning_session,
    delete_learning_session_source,
    delete_document_draft,
    initialize_database,
    list_learning_session_sources,
    load_learning_session,
    list_source_citations,
    load_app_setting,
    load_active_workspace,
    load_document_draft,
    load_practice_set,
    load_qiniu_settings,
    load_source_citation,
    load_saved_workspace_path,
    list_practice_attempts,
    move_document_draft,
    save_practice_attempt,
    save_active_workspace,
    save_app_setting,
    save_document_draft,
    save_learning_session_source,
    save_qiniu_settings,
    save_source_citation,
)
from tutor import (
    TutorContextError,
    bind_tutor_selection,
    event_stream,
    resolve_tutor_source,
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


class ModelSettingsRequest(BaseModel):
    base_url: str = ""
    model: str = ""
    api_key: str = ""
    embedding_model: str = ""
    embedding_enabled: bool = False


class CreateTutorSessionRequest(BaseModel):
    path: str
    block_id: Optional[str] = None
    page: Optional[int] = None
    quote: str


class AddTutorSourceRequest(BaseModel):
    path: str
    block_id: Optional[str] = None
    page: Optional[int] = None
    quote: str = ""


class CreateTutorTurnRequest(BaseModel):
    question: str
    mode: str = "guided"
    supplement_requested: bool = False


class CreatePracticeRequest(BaseModel):
    question_count: int = Field(default=3, ge=1, le=10)


class CreatePracticeAttemptRequest(BaseModel):
    practice_item_id: str
    selected_index: int = Field(ge=0)


class CreateCitationRequest(BaseModel):
    path: str
    page: int
    quote: str


class CreatePageRequest(BaseModel):
    directory: str = ""
    name: str


class MoveEntryRequest(BaseModel):
    path: str
    new_path: str


class SaveDocumentRequest(BaseModel):
    path: str
    content: str
    blocks: list[dict[str, object]]
    expected_revision: str


class SaveDraftRequest(BaseModel):
    path: str
    content: str
    blocks: list[dict[str, object]]
    base_revision: str


class QiniuSettingsRequest(BaseModel):
    bucket: str
    domain: str
    access_key: Optional[str] = None
    secret_key: Optional[str] = None


class DeleteImageRequest(BaseModel):
    url: str


class LocalImageRequest(BaseModel):
    path: str
    src: str


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


def serialize_stale_workspace(workspace: Path) -> dict[str, str]:
    return {"path": str(workspace)}


def resolve_workspace_file(
    relative_path: str,
    allowed_suffixes: set[str],
) -> Path:
    root = require_active_workspace()
    candidate = (root / relative_path).resolve()
    try:
        candidate.relative_to(root)
    except ValueError as error:
        raise HTTPException(status_code=400, detail="文件路径无效。") from error

    if not candidate.is_file() or candidate.suffix.lower() not in allowed_suffixes:
        raise HTTPException(status_code=404, detail="资料文件不存在。")

    return candidate


def serialize_document(file_path: Path) -> dict[str, object]:
    relative_path = file_path.relative_to(require_active_workspace()).as_posix()
    try:
        document = load_document(file_path)
    except (OSError, ValueError) as error:
        raise HTTPException(status_code=422, detail=str(error)) from error

    draft = load_document_draft(require_active_workspace(), relative_path)
    serialized_draft = None
    if draft is not None:
        try:
            draft_blocks = json.loads(str(draft["blocks_json"]))
        except json.JSONDecodeError:
            draft_blocks = []
        serialized_draft = {
            "content": draft["markdown"],
            "blocks": draft_blocks,
            "baseRevision": draft["base_revision"],
            "updatedAt": draft["updated_at"],
        }

    return {
        "path": relative_path,
        "title": file_path.stem,
        **document,
        "draft": serialized_draft,
    }


def conflict_payload(file_path: Path) -> dict[str, object]:
    return {
        "message": "Markdown 文件已在外部修改，当前草稿没有覆盖磁盘。",
        "current": serialize_document(file_path),
    }


def normalize_quote(value: str) -> str:
    return " ".join(value.split())


def serialize_model_settings() -> dict[str, object]:
    base_url = load_app_setting("model_base_url")
    model = load_app_setting("model_name")
    embedding_model = load_app_setting("embedding_model")
    embedding_enabled = load_app_setting("embedding_enabled") == "true"
    api_key_available = has_api_key()
    return {
        "baseUrl": base_url,
        "model": model,
        "hasApiKey": api_key_available,
        "configured": bool(base_url and model and api_key_available),
        "embeddingModel": embedding_model,
        "embeddingEnabled": embedding_enabled,
        "embeddingConfigured": bool(
            embedding_enabled
            and embedding_model
            and base_url
            and api_key_available
        ),
    }


def model_config_from_request(request: ModelSettingsRequest) -> ModelConfig:
    base_url = request.base_url.strip()
    model = request.model.strip()
    api_key = request.api_key.strip() or load_api_key()
    if not base_url:
        raise HTTPException(status_code=422, detail="请填写 Base URL。")
    if not base_url.startswith(("http://", "https://")):
        raise HTTPException(status_code=422, detail="Base URL 必须使用 HTTP 或 HTTPS。")
    if not model:
        raise HTTPException(status_code=422, detail="请填写聊天模型。")
    if not api_key:
        raise HTTPException(status_code=422, detail="请填写 API Key。")
    return ModelConfig(base_url=base_url, api_key=api_key, model=model)


def embedding_config_from_request(
    request: ModelSettingsRequest,
) -> EmbeddingConfig:
    base_url = request.base_url.strip()
    model = request.embedding_model.strip()
    api_key = request.api_key.strip() or load_api_key()
    if not base_url:
        raise HTTPException(status_code=422, detail="请填写 Base URL。")
    if not base_url.startswith(("http://", "https://")):
        raise HTTPException(status_code=422, detail="Base URL 必须使用 HTTP 或 HTTPS。")
    if not model:
        raise HTTPException(status_code=422, detail="请填写 Embedding 模型。")
    if not api_key:
        raise HTTPException(status_code=422, detail="请填写 API Key。")
    return EmbeddingConfig(base_url=base_url, api_key=api_key, model=model)


def configured_model() -> ModelConfig:
    base_url = load_app_setting("model_base_url")
    model = load_app_setting("model_name")
    api_key = load_api_key()
    if not base_url or not model or not api_key:
        raise HTTPException(status_code=409, detail="请先配置模型服务。")
    return ModelConfig(base_url=base_url, api_key=api_key, model=model)


def configured_embedding() -> Optional[EmbeddingConfig]:
    if load_app_setting("embedding_enabled") != "true":
        return None
    base_url = load_app_setting("model_base_url")
    model = load_app_setting("embedding_model")
    api_key = load_api_key()
    if not base_url or not model or not api_key:
        return None
    return EmbeddingConfig(base_url=base_url, api_key=api_key, model=model)


def normalize_qiniu_domain(value: str) -> str:
    parsed = urlsplit(value.strip())
    if (
        parsed.scheme != "https"
        or not parsed.hostname
        or parsed.username
        or parsed.password
        or parsed.query
        or parsed.fragment
        or parsed.path not in {"", "/"}
    ):
        raise HTTPException(
            status_code=422,
            detail="七牛访问域名必须是 HTTPS 域名，且不能包含路径或参数。",
        )
    return f"https://{parsed.netloc.lower()}"


def normalize_qiniu_bucket(value: str) -> str:
    bucket = value.strip().lower()
    if (
        len(bucket) < 3
        or len(bucket) > 63
        or not bucket[0].isalnum()
        or not bucket[-1].isalnum()
        or any(character not in "abcdefghijklmnopqrstuvwxyz0123456789-"
               for character in bucket)
    ):
        raise HTTPException(status_code=422, detail="七牛桶名称无效。")
    return bucket


def serialize_qiniu_settings() -> dict[str, object]:
    settings = load_qiniu_settings()
    store = credential_store()
    access_key = store.get(ACCESS_KEY_ACCOUNT)
    secret_key = store.get(SECRET_KEY_ACCOUNT)
    return {
        "bucket": settings["bucket"] if settings else "",
        "configured": bool(
            settings and access_key is not None and secret_key is not None
        ),
        "domain": settings["domain"] if settings else "",
        "hasAccessKey": access_key is not None,
        "hasSecretKey": secret_key is not None,
    }


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


def serialize_tutor_source(source: dict[str, object]) -> dict[str, object]:
    try:
        heading_path = json.loads(str(source.get("heading_path_json", "[]")))
    except json.JSONDecodeError:
        heading_path = []
    return {
        "id": source["id"],
        "kind": source["kind"],
        "path": source["path"],
        "blockId": source.get("block_id"),
        "blockIndex": source.get("block_index"),
        "page": source.get("page"),
        "headingPath": heading_path if isinstance(heading_path, list) else [],
        "quote": source.get("quote", ""),
        "isInitial": bool(source.get("is_initial")),
        "createdAt": source.get("created_at"),
    }


@app.get("/api/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/api/model-settings")
def model_settings() -> dict[str, object]:
    return serialize_model_settings()


@app.put("/api/model-settings")
def update_model_settings(request: ModelSettingsRequest) -> dict[str, object]:
    config = model_config_from_request(request)
    embedding_model = request.embedding_model.strip()
    if request.embedding_enabled and not embedding_model:
        raise HTTPException(
            status_code=422,
            detail="启用语义检索前请填写 Embedding 模型。",
        )
    try:
        if request.api_key.strip():
            save_api_key(config.api_key)
    except RuntimeError as secret_error:
        raise HTTPException(status_code=500, detail=str(secret_error)) from secret_error
    save_app_setting("model_base_url", config.base_url)
    save_app_setting("model_name", config.model)
    save_app_setting("embedding_model", embedding_model)
    save_app_setting(
        "embedding_enabled",
        "true" if request.embedding_enabled else "false",
    )
    return serialize_model_settings()


@app.post("/api/model-settings/test")
def test_model_settings(request: ModelSettingsRequest) -> dict[str, bool]:
    config = model_config_from_request(request)
    try:
        test_model_connection(config)
    except ModelRequestError as model_error:
        raise HTTPException(
            status_code=model_error.status,
            detail=str(model_error),
        ) from model_error
    return {"ok": True}


@app.post("/api/model-settings/test-embedding")
def test_embedding_settings(request: ModelSettingsRequest) -> dict[str, bool]:
    config = embedding_config_from_request(request)
    try:
        test_embedding_connection(config)
    except ModelRequestError as model_error:
        raise HTTPException(
            status_code=model_error.status,
            detail=str(model_error),
        ) from model_error
    return {"ok": True}


@app.post("/api/tutor/sessions")
def create_tutor_session(
    request: CreateTutorSessionRequest,
) -> dict[str, object]:
    root = require_active_workspace()
    try:
        selected = bind_tutor_selection(
            root,
            request.path,
            request.block_id,
            request.quote,
            page=request.page,
        )
    except TutorContextError as context_error:
        raise HTTPException(status_code=422, detail=str(context_error)) from context_error
    session = create_learning_session(
        root,
        str(selected["path"]),
        (
            str(selected["blockId"])
            if selected.get("blockId") is not None
            else None
        ),
        str(selected["quote"]),
        page=selected.get("page"),  # type: ignore[arg-type]
    )
    initial_source, _ = save_learning_session_source(
        root,
        str(session["id"]),
        selected,
        is_initial=True,
    )
    return {
        "id": session["id"],
        "path": session["path"],
        "blockId": session["block_id"],
        "page": session["page"],
        "quote": session["quote"],
        "createdAt": session["created_at"],
        "sources": [serialize_tutor_source(initial_source)],
    }


@app.post("/api/tutor/sessions/{session_id}/turns")
def create_tutor_turn(
    session_id: str,
    request: CreateTutorTurnRequest,
) -> StreamingResponse:
    root = require_active_workspace()
    session = load_learning_session(root, session_id)
    if session is None:
        raise HTTPException(status_code=404, detail="Learning session 不存在。")
    question = request.question.strip()
    if not question:
        raise HTTPException(status_code=422, detail="请输入问题。")
    if request.mode not in {"guided", "direct"}:
        raise HTTPException(status_code=422, detail="辅导模式无效。")
    resolve_workspace_file(str(session["path"]), {".md", ".pdf"})
    session_sources = list_learning_session_sources(root, session_id)
    config = configured_model()
    embedding_config = configured_embedding()
    return StreamingResponse(
        event_stream(
            root,
            session,
            session_sources,
            config,
            embedding_config,
            question,
            request.mode,
            request.supplement_requested,
        ),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-store",
            "X-Accel-Buffering": "no",
        },
    )


def require_learning_session(session_id: str) -> tuple[Path, dict[str, object]]:
    root = require_active_workspace()
    session = load_learning_session(root, session_id)
    if session is None:
        raise HTTPException(status_code=404, detail="Learning session 不存在。")
    resolve_workspace_file(str(session["path"]), {".md", ".pdf"})
    return root, session


@app.get("/api/tutor/sessions/{session_id}/sources")
def tutor_sources(session_id: str) -> dict[str, object]:
    root, _session = require_learning_session(session_id)
    return {
        "sources": [
            serialize_tutor_source(source)
            for source in list_learning_session_sources(root, session_id)
        ]
    }


@app.post("/api/tutor/sessions/{session_id}/sources")
def add_tutor_source(
    session_id: str,
    request: AddTutorSourceRequest,
) -> dict[str, object]:
    root, _session = require_learning_session(session_id)
    try:
        resolved = resolve_tutor_source(
            root,
            request.path,
            block_id=request.block_id,
            page=request.page,
            quote=request.quote,
        )
    except TutorContextError as context_error:
        raise HTTPException(status_code=422, detail=str(context_error)) from context_error
    source, deduplicated = save_learning_session_source(
        root,
        session_id,
        resolved,
    )
    return {
        "source": serialize_tutor_source(source),
        "deduplicated": deduplicated,
    }


@app.delete("/api/tutor/sessions/{session_id}/sources/{source_id}")
def remove_tutor_source(
    session_id: str,
    source_id: str,
) -> dict[str, bool]:
    root, _session = require_learning_session(session_id)
    try:
        deleted = delete_learning_session_source(root, session_id, source_id)
    except ValueError as source_error:
        raise HTTPException(status_code=409, detail=str(source_error)) from source_error
    if not deleted:
        raise HTTPException(status_code=404, detail="Learning source 不存在。")
    return {"deleted": True}


def saved_practice_response(
    workspace: Path,
    session_id: str,
) -> dict[str, object]:
    loaded = load_practice_set(workspace, session_id)
    if loaded is None:
        return serialize_practice(None, [])
    attempts = list_practice_attempts(
        workspace,
        session_id,
        str(loaded["practice"]["id"]),  # type: ignore[index]
    )
    return serialize_practice(loaded, attempts)


@app.get("/api/tutor/sessions/{session_id}/practice")
def get_practice(session_id: str) -> dict[str, object]:
    root, _session = require_learning_session(session_id)
    return saved_practice_response(root, session_id)


@app.post("/api/tutor/sessions/{session_id}/practice")
def create_practice(
    session_id: str,
    request: CreatePracticeRequest,
) -> dict[str, object]:
    root, session = require_learning_session(session_id)
    config = configured_model()
    try:
        return generate_practice(
            root,
            session,
            config,
            request.question_count,
        )
    except PracticeGenerationError as practice_error:
        raise HTTPException(status_code=502, detail=str(practice_error)) from practice_error
    except TutorContextError as context_error:
        raise HTTPException(status_code=422, detail=str(context_error)) from context_error
    except ModelRequestError as model_error:
        raise HTTPException(
            status_code=model_error.status,
            detail=str(model_error),
        ) from model_error


@app.post("/api/tutor/sessions/{session_id}/practice/attempts")
def create_practice_attempt(
    session_id: str,
    request: CreatePracticeAttemptRequest,
) -> dict[str, object]:
    root, _session = require_learning_session(session_id)
    try:
        attempt = save_practice_attempt(
            root,
            session_id,
            request.practice_item_id,
            request.selected_index,
        )
    except ValueError as selection_error:
        raise HTTPException(status_code=422, detail=str(selection_error)) from selection_error
    if attempt is None:
        raise HTTPException(status_code=404, detail="Practice item 不存在。")
    return {
        "id": attempt["id"],
        "practiceItemId": attempt["practice_item_id"],
        "selectedIndex": attempt["selected_index"],
        "correct": bool(attempt["correct"]),
        "answeredAt": attempt["answered_at"],
    }


@app.get("/api/settings/qiniu")
def qiniu_settings() -> dict[str, object]:
    return serialize_qiniu_settings()


@app.put("/api/settings/qiniu")
def update_qiniu_settings(request: QiniuSettingsRequest) -> dict[str, object]:
    bucket = normalize_qiniu_bucket(request.bucket)
    domain = normalize_qiniu_domain(request.domain)
    store = credential_store()
    current_access_key = store.get(ACCESS_KEY_ACCOUNT)
    current_secret_key = store.get(SECRET_KEY_ACCOUNT)
    access_key = (request.access_key or "").strip() or current_access_key
    secret_key = (request.secret_key or "").strip() or current_secret_key
    if not access_key or not secret_key:
        raise HTTPException(
            status_code=422,
            detail="首次配置需要同时填写 Access Key 和 Secret Key。",
        )

    save_qiniu_credentials(access_key, secret_key)
    save_qiniu_settings(bucket, domain)
    return serialize_qiniu_settings()


@app.post("/api/images", status_code=201)
def create_image(file: UploadFile = File(...)) -> dict[str, object]:
    workspace = require_active_workspace()
    try:
        return upload_image(
            workspace,
            file.filename or "image",
            file.content_type or "",
            file.file.read(MAX_IMAGE_BYTES + 1),
        )
    except QiniuError as error:
        raise HTTPException(status_code=502, detail=str(error)) from error


@app.post("/api/images/delete")
def remove_image(request: DeleteImageRequest) -> dict[str, object]:
    workspace = require_active_workspace()
    try:
        return delete_image(workspace, request.url)
    except QiniuError as error:
        raise HTTPException(status_code=502, detail=str(error)) from error


@app.get("/api/images/asset")
def workspace_image(path: str) -> FileResponse:
    file_path = resolve_workspace_file(
        path,
        {".png", ".jpg", ".jpeg", ".gif", ".webp"},
    )
    media_type = mimetypes.guess_type(file_path.name)[0] or "application/octet-stream"
    return FileResponse(
        file_path,
        media_type=media_type,
        headers={"Cache-Control": "no-store"},
    )


@app.post("/api/images/local")
def upload_local_image(request: LocalImageRequest) -> dict[str, object]:
    if request.src.startswith(("http://", "https://", "data:", "blob:")):
        raise HTTPException(status_code=422, detail="这张图片已经是远程图片。")
    parsed_src = unquote(request.src.split("?", 1)[0].split("#", 1)[0])
    page_dir = posixpath.dirname(request.path)
    if parsed_src.startswith("/"):
        relative = parsed_src.lstrip("/")
    else:
        relative = posixpath.normpath(posixpath.join(page_dir, parsed_src))
    if relative.startswith("../"):
        raise HTTPException(status_code=400, detail="图片路径无效。")
    file_path = resolve_workspace_file(
        relative,
        {".png", ".jpg", ".jpeg", ".gif", ".webp"},
    )
    content_type = mimetypes.guess_type(file_path.name)[0] or ""
    try:
        uploaded = upload_image(
            require_active_workspace(),
            file_path.name,
            content_type,
            file_path.read_bytes(),
        )
    except QiniuError as error:
        raise HTTPException(status_code=502, detail=str(error)) from error
    return {"source": request.src, **uploaded}


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


@app.get("/api/search")
def search(q: str = "") -> dict[str, object]:
    root = require_active_workspace()
    results, index = search_workspace(root, q)
    return {"index": index, "results": results}


@app.post("/api/search/reindex")
def rebuild_search_index() -> dict[str, object]:
    root = require_active_workspace()
    index = rebuild_workspace_index(root)
    return {"index": index}


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
    old_relative_path = source.relative_to(root).as_posix()

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

    source_sidecar = sidecar_path_for(source)
    destination_sidecar = sidecar_path_for(destination)
    source.rename(destination)
    if source_sidecar.exists():
        source_sidecar.rename(destination_sidecar)
    move_document_draft(root, old_relative_path, request.new_path)
    return {
        "newPath": destination.relative_to(root).as_posix(),
        "oldPath": old_relative_path,
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
    sidecar_path_for(source).unlink(missing_ok=True)
    delete_document_draft(root, deleted_path)

    return {
        "deletedPath": deleted_path,
        "tree": workspace_tree(root, root),
    }


@app.get("/api/file")
def read_file(path: str) -> dict[str, object]:
    file_path = resolve_workspace_file(path, {".md"})
    return serialize_document(file_path)


@app.post("/api/file")
def write_file(request: SaveDocumentRequest) -> dict[str, object]:
    file_path = resolve_workspace_file(request.path, {".md"})
    try:
        save_document(
            file_path,
            request.content,
            request.blocks,
            request.expected_revision,
        )
    except DocumentConflictError as error:
        raise HTTPException(status_code=409, detail=conflict_payload(file_path)) from error
    except (OSError, ValueError) as error:
        raise HTTPException(status_code=422, detail=str(error)) from error

    delete_document_draft(require_active_workspace(), request.path)
    return serialize_document(file_path)


@app.put("/api/drafts")
def write_draft(request: SaveDraftRequest) -> dict[str, object]:
    file_path = resolve_workspace_file(request.path, {".md"})
    try:
        blocks_json = json.dumps(request.blocks, ensure_ascii=False)
        draft = save_document_draft(
            require_active_workspace(),
            request.path,
            request.content,
            blocks_json,
            request.base_revision,
        )
    except (TypeError, ValueError) as error:
        raise HTTPException(status_code=422, detail="草稿无法保存。") from error

    return {
        "path": file_path.relative_to(require_active_workspace()).as_posix(),
        "updatedAt": draft["updated_at"],
    }


@app.delete("/api/drafts")
def discard_draft(path: str) -> dict[str, bool]:
    resolve_workspace_file(path, {".md"})
    delete_document_draft(require_active_workspace(), path)
    return {"deleted": True}


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
