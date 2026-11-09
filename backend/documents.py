from __future__ import annotations

from contextlib import contextmanager
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import tempfile
import threading
from typing import Iterator


SIDECAR_SCHEMA_VERSION = 1
MAX_SIDECAR_BYTES = 4 * 1024 * 1024
MAX_BLOCKS = 10_000

_locks_guard = threading.Lock()
_document_locks: dict[Path, threading.RLock] = {}


class DocumentConflictError(Exception):
    def __init__(self, document: dict[str, object]):
        super().__init__("The Markdown document changed on disk.")
        self.document = document


def markdown_sha256(content: str) -> str:
    return hashlib.sha256(content.encode("utf-8")).hexdigest()


def sidecar_path_for(file_path: Path) -> Path:
    return Path(f"{file_path}.note.json")


@contextmanager
def document_lock(file_path: Path) -> Iterator[None]:
    resolved = file_path.resolve()
    with _locks_guard:
        lock = _document_locks.setdefault(resolved, threading.RLock())

    with lock:
        yield


def read_markdown(file_path: Path) -> str:
    try:
        return file_path.read_text(encoding="utf-8")
    except UnicodeDecodeError as error:
        raise ValueError("Markdown 文件不是 UTF-8 编码。") from error


def atomic_write_text(file_path: Path, content: str) -> None:
    file_path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{file_path.name}.",
        suffix=".tmp",
        dir=file_path.parent,
    )
    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="") as handle:
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


def backup_sidecar(file_path: Path) -> Path | None:
    sidecar_path = sidecar_path_for(file_path)
    if not sidecar_path.exists():
        return None

    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    backup_path = Path(f"{sidecar_path}.corrupt-{timestamp}")
    index = 1
    while backup_path.exists():
        backup_path = Path(f"{sidecar_path}.corrupt-{timestamp}-{index}")
        index += 1

    sidecar_path.replace(backup_path)
    return backup_path


def validate_blocks(
    blocks: object,
    *,
    depth: int = 0,
    counter: list[int] | None = None,
) -> list[dict[str, object]]:
    if depth > 12:
        raise ValueError("sidecar 块嵌套过深。")
    if not isinstance(blocks, list):
        raise ValueError("sidecar blocks 必须是数组。")

    if counter is None:
        counter = [0]

    validated: list[dict[str, object]] = []
    for raw_block in blocks:
        counter[0] += 1
        if counter[0] > MAX_BLOCKS:
            raise ValueError("sidecar 块数量超过限制。")
        if not isinstance(raw_block, dict):
            raise ValueError("sidecar block 必须是对象。")

        block_id = raw_block.get("id")
        block_type = raw_block.get("type")
        props = raw_block.get("props", {})
        children = raw_block.get("children", [])
        layout = raw_block.get("layout")
        custom = raw_block.get("custom", {})

        if not isinstance(block_id, str) or not block_id or len(block_id) > 160:
            raise ValueError("sidecar block id 无效。")
        if not isinstance(block_type, str) or not block_type or len(block_type) > 80:
            raise ValueError("sidecar block type 无效。")
        if not isinstance(props, dict):
            raise ValueError("sidecar block props 无效。")
        if not isinstance(custom, dict):
            raise ValueError("sidecar block custom 无效。")

        block: dict[str, object] = {
            "id": block_id,
            "type": block_type,
            "props": props,
            "children": validate_blocks(
                children,
                depth=depth + 1,
                counter=counter,
            ),
        }
        if layout is not None:
            block["layout"] = layout
        if custom:
            block["custom"] = custom
        validated.append(block)

    return validated


def serialize_sidecar(file_path: Path, markdown: str, blocks: object) -> str:
    validated_blocks = validate_blocks(blocks)
    sidecar = {
        "schemaVersion": SIDECAR_SCHEMA_VERSION,
        "sourceMarkdownSha256": markdown_sha256(markdown),
        "savedAt": datetime.now(timezone.utc).isoformat(),
        "blocks": validated_blocks,
    }
    content = json.dumps(sidecar, ensure_ascii=False, indent=2) + "\n"
    if len(content.encode("utf-8")) > MAX_SIDECAR_BYTES:
        raise ValueError("sidecar 超过 4 MB 限制。")
    return content


def rebuild_blocks(file_path: Path) -> list[dict[str, object]]:
    markdown = read_markdown(file_path)
    if not markdown.strip():
        return []

    blocks: list[dict[str, object]] = []
    for line in markdown.splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.startswith("# "):
            block_type = "heading"
            props: dict[str, object] = {"level": 1}
        elif stripped.startswith("## "):
            block_type = "heading"
            props = {"level": 2}
        elif stripped.startswith("### "):
            block_type = "heading"
            props = {"level": 3}
        elif stripped.startswith(("> ", "- ", "* ", "+ ")) or stripped[:2].isdigit():
            block_type = "paragraph"
            props = {}
        else:
            block_type = "paragraph"
            props = {}
        blocks.append(
            {
                "id": hashlib.sha1(  # noqa: S324 - deterministic local block id
                    f"{len(blocks)}:{stripped}".encode("utf-8")
                ).hexdigest()[:12],
                "type": block_type,
                "props": props,
                "children": [],
            }
        )
    return blocks


def load_document(file_path: Path) -> dict[str, object]:
    markdown = read_markdown(file_path)
    revision = markdown_sha256(markdown)
    sidecar_path = sidecar_path_for(file_path)
    sidecar_status = "valid"
    blocks: list[dict[str, object]] = []
    backup_path: str | None = None

    if not sidecar_path.exists():
        sidecar_status = "missing"
        blocks = rebuild_blocks(file_path)
    else:
        try:
            sidecar_bytes = sidecar_path.read_bytes()
            if len(sidecar_bytes) > MAX_SIDECAR_BYTES:
                raise ValueError("sidecar 超过 4 MB 限制。")
            sidecar = json.loads(sidecar_bytes.decode("utf-8"))
            if not isinstance(sidecar, dict):
                raise ValueError("sidecar 必须是 JSON 对象。")
            if sidecar.get("schemaVersion") != SIDECAR_SCHEMA_VERSION:
                raise ValueError("sidecar schemaVersion 不受支持。")
            if sidecar.get("sourceMarkdownSha256") != revision:
                raise ValueError("sidecar 与 Markdown 哈希不一致。")
            blocks = validate_blocks(sidecar.get("blocks"))
        except (OSError, UnicodeDecodeError, json.JSONDecodeError, ValueError):
            sidecar_status = "rebuilt"
            backup = backup_sidecar(file_path)
            backup_path = str(backup) if backup is not None else None
            blocks = rebuild_blocks(file_path)

    return {
        "content": markdown,
        "revision": revision,
        "blocks": blocks,
        "sidecarStatus": sidecar_status,
        "sidecarBackupPath": backup_path,
    }


def save_document(
    file_path: Path,
    content: str,
    blocks: object,
    expected_revision: str,
) -> dict[str, object]:
    sidecar_content = serialize_sidecar(file_path, content, blocks)

    with document_lock(file_path):
        current_markdown = read_markdown(file_path)
        current_revision = markdown_sha256(current_markdown)
        if current_revision != expected_revision:
            raise DocumentConflictError(load_document(file_path))

        atomic_write_text(file_path, content)
        atomic_write_text(sidecar_path_for(file_path), sidecar_content)
        revision = markdown_sha256(content)

    return {
        "content": content,
        "revision": revision,
        "blocks": validate_blocks(blocks),
        "sidecarStatus": "valid",
        "sidecarBackupPath": None,
    }
