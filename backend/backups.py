from __future__ import annotations

import gzip
import hashlib
import io
import json
import os
from datetime import datetime, timezone
from pathlib import Path
import tempfile
import threading
import time
from typing import cast
import uuid

from documents import sidecar_path_for
from storage import (
    application_data_directory,
    connect,
    load_active_workspace,
    load_app_setting,
    load_qiniu_settings,
)


BACKUP_FORMAT = "studynotes-backup"
BACKUP_SCHEMA_VERSION = 1
BACKUP_SUFFIX = ".studynotes.gz"
MAX_PACKAGE_BYTES = 64 * 1024 * 1024
MAX_PAYLOAD_BYTES = 128 * 1024 * 1024
SUPPORTED_SOURCE_SUFFIXES = {".md", ".pdf"}
PREVIEW_TTL_SECONDS = 60 * 60

TABLE_COLUMNS: dict[str, tuple[str, ...]] = {
    "document_drafts": (
        "workspace_path",
        "path",
        "markdown",
        "blocks_json",
        "base_revision",
        "updated_at",
    ),
    "source_citations": (
        "id",
        "workspace_path",
        "path",
        "page",
        "quote",
        "pdf_sha256",
        "extractor_version",
        "created_at",
    ),
    "uploaded_images": (
        "workspace_path",
        "object_key",
        "url",
        "mime_type",
        "size",
        "created_at",
    ),
    "learning_sessions": (
        "id",
        "workspace_path",
        "path",
        "block_id",
        "page",
        "quote",
        "created_at",
        "updated_at",
    ),
    "session_messages": (
        "id",
        "workspace_path",
        "session_id",
        "role",
        "content",
        "answer_type",
        "citations_json",
        "context_json",
        "created_at",
    ),
    "learning_session_sources": (
        "id",
        "workspace_path",
        "session_id",
        "kind",
        "path",
        "block_id",
        "block_index",
        "page",
        "heading_path_json",
        "quote",
        "source_key",
        "is_initial",
        "created_at",
    ),
    "practice_sets": (
        "id",
        "workspace_path",
        "session_id",
        "question_count",
        "created_at",
    ),
    "practice_items": (
        "id",
        "practice_set_id",
        "workspace_path",
        "session_id",
        "ordinal",
        "item_type",
        "stem",
        "options_json",
        "correct_index",
        "explanation",
        "reference_answer",
        "citation_json",
        "created_at",
    ),
    "practice_attempts": (
        "id",
        "workspace_path",
        "session_id",
        "practice_set_id",
        "practice_item_id",
        "selected_index",
        "correct",
        "answer_text",
        "feedback_json",
        "ai_score",
        "final_score",
        "feedback_status",
        "feedback_error",
        "answered_at",
        "feedback_updated_at",
    ),
    "gap_records": (
        "id",
        "workspace_path",
        "session_id",
        "practice_item_id",
        "title",
        "citation_json",
        "schedule_step",
        "next_review_at",
        "created_at",
        "updated_at",
    ),
    "review_results": (
        "id",
        "workspace_path",
        "gap_id",
        "answer",
        "feedback",
        "result",
        "reviewed_at",
        "next_review_at",
    ),
}

DATA_FIELD_NAMES = {
    "document_drafts": "documentDrafts",
    "source_citations": "sourceCitations",
    "uploaded_images": "uploadedImages",
    "learning_sessions": "learningSessions",
    "session_messages": "sessionMessages",
    "learning_session_sources": "learningSessionSources",
    "practice_sets": "practiceSets",
    "practice_items": "practiceItems",
    "practice_attempts": "practiceAttempts",
    "gap_records": "gapRecords",
    "review_results": "reviewResults",
}

MODEL_SETTING_KEYS = {
    "baseUrl": "model_base_url",
    "model": "model_name",
    "embeddingModel": "embedding_model",
    "embeddingEnabled": "embedding_enabled",
}

BANNED_SECRET_KEYS = {
    "api_key",
    "apikey",
    "access_key",
    "accesskey",
    "secret_key",
    "secretkey",
    "authorization",
}


class BackupError(Exception):
    pass


class BackupPackageError(BackupError):
    pass


class BackupPreviewError(BackupError):
    pass


class BackupRestoreError(BackupError):
    pass


