from __future__ import annotations

import hashlib
import re
from pathlib import Path
from typing import Iterable, Optional

import fitz

from documents import load_document
from storage import connect


PARSER_VERSION = "fulltext-1"
SUPPORTED_SUFFIXES = {".md", ".pdf"}
TAG_SEPARATOR = "\x1f"
HEADING_RE = re.compile(r"^(#{1,6})\s+(.+?)\s*$")
BODY_TAG_RE = re.compile(r"(?:^|\s)#([\w\u3400-\u9fff-]+)")
INLINE_LINK_RE = re.compile(r"!?\[([^\]]*)\]\(([^)]+)\)")
INLINE_MARKER_RE = re.compile(r"[*_~`]+")


def normalize_text(value: str) -> str:
    return " ".join(value.replace("\x00", " ").split())


def source_hash(file_path: Path) -> str:
    return hashlib.sha256(file_path.read_bytes()).hexdigest()


def source_files(workspace: Path) -> list[Path]:
    files: list[Path] = []
    for candidate in workspace.rglob("*"):
        if any(part.startswith(".") for part in candidate.relative_to(workspace).parts):
            continue
        if candidate.is_file() and candidate.suffix.lower() in SUPPORTED_SUFFIXES:
            files.append(candidate)
    return sorted(files, key=lambda item: item.as_posix().casefold())


def parse_frontmatter(markdown: str) -> tuple[list[str], str]:
    lines = markdown.splitlines()
    if not lines or lines[0].strip() != "---":
        return [], markdown

    end = next(
        (index for index in range(1, len(lines)) if lines[index].strip() in {"---", "..."}),
        None,
    )
    if end is None:
        return [], markdown

    tags: list[str] = []
    active_list: Optional[str] = None
    for line in lines[1:end]:
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if stripped.startswith("- ") and active_list == "tags":
            tag = stripped[2:].strip().strip("\"'")
            if tag:
                tags.append(tag)
            continue
        if ":" not in stripped:
            continue
        key, raw_value = stripped.split(":", 1)
        normalized_key = key.strip().casefold()
        active_list = normalized_key if not raw_value.strip() else None
        if normalized_key not in {"tags", "tag"}:
            continue
        value = raw_value.strip()
        if value.startswith("[") and value.endswith("]"):
            value = value[1:-1]
        if value:
            tags.extend(
                part.strip().strip("\"'")
                for part in value.split(",")
                if part.strip()
            )

    return list(dict.fromkeys(tags)), "\n".join(lines[end + 1 :])


def markdown_blocks(markdown: str) -> list[tuple[str, str, list[str]]]:
    blocks: list[tuple[str, str, list[str]]] = []
    heading_stack: list[tuple[int, str]] = []
    paragraph: list[str] = []
    code_fence: Optional[str] = None
    code_lines: list[str] = []

    def current_heading_path() -> list[str]:
        return [heading for _, heading in heading_stack]

    def flush_paragraph() -> None:
        if not paragraph:
            return
        text = normalize_text(" ".join(paragraph))
        paragraph.clear()
        if text:
            blocks.append(("paragraph", text, current_heading_path()))

    for raw_line in markdown.splitlines():
        stripped = raw_line.strip()
        if code_fence is not None:
            if stripped.startswith(code_fence):
                code_fence = None
                text = normalize_text(" ".join(code_lines))
                code_lines.clear()
                if text:
                    blocks.append(("code", text, current_heading_path()))
            else:
                code_lines.append(raw_line)
            continue

        if stripped.startswith("```") or stripped.startswith("~~~"):
            flush_paragraph()
            code_fence = stripped[:3]
            continue

        heading_match = HEADING_RE.match(stripped)
        if heading_match:
            flush_paragraph()
            level = len(heading_match.group(1))
            heading = normalize_text(heading_match.group(2))
            while heading_stack and heading_stack[-1][0] >= level:
                heading_stack.pop()
            heading_stack.append((level, heading))
            blocks.append(("heading", heading, current_heading_path()))
            continue

        if not stripped:
            flush_paragraph()
            continue

        paragraph.append(stripped)

    flush_paragraph()
    if code_lines:
        text = normalize_text(" ".join(code_lines))
        if text:
            blocks.append(("code", text, current_heading_path()))
    return blocks


