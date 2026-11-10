from __future__ import annotations

import json
import math
from pathlib import Path
from typing import Optional

from model_client import EmbeddingConfig, request_embeddings
from search_index import TAG_SEPARATOR, normalize_text, search_workspace, sync_workspace_index
from storage import connect


EMBEDDING_BATCH_SIZE = 24
MAX_EMBEDDING_CHARACTERS = 8_000
MIN_SEMANTIC_SCORE = 0.1


def _entry_key(row: dict[str, object]) -> str:
    block_index = row.get("block_index")
    return ":".join(
        [
            str(row["path"]),
            str(row.get("block_id") or ""),
            str(row.get("page") or ""),
            str(block_index if block_index is not None else ""),
        ]
    )


def _index_rows(workspace: Path) -> list[dict[str, object]]:
    with connect() as connection:
        rows = connection.execute(
            """
            SELECT
                search.path,
                search.kind,
                search.block_id,
                search.block_index,
                search.heading_path,
                search.page,
                search.title,
                search.tags,
                search.body,
                sources.source_hash AS content_hash
            FROM search_fts AS search
            JOIN search_sources AS sources
              ON sources.workspace_path = search.workspace_path
             AND sources.path = search.path
            WHERE search.workspace_path = ?
              AND length(trim(search.body)) > 0
            ORDER BY search.path ASC, search.page ASC, search.block_index ASC
            """,
            (str(workspace.resolve()),),
        ).fetchall()
    return [dict(row) for row in rows]


def _embedding_text(row: dict[str, object]) -> str:
    heading_path = str(row.get("heading_path") or "").split(TAG_SEPARATOR)
    return normalize_text(
        " ".join(
            [
                str(row.get("title") or ""),
                *[heading for heading in heading_path if heading],
                str(row.get("body") or ""),
            ]
        )
    )[:MAX_EMBEDDING_CHARACTERS]


def sync_embedding_index(
    workspace: Path,
    config: EmbeddingConfig,
) -> dict[str, int]:
    fulltext_stats = sync_workspace_index(workspace)
    rows = _index_rows(workspace)
    rows_by_key = {_entry_key(row): row for row in rows}
    workspace_path = str(workspace.resolve())

    with connect() as connection:
        connection.execute(
            """
            DELETE FROM embedding_entries
            WHERE workspace_path = ? AND embedding_model <> ?
            """,
            (workspace_path, config.model),
        )
        existing_rows = connection.execute(
            """
            SELECT entry_key, content_hash
            FROM embedding_entries
            WHERE workspace_path = ? AND embedding_model = ?
            """,
            (workspace_path, config.model),
        ).fetchall()
        existing = {
            str(row["entry_key"]): str(row["content_hash"])
            for row in existing_rows
        }

        stale_keys = sorted(set(existing) - set(rows_by_key))
        if stale_keys:
            connection.executemany(
                """
                DELETE FROM embedding_entries
                WHERE workspace_path = ? AND entry_key = ?
                """,
                [(workspace_path, entry_key) for entry_key in stale_keys],
            )

        pending = [
            row
            for key, row in rows_by_key.items()
            if existing.get(key) != str(row["content_hash"])
        ]
        for start in range(0, len(pending), EMBEDDING_BATCH_SIZE):
            batch = pending[start : start + EMBEDDING_BATCH_SIZE]
            vectors = request_embeddings(
                config,
                [_embedding_text(row) for row in batch],
            )
            connection.executemany(
                """
                INSERT INTO embedding_entries (
                    workspace_path,
                    entry_key,
                    path,
                    kind,
                    block_id,
                    block_index,
                    heading_path,
                    page,
                    title,
                    tags,
                    body,
                    content_hash,
                    embedding_model,
                    embedding_json,
                    indexed_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
                ON CONFLICT(workspace_path, entry_key) DO UPDATE SET
                    path = excluded.path,
                    kind = excluded.kind,
                    block_id = excluded.block_id,
                    block_index = excluded.block_index,
                    heading_path = excluded.heading_path,
                    page = excluded.page,
                    title = excluded.title,
                    tags = excluded.tags,
                    body = excluded.body,
                    content_hash = excluded.content_hash,
                    embedding_model = excluded.embedding_model,
                    embedding_json = excluded.embedding_json,
                    indexed_at = CURRENT_TIMESTAMP
                """,
                [
                    (
                        workspace_path,
                        _entry_key(row),
                        row["path"],
                        row["kind"],
                        row.get("block_id"),
                        row.get("block_index"),
                        row.get("heading_path"),
                        row.get("page"),
                        row["title"],
                        row.get("tags"),
                        row["body"],
                        row["content_hash"],
                        config.model,
                        json.dumps(vector),
                    )
                    for row, vector in zip(batch, vectors)
                ],
            )

    return {
        **fulltext_stats,
        "embeddedChunks": len(rows),
        "updatedEmbeddings": len(pending),
        "unchangedEmbeddings": len(rows) - len(pending),
    }