_preview_lock = threading.Lock()
_previews: dict[str, dict[str, object]] = {}


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _file_sha256(file_path: Path) -> str:
    digest = hashlib.sha256()
    with file_path.open("rb") as handle:
        while chunk := handle.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def _relative_source_files(workspace: Path) -> list[Path]:
    files: list[Path] = []
    for candidate in workspace.rglob("*"):
        relative = candidate.relative_to(workspace)
        if any(part.startswith(".") for part in relative.parts):
            continue
        if candidate.is_symlink() or not candidate.is_file():
            continue
        if candidate.suffix.lower() in SUPPORTED_SOURCE_SUFFIXES:
            files.append(candidate)
    return sorted(files, key=lambda item: item.as_posix().casefold())


def _markdown_sidecar_record(file_path: Path, workspace: Path) -> dict[str, object]:
    sidecar_path = sidecar_path_for(file_path)
    relative_file = file_path.relative_to(workspace).as_posix()
    relative_sidecar = sidecar_path.relative_to(workspace).as_posix()
    record: dict[str, object] = {
        "kind": "markdown",
        "path": relative_file,
        "sourceFileSha256": _file_sha256(file_path),
        "sidecarPath": relative_sidecar,
        "sidecarSha256": None,
        "sidecarStatus": "missing",
        "sidecarSourceMarkdownSha256": None,
    }
    if sidecar_path.is_symlink():
        record["sidecarStatus"] = "invalid"
        return record
    if not sidecar_path.is_file():
        return record

    sidecar_bytes = sidecar_path.read_bytes()
    record["sidecarSha256"] = _sha256_bytes(sidecar_bytes)
    try:
        sidecar = json.loads(sidecar_bytes.decode("utf-8"))
        if not isinstance(sidecar, dict):
            raise ValueError("sidecar must be an object")
        source_hash = sidecar.get("sourceMarkdownSha256")
        if not isinstance(source_hash, str) or len(source_hash) != 64:
            raise ValueError("sidecar source hash is invalid")
        record["sidecarSourceMarkdownSha256"] = source_hash
        record["sidecarStatus"] = (
            "valid"
            if source_hash == record["sourceFileSha256"]
            else "mismatched"
        )
    except (UnicodeDecodeError, json.JSONDecodeError, ValueError):
        record["sidecarStatus"] = "invalid"
    return record


def _sidecar_manifest(workspace: Path) -> list[dict[str, object]]:
    records: list[dict[str, object]] = []
    for file_path in _relative_source_files(workspace):
        if file_path.suffix.lower() == ".md":
            records.append(_markdown_sidecar_record(file_path, workspace))
        else:
            records.append(
                {
                    "kind": "pdf",
                    "path": file_path.relative_to(workspace).as_posix(),
                    "sourceFileSha256": _file_sha256(file_path),
                }
            )
    return records


def _workspace_rows(workspace_path: str) -> dict[str, list[dict[str, object]]]:
    data: dict[str, list[dict[str, object]]] = {}
    with connect() as connection:
        for table, columns in TABLE_COLUMNS.items():
            selected = ", ".join(columns)
            rows = connection.execute(
                f"""
                SELECT {selected}
                FROM {table}
                WHERE workspace_path = ?
                ORDER BY rowid ASC
                """,
                (workspace_path,),
            ).fetchall()
            data[DATA_FIELD_NAMES[table]] = [dict(row) for row in rows]

        workspace_row = connection.execute(
            """
            SELECT path, name, created_at, updated_at
            FROM workspaces
            WHERE path = ?
            """,
            (workspace_path,),
        ).fetchone()
    data["workspaceRegistration"] = (
        [dict(workspace_row)] if workspace_row is not None else []
    )
    return data


def _assert_no_secret_keys(value: object) -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if str(key).casefold() in BANNED_SECRET_KEYS:
                raise BackupError("备份数据包含不允许导出的密钥字段。")
            _assert_no_secret_keys(child)
    elif isinstance(value, list):
        for child in value:
            _assert_no_secret_keys(child)


def _build_payload(workspace: Path, kind: str) -> dict[str, object]:
    resolved = workspace.resolve()
    active_workspace = load_active_workspace()
    qiniu = load_qiniu_settings()
    model = {
        field: load_app_setting(storage_key)
        for field, storage_key in MODEL_SETTING_KEYS.items()
    }
    model["embeddingEnabled"] = model["embeddingEnabled"] == "true"
    payload: dict[str, object] = {
        "format": BACKUP_FORMAT,
        "schemaVersion": BACKUP_SCHEMA_VERSION,
        "kind": kind,
        "createdAt": _utc_now().isoformat().replace("+00:00", "Z"),
        "sourceWorkspace": {
            "path": str(resolved),
            "name": resolved.name or str(resolved),
            "activeWorkspacePath": (
                str(active_workspace.resolve())
                if active_workspace is not None
                else None
            ),
        },
        "settings": {
            "model": model,
            "qiniu": {
                "bucket": qiniu["bucket"] if qiniu is not None else "",
                "domain": qiniu["domain"] if qiniu is not None else "",
            },
        },
        "secrets": {
            "modelApiKeyIncluded": False,
            "qiniuAccessKeyIncluded": False,
            "qiniuSecretKeyIncluded": False,
            "authorizationIncluded": False,
        },
        "sidecars": _sidecar_manifest(resolved),
        "data": _workspace_rows(str(resolved)),
    }
    _assert_no_secret_keys(payload)
    return payload