def visible_markdown_text(value: str) -> str:
    linked = INLINE_LINK_RE.sub(lambda match: match.group(1), value)
    return normalize_text(INLINE_MARKER_RE.sub("", linked))


def markdown_entries(
    file_path: Path,
    relative_path: str,
    content_hash: str,
) -> list[dict[str, object]]:
    markdown = file_path.read_text(encoding="utf-8")
    frontmatter_tags, body = parse_frontmatter(markdown)
    body_tags = BODY_TAG_RE.findall(body)
    tags = list(dict.fromkeys([*frontmatter_tags, *body_tags]))
    blocks = markdown_blocks(body)
    document = load_document(file_path)
    metadata = document.get("blocks", [])
    if not isinstance(metadata, list):
        metadata = []
    has_canonical_block_ids = document.get("sidecarStatus") == "valid"

    title = file_path.stem
    entries: list[dict[str, object]] = [
        {
            "path": relative_path,
            "kind": "markdown",
            "block_id": None,
            "block_index": None,
            "heading_path": [],
            "page": None,
            "title": title,
            "tags": tags,
            "body": "",
            "content_hash": content_hash,
        }
    ]

    for block_index, (kind, raw_text, heading_path) in enumerate(blocks):
        block_id: Optional[str] = None
        if (
            has_canonical_block_ids
            and block_index < len(metadata)
            and isinstance(metadata[block_index], dict)
        ):
            candidate = metadata[block_index].get("id")
            if isinstance(candidate, str):
                block_id = candidate
        text = visible_markdown_text(raw_text)
        if not text:
            continue
        entries.append(
            {
                "path": relative_path,
                "kind": "markdown",
                "block_id": block_id,
                "block_index": block_index,
                "heading_path": heading_path,
                "page": None,
                "title": title,
                "tags": tags,
                "body": text,
                "content_hash": content_hash,
                "block_kind": kind,
            }
        )
    return entries


def pdf_entries(
    file_path: Path,
    relative_path: str,
    content_hash: str,
) -> list[dict[str, object]]:
    entries: list[dict[str, object]] = []
    try:
        document = fitz.open(stream=file_path.read_bytes(), filetype="pdf")
    except (OSError, RuntimeError, ValueError) as error:
        raise ValueError("无法读取这个 PDF 文件。") from error

    try:
        for page_index, page in enumerate(document):
            text = normalize_text(page.get_text("text", sort=True))
            if not text:
                continue
            entries.append(
                {
                    "path": relative_path,
                    "kind": "pdf",
                    "block_id": None,
                    "block_index": None,
                    "heading_path": [],
                    "page": page_index + 1,
                    "title": file_path.stem,
                    "tags": [],
                    "body": text,
                    "content_hash": content_hash,
                }
            )
    finally:
        document.close()
    return entries


def delete_source_index(connection, workspace: Path, relative_path: str) -> None:
    workspace_path = str(workspace.resolve())
    connection.execute(
        "DELETE FROM search_fts WHERE workspace_path = ? AND path = ?",
        (workspace_path, relative_path),
    )
    connection.execute(
        "DELETE FROM search_sources WHERE workspace_path = ? AND path = ?",
        (workspace_path, relative_path),
    )