def _cosine_similarity(left: list[float], right: list[float]) -> float:
    if len(left) != len(right) or not left:
        return 0.0
    dot_product = sum(a * b for a, b in zip(left, right))
    left_norm = math.sqrt(sum(value * value for value in left))
    right_norm = math.sqrt(sum(value * value for value in right))
    if left_norm == 0 or right_norm == 0:
        return 0.0
    return dot_product / (left_norm * right_norm)


def _semantic_result(row: dict[str, object]) -> dict[str, object]:
    body = str(row.get("body") or "")
    block_id = row.get("block_id")
    page = row.get("page")
    block_index = row.get("block_index")
    return {
        "id": ":".join(
            [
                str(row["path"]),
                str(block_id or ""),
                str(page or ""),
                str(block_index if block_index is not None else ""),
            ]
        ),
        "path": str(row["path"]),
        "kind": str(row["kind"]),
        "title": str(row["title"]),
        "headingPath": [
            heading
            for heading in str(row.get("heading_path") or "").split(TAG_SEPARATOR)
            if heading
        ],
        "blockId": block_id,
        "blockIndex": block_index,
        "page": page,
        "tags": [
            tag
            for tag in str(row.get("tags") or "").split(TAG_SEPARATOR)
            if tag
        ],
        "snippet": normalize_text(body)[:240],
        "matchedIn": "semantic",
    }


def semantic_search_workspace(
    workspace: Path,
    query: str,
    config: EmbeddingConfig,
    *,
    limit: int = 12,
) -> tuple[list[dict[str, object]], dict[str, int]]:
    stats = sync_embedding_index(workspace, config)
    query_vector = request_embeddings(config, [query])[0]
    with connect() as connection:
        rows = connection.execute(
            """
            SELECT *
            FROM embedding_entries
            WHERE workspace_path = ? AND embedding_model = ?
            """,
            (str(workspace.resolve()), config.model),
        ).fetchall()

    scored: list[tuple[float, dict[str, object]]] = []
    for raw_row in rows:
        row = dict(raw_row)
        try:
            vector = [float(value) for value in json.loads(row["embedding_json"])]
        except (json.JSONDecodeError, TypeError, ValueError):
            continue
        if len(query_vector) != len(vector):
            raise ValueError("向量模型向量维度与本地索引不一致。")
        score = _cosine_similarity(query_vector, vector)
        if score >= MIN_SEMANTIC_SCORE:
            scored.append((score, row))

    scored.sort(
        key=lambda item: (
            -item[0],
            str(item[1]["path"]),
            str(item[1].get("page") or ""),
            str(item[1].get("block_index") or ""),
        )
    )
    return [_semantic_result(row) for _, row in scored[:limit]], stats


def _result_identity(result: dict[str, object]) -> tuple[str, str, str, str]:
    return (
        str(result.get("path") or ""),
        str(result.get("blockId") or ""),
        str(result.get("page") or ""),
        str(result.get("blockIndex") if result.get("blockIndex") is not None else ""),
    )


def retrieve_tutor_sources(
    workspace: Path,
    query: str,
    config: Optional[EmbeddingConfig],
    *,
    limit: int = 12,
) -> tuple[list[dict[str, object]], dict[str, object], dict[str, int]]:
    fulltext_results, fulltext_stats = search_workspace(
        workspace,
        query,
        limit=limit,
    )
    if config is None:
        return (
            fulltext_results,
            {
                "mode": "fulltext",
                "label": "全文检索",
                "fallback": False,
                "reason": None,
            },
            fulltext_stats,
        )

    try:
        semantic_results, semantic_stats = semantic_search_workspace(
            workspace,
            query,
            config,
            limit=limit,
        )
    except Exception:
        return (
            fulltext_results,
            {
                "mode": "fulltext",
                "label": "全文检索（已降级）",
                "fallback": True,
                "reason": "向量模型检索不可用，已自动回退全文检索。",
            },
            fulltext_stats,
        )

    combined: list[dict[str, object]] = []
    seen: set[tuple[str, str, str, str]] = set()
    for result in [*semantic_results, *fulltext_results]:
        identity = _result_identity(result)
        if identity in seen:
            continue
        seen.add(identity)
        combined.append(result)
        if len(combined) >= limit:
            break
    return (
        combined,
        {
            "mode": "semantic",
            "label": "语义检索",
            "fallback": False,
            "reason": None,
        },
        semantic_stats,
    )