def _backup_directory() -> Path:
    directory = application_data_directory() / "backups"
    directory.mkdir(parents=True, exist_ok=True)
    return directory


def _atomic_write_bytes(file_path: Path, content: bytes) -> None:
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{file_path.name}.",
        suffix=".tmp",
        dir=file_path.parent,
    )
    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_path, file_path)
        directory_descriptor = os.open(file_path.parent, os.O_RDONLY)
        try:
            os.fsync(directory_descriptor)
        finally:
            os.close(directory_descriptor)
    except Exception:
        temporary_path.unlink(missing_ok=True)
        raise


def create_backup(workspace: Path, *, kind: str = "manual") -> dict[str, object]:
    payload = _build_payload(workspace, kind)
    serialized = json.dumps(
        payload,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")
    package = gzip.compress(serialized, compresslevel=6, mtime=0)
    timestamp = _utc_now().strftime("%Y%m%dT%H%M%S%fZ")
    prefix = "studynotes-rollback" if kind == "rollback" else "studynotes-backup"
    file_path = _backup_directory() / (
        f"{prefix}-{timestamp}-{uuid.uuid4().hex[:8]}{BACKUP_SUFFIX}"
    )
    _atomic_write_bytes(file_path, package)
    return {
        "path": str(file_path),
        "filename": file_path.name,
        "createdAt": payload["createdAt"],
        "kind": kind,
        "size": len(package),
    }


def _validate_sha256(value: object, label: str) -> str:
    if not isinstance(value, str) or len(value) != 64:
        raise BackupPackageError(f"{label}校验值无效。")
    try:
        int(value, 16)
    except ValueError as error:
        raise BackupPackageError(f"{label}校验值无效。") from error
    return value.lower()


def _safe_relative_path(
    value: object,
    *,
    label: str,
    suffixes: set[str] = SUPPORTED_SOURCE_SUFFIXES,
) -> str:
    if not isinstance(value, str) or not value or len(value) > 4096:
        raise BackupPackageError(f"{label}路径无效。")
    if "\x00" in value or "\\" in value or value.startswith("/"):
        raise BackupPackageError(f"{label}路径必须是安全的相对路径。")
    parts = value.split("/")
    if any(part in {"", ".", ".."} or ":" in part for part in parts):
        raise BackupPackageError(f"{label}路径必须是安全的相对路径。")
    if Path(value).suffix.lower() not in suffixes:
        raise BackupPackageError(f"{label}文件类型不受支持。")
    return value


def _workspace_target_file(
    workspace: Path,
    relative_path: str,
    *,
    label: str,
) -> Path:
    root = workspace.resolve()
    unresolved = root / relative_path
    if unresolved.is_symlink():
        raise BackupRestoreError(f"{label}不能是符号链接。")
    candidate = unresolved.resolve()
    try:
        candidate.relative_to(root)
    except ValueError as error:
        raise BackupRestoreError(f"{label}路径越过了当前工作区。") from error
    if candidate.is_symlink() or not candidate.is_file():
        raise BackupRestoreError(f"{label}文件在当前工作区中不存在。")
    return candidate


def _json_path_values(raw: object, label: str) -> list[str]:
    if raw is None or raw == "":
        return []
    if isinstance(raw, str):
        try:
            parsed = json.loads(raw)
        except json.JSONDecodeError as error:
            raise BackupPackageError(f"{label} JSON 无效。") from error
    else:
        parsed = raw

    paths: list[str] = []

    def visit(value: object) -> None:
        if isinstance(value, dict):
            if "path" in value:
                paths.append(_safe_relative_path(value["path"], label=label))
            for child in value.values():
                visit(child)
        elif isinstance(value, list):
            for child in value:
                visit(child)

    visit(parsed)
    return paths


def _validate_payload(payload: dict[str, object]) -> None:
    _assert_no_secret_keys(payload)
    if payload.get("format") != BACKUP_FORMAT:
        raise BackupPackageError("备份包格式不受支持。")
    if payload.get("schemaVersion") != BACKUP_SCHEMA_VERSION:
        raise BackupPackageError("备份包版本不受支持。")
    if payload.get("kind") not in {"manual", "rollback"}:
        raise BackupPackageError("备份包类型无效。")

    source_workspace = payload.get("sourceWorkspace")
    if not isinstance(source_workspace, dict):
        raise BackupPackageError("备份包缺少来源工作区。")
    source_path = source_workspace.get("path")
    if (
        not isinstance(source_path, str)
        or not source_path
        or not Path(source_path).is_absolute()
    ):
        raise BackupPackageError("备份包来源工作区路径无效。")
    active_path = source_workspace.get("activeWorkspacePath")
    if active_path is not None and (
        not isinstance(active_path, str) or not Path(active_path).is_absolute()
    ):
        raise BackupPackageError("备份包激活工作区信息无效。")
    if not isinstance(source_workspace.get("name"), str):
        raise BackupPackageError("备份包来源工作区名称无效。")

    settings = payload.get("settings")
    if not isinstance(settings, dict) or not isinstance(
        settings.get("model"), dict
    ) or not isinstance(settings.get("qiniu"), dict):
        raise BackupPackageError("备份包设置结构无效。")
    model = settings["model"]
    if not isinstance(model.get("embeddingEnabled"), bool):
        raise BackupPackageError("备份包模型设置无效。")
    for field in ("baseUrl", "model", "embeddingModel"):
        if not isinstance(model.get(field), str):
            raise BackupPackageError("备份包模型设置无效。")
    qiniu = settings["qiniu"]
    for field in ("bucket", "domain"):
        if not isinstance(qiniu.get(field), str):
            raise BackupPackageError("备份包七牛设置无效。")

    data = payload.get("data")
    if not isinstance(data, dict):
        raise BackupPackageError("备份包缺少学习数据。")
    rows_by_table: dict[str, list[dict[str, object]]] = {}
    for table, columns in TABLE_COLUMNS.items():
        field = DATA_FIELD_NAMES[table]
        raw_rows = data.get(field)
        if not isinstance(raw_rows, list):
            raise BackupPackageError(f"备份包缺少 {field}。")
        rows: list[dict[str, object]] = []
        for raw_row in raw_rows:
            if not isinstance(raw_row, dict) or set(raw_row) != set(columns):
                raise BackupPackageError(f"备份包 {field} 行结构无效。")
            if raw_row.get("workspace_path") != source_path:
                raise BackupPackageError("备份包数据包含非来源工作区记录。")
            rows.append(raw_row)
        rows_by_table[table] = rows

    for row in rows_by_table["document_drafts"]:
        _safe_relative_path(row.get("path"), label="Markdown", suffixes={".md"})
    for row in rows_by_table["source_citations"]:
        _safe_relative_path(row.get("path"), label="PDF", suffixes={".pdf"})
        _validate_sha256(row.get("pdf_sha256"), "Source citation")
    for row in rows_by_table["learning_sessions"]:
        _safe_relative_path(row.get("path"), label="Learning source")
    for row in rows_by_table["learning_session_sources"]:
        _safe_relative_path(row.get("path"), label="Learning source")
    for row in rows_by_table["session_messages"]:
        _json_path_values(row.get("citations_json"), "Session message citation")
        _json_path_values(row.get("context_json"), "Session message context")
    for row in rows_by_table["practice_items"]:
        _json_path_values(row.get("citation_json"), "Practice citation")
    for row in rows_by_table["gap_records"]:
        _json_path_values(row.get("citation_json"), "Gap citation")

    registration = data.get("workspaceRegistration")
    if not isinstance(registration, list):
        raise BackupPackageError("备份包缺少工作区注册信息。")
    for row in registration:
        if not isinstance(row, dict) or row.get("path") != source_path:
            raise BackupPackageError("备份包工作区注册信息无效。")

    sidecars = payload.get("sidecars")
    if not isinstance(sidecars, list):
        raise BackupPackageError("备份包缺少页面结构校验信息。")
    seen_paths: set[str] = set()
    for raw_record in sidecars:
        if not isinstance(raw_record, dict):
            raise BackupPackageError("备份包页面结构校验信息无效。")
        kind = raw_record.get("kind")
        if kind not in {"markdown", "pdf"}:
            raise BackupPackageError("备份包页面结构类型无效。")
        relative_path = _safe_relative_path(
            raw_record.get("path"),
            label="Sidecar",
        )
        if relative_path in seen_paths:
            raise BackupPackageError("备份包页面结构路径重复。")
        seen_paths.add(relative_path)
        _validate_sha256(raw_record.get("sourceFileSha256"), "源文件")
        if kind == "markdown":
            sidecar_path = _safe_relative_path(
                raw_record.get("sidecarPath"),
                label="Markdown 页面结构",
                suffixes={".json"},
            )
            if not sidecar_path.endswith(".md.note.json"):
                raise BackupPackageError("Markdown 页面结构路径无效。")
            status = raw_record.get("sidecarStatus")
            if status not in {"valid", "missing", "mismatched", "invalid"}:
                raise BackupPackageError("Markdown 页面结构状态无效。")
            sidecar_sha = raw_record.get("sidecarSha256")
            if sidecar_sha is not None:
                _validate_sha256(sidecar_sha, "Markdown 页面结构")
            source_markdown_sha = raw_record.get(
                "sidecarSourceMarkdownSha256"
            )
            if source_markdown_sha is not None:
                _validate_sha256(source_markdown_sha, "Markdown 页面结构来源")

    sessions = {
        str(row["id"]) for row in rows_by_table["learning_sessions"]
    }
    for row in rows_by_table["session_messages"]:
        if str(row["session_id"]) not in sessions:
            raise BackupPackageError("备份包会话消息关系无效。")
    for row in rows_by_table["learning_session_sources"]:
        if str(row["session_id"]) not in sessions:
            raise BackupPackageError("备份包会话来源关系无效。")

    practice_sets = {
        str(row["id"]) for row in rows_by_table["practice_sets"]
    }
    practice_items = {
        str(row["id"]): row for row in rows_by_table["practice_items"]
    }
    for item in practice_items.values():
        if str(item["practice_set_id"]) not in practice_sets:
            raise BackupPackageError("备份包练习题目关系无效。")
    for attempt in rows_by_table["practice_attempts"]:
        item_id = str(attempt["practice_item_id"])
        if item_id not in practice_items:
            raise BackupPackageError("备份包练习作答关系无效。")
        if str(practice_items[item_id]["practice_set_id"]) != str(
            attempt["practice_set_id"]
        ):
            raise BackupPackageError("备份包练习集合关系无效。")
    for gap in rows_by_table["gap_records"]:
        practice_item_id = gap.get("practice_item_id")
        if practice_item_id is not None and str(practice_item_id) not in practice_items:
            raise BackupPackageError("备份包知识缺口关系无效。")
    gaps = {str(row["id"]) for row in rows_by_table["gap_records"]}
    for review in rows_by_table["review_results"]:
        if str(review["gap_id"]) not in gaps:
            raise BackupPackageError("备份包复习结果关系无效。")


def _decode_package(package_bytes: bytes) -> tuple[dict[str, object], str]:
    if not package_bytes or len(package_bytes) > MAX_PACKAGE_BYTES:
        raise BackupPackageError("备份包为空或超过大小限制。")
    package_sha = _sha256_bytes(package_bytes)
    try:
        with gzip.GzipFile(fileobj=io.BytesIO(package_bytes)) as package:
            payload_bytes = package.read(MAX_PAYLOAD_BYTES + 1)
    except (OSError, EOFError) as error:
        raise BackupPackageError("备份包损坏，无法读取。") from error
    if len(payload_bytes) > MAX_PAYLOAD_BYTES:
        raise BackupPackageError("备份包解压后超过大小限制。")
    try:
        payload = json.loads(payload_bytes.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise BackupPackageError("备份包内容不是有效的 JSON。") from error
    if not isinstance(payload, dict):
        raise BackupPackageError("备份包顶层结构无效。")
    _validate_payload(payload)
    return payload, package_sha


def _sidecar_review(
    payload: dict[str, object],
    workspace: Path,
) -> dict[str, object]:
    records = cast(list[object], payload["sidecars"])
    issues: list[dict[str, str]] = []
    matched = 0
    for raw_record in records:
        record = cast(dict[str, object], raw_record)
        relative_path = str(record["path"])
        try:
            source_path = _workspace_target_file(
                workspace,
                relative_path,
                label="Learning source",
            )
        except BackupRestoreError as error:
            issues.append(
                {
                    "path": relative_path,
                    "status": "missing",
                    "message": str(error),
                }
            )
            continue
        if _file_sha256(source_path) != record["sourceFileSha256"]:
            issues.append(
                {
                    "path": relative_path,
                    "status": "changed",
                    "message": "当前文件与备份时不一致。",
                }
            )
            continue

        if record["kind"] == "markdown":
            sidecar_relative_path = str(record["sidecarPath"])
            try:
                sidecar_path = (
                    _workspace_target_file(
                        workspace,
                        sidecar_relative_path,
                        label="Markdown 页面结构",
                    )
                    if (workspace / sidecar_relative_path).exists()
                    else None
                )
            except BackupRestoreError as error:
                issues.append(
                    {
                        "path": relative_path,
                        "status": "sidecar-invalid",
                        "message": str(error),
                    }
                )
                continue
            status = record["sidecarStatus"]
            if status in {"invalid", "mismatched"}:
                issues.append(
                    {
                        "path": relative_path,
                        "status": str(status),
                        "message": "Markdown 页面结构在备份时已无效。",
                    }
                )
                continue
            if status == "missing":
                if sidecar_path is not None:
                    issues.append(
                        {
                            "path": relative_path,
                            "status": "sidecar-added",
                            "message": "当前工作区多出了页面结构文件。",
                        }
                    )
                    continue
            else:
                if sidecar_path is None:
                    issues.append(
                        {
                            "path": relative_path,
                            "status": "sidecar-missing",
                            "message": "当前工作区缺少 Markdown 页面结构文件。",
                        }
                    )
                    continue
                if _file_sha256(sidecar_path) != record["sidecarSha256"]:
                    issues.append(
                        {
                            "path": relative_path,
                            "status": "sidecar-changed",
                            "message": "Markdown 页面结构与备份时不一致。",
                        }
                    )
                    continue
        matched += 1

    manifest_by_path = {
        str(record["path"]): record
        for record in (
            cast(dict[str, object], raw_record)
            for raw_record in records
        )
    }
    data = cast(dict[str, object], payload["data"])
    referenced_paths: dict[str, str] = {}
    for row in cast(list[dict[str, object]], data["documentDrafts"]):
        referenced_paths[str(row["path"])] = "编辑草稿"
    for row in cast(list[dict[str, object]], data["learningSessions"]):
        referenced_paths[str(row["path"])] = "学习会话"
    for row in cast(
        list[dict[str, object]],
        data["learningSessionSources"],
    ):
        referenced_paths[str(row["path"])] = "学习来源"
    for row in cast(list[dict[str, object]], data["sessionMessages"]):
        for path in _json_path_values(
            row.get("citations_json"),
            "Session message citation",
        ):
            referenced_paths[path] = "会话引用"
        for path in _json_path_values(
            row.get("context_json"),
            "Session message context",
        ):
            referenced_paths[path] = "会话上下文"
    for row in cast(list[dict[str, object]], data["practiceItems"]):
        for path in _json_path_values(
            row.get("citation_json"),
            "Practice citation",
        ):
            referenced_paths[path] = "练习引用"
    for row in cast(list[dict[str, object]], data["gapRecords"]):
        for path in _json_path_values(
            row.get("citation_json"),
            "Gap citation",
        ):
            referenced_paths[path] = "知识缺口引用"
    for path, record_kind in sorted(referenced_paths.items()):
        if path not in manifest_by_path:
            issues.append(
                {
                    "path": path,
                    "status": "source-unlisted",
                    "message": f"{record_kind}引用的资料不在当前工作区校验清单中。",
                }
            )

    for row in cast(list[dict[str, object]], data["sourceCitations"]):
        path = str(row["path"])
        record = manifest_by_path.get(path)
        if record is None:
            issues.append(
                {
                    "path": path,
                    "status": "source-unlisted",
                    "message": "资料引用指向的 PDF 不在当前工作区校验清单中。",
                }
            )
        elif row["pdf_sha256"] != record["sourceFileSha256"]:
            issues.append(
                {
                    "path": path,
                    "status": "citation-changed",
                    "message": "资料引用记录的 PDF 校验值与备份文件不一致。",
                }
            )

    return {
        "total": len(records),
        "matched": matched,
        "issues": issues,
        "canRestore": not issues,
    }


def _data_counts(payload: dict[str, object]) -> dict[str, int]:
    data = cast(dict[str, object], payload["data"])
    return {
        "documentDrafts": len(data["documentDrafts"]),
        "sourceCitations": len(data["sourceCitations"]),
        "learningSessions": len(data["learningSessions"]),
        "sessionMessages": len(data["sessionMessages"]),
        "practiceSets": len(data["practiceSets"]),
        "practiceItems": len(data["practiceItems"]),
        "practiceAttempts": len(data["practiceAttempts"]),
        "gapRecords": len(data["gapRecords"]),
        "reviewResults": len(data["reviewResults"]),
    }


def _prune_previews() -> None:
    now = time.monotonic()
    expired = [
        preview_id
        for preview_id, preview in _previews.items()
        if float(preview["expiresAt"]) <= now
    ]
    for preview_id in expired:
        _previews.pop(preview_id, None)


def preview_backup(package_bytes: bytes, workspace: Path) -> dict[str, object]:
    payload, package_sha = _decode_package(package_bytes)
    sidecar_review = _sidecar_review(payload, workspace)
    rollback = create_backup(workspace, kind="rollback")
    preview_id = str(uuid.uuid4())
    now = time.monotonic()
    with _preview_lock:
        _prune_previews()
        _previews[preview_id] = {
            "packageSha256": package_sha,
            "workspacePath": str(workspace.resolve()),
            "rollbackPath": rollback["path"],
            "canRestore": sidecar_review["canRestore"],
            "expiresAt": now + PREVIEW_TTL_SECONDS,
        }
    source_workspace = cast(dict[str, object], payload["sourceWorkspace"])
    settings = cast(dict[str, object], payload["settings"])
    model = cast(dict[str, object], settings["model"])
    qiniu = cast(dict[str, object], settings["qiniu"])
    return {
        "previewId": preview_id,
        "packageSha256": package_sha,
        "preview": {
            "createdAt": payload["createdAt"],
            "kind": payload["kind"],
            "sourceWorkspace": {
                "name": source_workspace["name"],
                "path": source_workspace["path"],
                "activeWorkspacePath": source_workspace.get(
                    "activeWorkspacePath"
                ),
            },
            "targetWorkspace": {
                "name": workspace.resolve().name,
                "path": str(workspace.resolve()),
            },
            "counts": _data_counts(payload),
            "sidecars": sidecar_review,
            "settings": {
                "model": {
                    "baseUrl": model["baseUrl"],
                    "model": model["model"],
                    "embeddingModel": model["embeddingModel"],
                    "embeddingEnabled": model["embeddingEnabled"],
                },
                "qiniu": {
                    "bucket": qiniu["bucket"],
                    "domain": qiniu["domain"],
                },
            },
            "canRestore": sidecar_review["canRestore"],
            "requiresSecretReconfiguration": True,
            "secretMessage": (
                "密钥未包含在备份中，请重新配置或读取 Keychain。"
            ),
        },
        "rollback": rollback,
    }


DELETE_ORDER = (
    "review_results",
    "gap_records",
    "practice_attempts",
    "practice_items",
    "practice_sets",
    "session_messages",
    "learning_session_sources",
    "learning_sessions",
    "source_citations",
    "document_drafts",
    "uploaded_images",
)


def _restore_transaction(
    payload: dict[str, object],
    workspace: Path,
) -> None:
    workspace_path = str(workspace.resolve())
    data = cast(dict[str, object], payload["data"])
    settings = cast(dict[str, object], payload["settings"])
    model = cast(dict[str, object], settings["model"])
    qiniu = cast(dict[str, object], settings["qiniu"])
    connection = connect()
    try:
        connection.execute("PRAGMA foreign_keys = ON")
        connection.execute("BEGIN IMMEDIATE")
        for table in DELETE_ORDER:
            connection.execute(
                f"DELETE FROM {table} WHERE workspace_path = ?",
                (workspace_path,),
            )
        for derived_table in ("search_fts", "embedding_entries", "search_sources"):
            connection.execute(
                f"DELETE FROM {derived_table} WHERE workspace_path = ?",
                (workspace_path,),
            )

        for table, columns in TABLE_COLUMNS.items():
            field = DATA_FIELD_NAMES[table]
            rows = cast(list[object], data[field])
            placeholders = ", ".join("?" for _ in columns)
            selected = ", ".join(columns)
            for raw_row in rows:
                row = dict(cast(dict[str, object], raw_row))
                row["workspace_path"] = workspace_path
                connection.execute(
                    f"""
                    INSERT INTO {table} ({selected})
                    VALUES ({placeholders})
                    """,
                    tuple(row[column] for column in columns),
                )

        connection.execute(
            """
            INSERT INTO workspaces (path, name)
            VALUES (?, ?)
            ON CONFLICT(path) DO UPDATE SET
                name = excluded.name,
                updated_at = CURRENT_TIMESTAMP
            """,
            (workspace_path, workspace.resolve().name or workspace_path),
        )
        connection.execute(
            """
            INSERT INTO app_state (key, value)
            VALUES ('active_workspace_path', ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
            """,
            (workspace_path,),
        )
        for field, storage_key in MODEL_SETTING_KEYS.items():
            value = model[field]
            connection.execute(
                """
                INSERT INTO app_state (key, value)
                VALUES (?, ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value
                """,
                (
                    storage_key,
                    (
                        "true"
                        if value is True
                        else "false"
                        if value is False
                        else str(value)
                    ),
                ),
            )
        if qiniu["bucket"] and qiniu["domain"]:
            connection.execute(
                """
                INSERT INTO qiniu_settings (id, bucket, domain)
                VALUES (1, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    bucket = excluded.bucket,
                    domain = excluded.domain,
                    updated_at = CURRENT_TIMESTAMP
                """,
                (qiniu["bucket"], qiniu["domain"]),
            )
        else:
            connection.execute("DELETE FROM qiniu_settings WHERE id = 1")

        expected_counts = _data_counts(payload)
        for table, field in (
            ("source_citations", "sourceCitations"),
            ("learning_sessions", "learningSessions"),
            ("session_messages", "sessionMessages"),
            ("practice_items", "practiceItems"),
            ("practice_attempts", "practiceAttempts"),
            ("gap_records", "gapRecords"),
            ("review_results", "reviewResults"),
        ):
            row = connection.execute(
                f"SELECT COUNT(*) AS count FROM {table} WHERE workspace_path = ?",
                (workspace_path,),
            ).fetchone()
            if row is None or int(row["count"]) != expected_counts[field]:
                raise BackupRestoreError("恢复后的学习数据数量不一致。")

        orphan_checks = (
            """
            SELECT COUNT(*) AS count
            FROM practice_attempts AS attempt
            LEFT JOIN practice_items AS item
              ON item.workspace_path = attempt.workspace_path
             AND item.id = attempt.practice_item_id
            WHERE attempt.workspace_path = ? AND item.id IS NULL
            """,
            """
            SELECT COUNT(*) AS count
            FROM review_results AS review
            LEFT JOIN gap_records AS gap
              ON gap.workspace_path = review.workspace_path
             AND gap.id = review.gap_id
            WHERE review.workspace_path = ? AND gap.id IS NULL
            """,
            """
            SELECT COUNT(*) AS count
            FROM session_messages AS message
            LEFT JOIN learning_sessions AS session
              ON session.workspace_path = message.workspace_path
             AND session.id = message.session_id
            WHERE message.workspace_path = ? AND session.id IS NULL
            """,
        )
        for query in orphan_checks:
            row = connection.execute(query, (workspace_path,)).fetchone()
            if row is None or int(row["count"]) != 0:
                raise BackupRestoreError("恢复后的学习记录关系无效。")
        connection.commit()
    except Exception as error:
        connection.rollback()
        if isinstance(error, BackupRestoreError):
            raise
        raise BackupRestoreError("恢复失败，当前学习数据已保持不变。") from error
    finally:
        connection.close()


def restore_backup(
    package_bytes: bytes,
    preview_id: str,
    workspace: Path,
) -> dict[str, object]:
    payload, package_sha = _decode_package(package_bytes)
    workspace_path = str(workspace.resolve())
    with _preview_lock:
        _prune_previews()
        preview = _previews.get(preview_id)
    if preview is None:
        raise BackupPreviewError("恢复预览已过期，请重新选择备份包。")
    if preview["workspacePath"] != workspace_path:
        raise BackupPreviewError("当前笔记本工作区已变化，请重新预览。")
    if preview["packageSha256"] != package_sha:
        raise BackupPreviewError("备份包在预览后发生变化，请重新预览。")
    sidecar_review = _sidecar_review(payload, workspace)
    if not sidecar_review["canRestore"] or not preview["canRestore"]:
        raise BackupRestoreError(
            "当前工作区文件与备份校验不一致，无法安全恢复。"
        )
    _restore_transaction(payload, workspace)
    with _preview_lock:
        _previews.pop(preview_id, None)
    return {
        "restored": True,
        "rollback": {
            "path": preview["rollbackPath"],
        },
        "counts": _data_counts(payload),
        "sidecars": sidecar_review,
        "requiresSecretReconfiguration": True,
        "secretMessage": "密钥未包含在备份中，请重新配置或读取 Keychain。",
        "indexesWillRebuild": True,
    }