def insert_entries(
    connection,
    workspace: Path,
    entries: Iterable[dict[str, object]],
) -> None:
    workspace_path = str(workspace.resolve())
    for entry in entries:
        heading_path = entry.get("heading_path", [])
        tags = entry.get("tags", [])
        connection.execute(
            """
            INSERT INTO search_fts (
                workspace_path,
                path,
                kind,
                block_id,
                block_index,
                heading_path,
                page,
                title,
                path_search,
                tags,
                heading_search,
                body
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                workspace_path,
                entry["path"],
                entry["kind"],
                entry.get("block_id"),
                entry.get("block_index"),
                TAG_SEPARATOR.join(heading_path),
                entry.get("page"),
                entry["title"],
                entry["path"],
                TAG_SEPARATOR.join(tags),
                " ".join(heading_path),
                entry["body"],
            ),
        )


def replace_source(
    connection,
    workspace: Path,
    file_path: Path,
    relative_path: str,
    content_hash: str,
) -> None:
    entries = (
        markdown_entries(file_path, relative_path, content_hash)
        if file_path.suffix.lower() == ".md"
        else pdf_entries(file_path, relative_path, content_hash)
    )
    delete_source_index(connection, workspace, relative_path)
    insert_entries(connection, workspace, entries)
    connection.execute(
        """
        INSERT INTO search_sources (
            workspace_path,
            path,
            kind,
            source_hash,
            parser_version,
            indexed_at,
            error
        )
        VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP, NULL)
        """,
        (
            str(workspace.resolve()),
            relative_path,
            "pdf" if file_path.suffix.lower() == ".pdf" else "markdown",
            content_hash,
            PARSER_VERSION,
        ),
    )


def sync_workspace_index(workspace: Path, *, force: bool = False) -> dict[str, int]:
    root = workspace.resolve()
    files = source_files(root)
    current_paths = {
        file_path.relative_to(root).as_posix() for file_path in files
    }
    stats = {
        "indexedSources": 0,
        "unchangedSources": 0,
        "removedSources": 0,
        "failedSources": 0,
        "totalSources": len(files),
    }

    with connect() as connection:
        rows = connection.execute(
            """
            SELECT path, source_hash, parser_version
            FROM search_sources
            WHERE workspace_path = ?
            """,
            (str(root),),
        ).fetchall()
        existing = {str(row["path"]): row for row in rows}

        for stale_path in sorted(set(existing) - current_paths):
            delete_source_index(connection, root, stale_path)
            stats["removedSources"] += 1

        for file_path in files:
            relative_path = file_path.relative_to(root).as_posix()
            content_hash = source_hash(file_path)
            indexed = existing.get(relative_path)
            if (
                not force
                and indexed is not None
                and indexed["source_hash"] == content_hash
                and indexed["parser_version"] == PARSER_VERSION
            ):
                stats["unchangedSources"] += 1
                continue

            try:
                replace_source(connection, root, file_path, relative_path, content_hash)
            except (OSError, UnicodeDecodeError, ValueError):
                stats["failedSources"] += 1
                if indexed is None:
                    connection.execute(
                        """
                        INSERT OR REPLACE INTO search_sources (
                            workspace_path,
                            path,
                            kind,
                            source_hash,
                            parser_version,
                            indexed_at,
                            error
                        )
                        VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP, ?)
                        """,
                        (
                            str(root),
                            relative_path,
                            "pdf" if file_path.suffix.lower() == ".pdf" else "markdown",
                            content_hash,
                            PARSER_VERSION,
                            "索引失败",
                        ),
                    )
                continue
            stats["indexedSources"] += 1

    return stats


def rebuild_workspace_index(workspace: Path) -> dict[str, int]:
    root = workspace.resolve()
    with connect() as connection:
        connection.execute(
            "DELETE FROM search_fts WHERE workspace_path = ?",
            (str(root),),
        )
        connection.execute(
            "DELETE FROM search_sources WHERE workspace_path = ?",
            (str(root),),
        )
    return sync_workspace_index(root, force=True)


def fts_query(value: str) -> Optional[str]:
    terms = [term for term in normalize_text(value).split(" ") if term]
    if not terms:
        return None
    return " AND ".join(
        f'"{term.replace(chr(34), chr(34) * 2)}"' for term in terms
    )


def matches_query(query: str, *values: str) -> bool:
    normalized = normalize_text(query).casefold()
    return any(normalized in value.casefold() for value in values if value)


def search_workspace(
    workspace: Path,
    query: str,
    *,
    limit: int = 30,
) -> tuple[list[dict[str, object]], dict[str, int]]:
    normalized_query = normalize_text(query)
    stats = sync_workspace_index(workspace)
    if not normalized_query:
        return [], stats

    root = workspace.resolve()
    match_expression = fts_query(normalized_query)
    with connect() as connection:
        rows = []
        if match_expression is not None and len(normalized_query.replace(" ", "")) >= 3:
            try:
                rows = connection.execute(
                    """
                    SELECT
                        rowid AS entry_id,
                        path,
                        kind,
                        block_id,
                        block_index,
                        heading_path,
                        page,
                        title,
                        tags,
                        body,
                        snippet(search_fts, 11, '', '', '…', 28) AS snippet,
                        bm25(search_fts) AS score
                    FROM search_fts
                    WHERE search_fts MATCH ? AND workspace_path = ?
                    ORDER BY score ASC, path ASC, block_index ASC
                    LIMIT ?
                    """,
                    (match_expression, str(root), limit),
                ).fetchall()
            except Exception:
                rows = []

        if not rows:
            like_query = f"%{normalized_query}%"
            rows = connection.execute(
                """
                SELECT
                    rowid AS entry_id,
                    path,
                    kind,
                    block_id,
                    block_index,
                    heading_path,
                    page,
                    title,
                    tags,
                    body,
                    substr(body, 1, 240) AS snippet,
                    0 AS score
                FROM search_fts
                WHERE workspace_path = ?
                  AND (
                    title LIKE ? COLLATE NOCASE
                    OR path_search LIKE ? COLLATE NOCASE
                    OR tags LIKE ? COLLATE NOCASE
                    OR heading_search LIKE ? COLLATE NOCASE
                    OR body LIKE ? COLLATE NOCASE
                  )
                ORDER BY path ASC, block_index ASC
                LIMIT ?
                """,
                (
                    str(root),
                    like_query,
                    like_query,
                    like_query,
                    like_query,
                    like_query,
                    limit,
                ),
            ).fetchall()

    prepared: list[dict[str, object]] = []
    for row in rows:
        tags = [tag for tag in str(row["tags"]).split(TAG_SEPARATOR) if tag]
        heading_path = [
            heading
            for heading in str(row["heading_path"]).split(TAG_SEPARATOR)
            if heading
        ]
        body = str(row["body"] or "")
        title = str(row["title"] or "")
        path_value = str(row["path"])
        matched_fields: list[str] = []
        if matches_query(normalized_query, title):
            matched_fields.append("title")
        if matches_query(normalized_query, path_value):
            matched_fields.append("path")
        if matches_query(normalized_query, *tags):
            matched_fields.append("tag")
        if matches_query(normalized_query, *heading_path):
            matched_fields.append("heading")
        if matches_query(normalized_query, body):
            matched_fields.append("body")

        prepared.append(
            {
                "row": row,
                "body": body,
                "heading_path": heading_path,
                "matched_fields": matched_fields,
                "path": path_value,
                "tags": tags,
                "title": title,
            }
        )

    metadata_paths = {
        str(item["path"])
        for item in prepared
        if any(
            field in {"title", "path", "tag"}
            for field in item["matched_fields"]
        )
    }
    metadata_page_rows: dict[str, dict[str, object]] = {}
    for item in prepared:
        if str(item["path"]) not in metadata_paths:
            continue
        row = item["row"]
        if row["block_index"] is None and row["page"] is None:
            metadata_page_rows[str(item["path"])] = item

    results: list[dict[str, object]] = []
    seen: set[str] = set()
    emitted_metadata_paths: set[str] = set()
    chunk_counts: dict[str, int] = {}
    for item in prepared:
        row = item["row"]
        path_value = str(item["path"])
        if path_value in metadata_paths:
            if path_value in emitted_metadata_paths:
                continue
            selected = metadata_page_rows.get(path_value, item)
            item = selected
            row = item["row"]
            emitted_metadata_paths.add(path_value)

        chunk_count = chunk_counts.get(path_value, 0)
        if path_value not in metadata_paths and chunk_count >= 3:
            continue

        body = str(item["body"])
        title = str(item["title"])
        tags = item["tags"]
        heading_path = item["heading_path"]
        matched_fields = item["matched_fields"]
        result_id = ":".join(
            [
                path_value,
                str(row["block_id"] or ""),
                str(row["page"] or ""),
            ]
        )
        if result_id in seen:
            continue
        seen.add(result_id)
        chunk_counts[path_value] = chunk_count + 1

        if matched_fields:
            primary_match = matched_fields[0]
        else:
            primary_match = "pdf" if row["kind"] == "pdf" else "body"
        snippet_value = normalize_text(str(row["snippet"] or ""))
        if not snippet_value:
            snippet_value = body[:240]
        results.append(
            {
                "id": result_id,
                "path": path_value,
                "kind": row["kind"],
                "title": title,
                "headingPath": heading_path,
                "blockId": row["block_id"],
                "blockIndex": row["block_index"],
                "page": row["page"],
                "tags": tags,
                "snippet": snippet_value,
                "matchedIn": primary_match,
            }
        )
    return results, stats
