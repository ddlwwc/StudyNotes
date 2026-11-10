from __future__ import annotations

import hashlib
import json
import posixpath
import re
from pathlib import Path
from typing import Iterator, Optional

import fitz

from documents import load_document
from model_client import (
    ModelConfig,
    ModelRequestError,
    stream_chat_completion,
)
from search_index import normalize_text, search_workspace, sync_workspace_index
from storage import connect, save_session_message


ALLOWED_ANSWER_TYPES = {
    "grounded",
    "insufficient_evidence",
    "unsupported_supplement",
}
JSON_FENCE_RE = re.compile(r"^```(?:json)?\s*|\s*```$", re.IGNORECASE)
TOKEN_RE = re.compile(r"[\w\u3400-\u9fff-]+")
MAX_CONTEXT_CHUNKS = 6
MAX_CONTEXT_CHARACTERS = 12_000


class TutorContextError(Exception):
    pass


def normalize_source_path(value: str) -> str:
    normalized = posixpath.normpath(value.strip().replace("\\", "/"))
    if (
        not normalized
        or normalized in {".", ".."}
        or normalized.startswith("/")
        or normalized.startswith("../")
    ):
        raise TutorContextError("Learning source 路径无效。")
    return normalized


def source_key(
    kind: str,
    relative_path: str,
    *,
    block_id: Optional[str],
    block_index: Optional[int],
    page: Optional[int],
    quote: str,
) -> str:
    position = (
        f"block:{block_id or ''}:{block_index if block_index is not None else ''}"
        if kind == "markdown"
        else f"page:{page if page is not None else ''}"
    )
    value = "\x1f".join(
        [
            normalize_source_path(relative_path),
            kind,
            position,
            normalize_text(quote),
        ]
    )
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _workspace_file(workspace: Path, relative_path: str) -> Path:
    normalized = normalize_source_path(relative_path)
    root = workspace.resolve()
    candidate = (root / normalized).resolve()
    try:
        candidate.relative_to(root)
    except ValueError as error:
        raise TutorContextError("Learning source 路径无效。") from error
    if not candidate.is_file() or candidate.suffix.lower() not in {".md", ".pdf"}:
        raise TutorContextError("Learning source 不存在。")
    return candidate


def _heading_path(value: object) -> list[str]:
    if isinstance(value, list):
        return [str(item) for item in value if str(item)]
    return [part for part in str(value or "").split("\x1f") if part]


def _load_markdown_block(
    workspace: Path,
    relative_path: str,
    block_id: Optional[str],
    quote: str,
) -> dict[str, object]:
    sync_workspace_index(workspace)
    parameters: list[object] = [str(workspace.resolve()), relative_path]
    block_filter = ""
    if block_id:
        block_filter = " AND block_id = ?"
        parameters.append(block_id)
    with connect() as connection:
        rows = connection.execute(
            f"""
            SELECT
                block_id,
                block_index,
                heading_path,
                title,
                body
            FROM search_fts
            WHERE workspace_path = ?
              AND path = ?
              AND kind = 'markdown'
              {block_filter}
            ORDER BY block_index ASC
            """,
            parameters,
        ).fetchall()
        if not rows and block_id:
            rows = connection.execute(
                """
                SELECT
                    block_id,
                    block_index,
                    heading_path,
                    title,
                    body
                FROM search_fts
                WHERE workspace_path = ?
                  AND path = ?
                  AND kind = 'markdown'
                ORDER BY block_index ASC
                """,
                (str(workspace.resolve()), relative_path),
            ).fetchall()

    normalized_quote = normalize_text(quote)
    matching = next(
        (
            candidate
            for candidate in rows
            if not normalized_quote
            or normalized_quote in normalize_text(str(candidate["body"]))
        ),
        None,
    )
    if matching is None:
        raise TutorContextError("选中的 Markdown 片段不属于当前页面。")

    body = normalize_text(str(matching["body"]))
    selected_quote = normalized_quote or body
    if selected_quote not in body:
        raise TutorContextError("选区内容已变化，请重新选择 Markdown 块。")
    return {
        "kind": "markdown",
        "blockId": matching["block_id"],
        "blockIndex": matching["block_index"],
        "page": None,
        "headingPath": _heading_path(matching["heading_path"]),
        "path": relative_path,
        "text": body,
        "title": str(matching["title"]),
        "quote": selected_quote,
        "wholeFile": False,
    }


def _load_pdf_source(
    file_path: Path,
    relative_path: str,
    page: Optional[int],
    quote: str,
) -> dict[str, object]:
    try:
        document = fitz.open(stream=file_path.read_bytes(), filetype="pdf")
    except (OSError, RuntimeError, ValueError) as error:
        raise TutorContextError("无法读取这个 PDF 文件。") from error

    normalized_quote = normalize_text(quote)
    try:
        selected_page = page
        if selected_page is None and normalized_quote:
            selected_page = next(
                (
                    index + 1
                    for index, candidate in enumerate(document)
                    if normalized_quote
                    in normalize_text(candidate.get_text("text", sort=True))
                ),
                None,
            )
        if selected_page is not None:
            if selected_page < 1 or selected_page > document.page_count:
                raise TutorContextError("PDF 页码超出范围。")
            text = normalize_text(
                document[selected_page - 1].get_text("text", sort=True)
            )
            if not text:
                raise TutorContextError("当前页没有可提取文本。")
            if not normalized_quote:
                normalized_quote = text
            if normalized_quote not in text:
                raise TutorContextError("选中的文本不属于当前 PDF 页面。")

        return {
            "kind": "pdf",
            "blockId": None,
            "blockIndex": None,
            "page": selected_page,
            "headingPath": [],
            "path": relative_path,
            "text": text if selected_page is not None else "",
            "title": file_path.stem,
            "quote": normalized_quote,
            "wholeFile": selected_page is None,
        }
    finally:
        document.close()


def resolve_tutor_source(
    workspace: Path,
    relative_path: str,
    block_id: Optional[str] = None,
    page: Optional[int] = None,
    quote: str = "",
) -> dict[str, object]:
    normalized_path = normalize_source_path(relative_path)
    file_path = _workspace_file(workspace, normalized_path)
    if file_path.suffix.lower() == ".pdf":
        source = _load_pdf_source(file_path, normalized_path, page, quote)
    else:
        if block_id or normalize_text(quote):
            source = _load_markdown_block(
                workspace,
                normalized_path,
                block_id,
                quote,
            )
        else:
            document = load_document(file_path)
            source = {
                "kind": "markdown",
                "blockId": None,
                "blockIndex": None,
                "page": None,
                "headingPath": [],
                "path": normalized_path,
                "text": "",
                "title": str(document["title"]),
                "quote": "",
                "wholeFile": True,
            }
    source["sourceKey"] = source_key(
        str(source["kind"]),
        normalized_path,
        block_id=source.get("blockId"),  # type: ignore[arg-type]
        block_index=source.get("blockIndex"),  # type: ignore[arg-type]
        page=source.get("page"),  # type: ignore[arg-type]
        quote=str(source.get("quote", "")),
    )
    return source


def bind_tutor_selection(
    workspace: Path,
    relative_path: str,
    block_id: Optional[str],
    quote: str,
    page: Optional[int] = None,
) -> dict[str, object]:
    return resolve_tutor_source(
        workspace,
        relative_path,
        block_id=block_id,
        page=page,
        quote=quote,
    )


def _row_source(row: dict[str, object]) -> dict[str, object]:
    return {
        "id": row.get("id"),
        "kind": row["kind"],
        "path": row["path"],
        "blockId": row.get("block_id"),
        "blockIndex": row.get("block_index"),
        "page": row.get("page"),
        "headingPath": _heading_path(row.get("heading_path_json")),
        "quote": row.get("quote", ""),
        "isInitial": bool(row.get("is_initial")),
    }


def _query_rows_for_path(
    workspace: Path,
    relative_path: str,
) -> list[dict[str, object]]:
    with connect() as connection:
        rows = connection.execute(
            """
            SELECT
                path,
                kind,
                block_id,
                block_index,
                heading_path,
                page,
                title,
                body
            FROM search_fts
            WHERE workspace_path = ? AND path = ?
            ORDER BY
                CASE WHEN page IS NULL THEN block_index ELSE page END ASC
            """,
            (str(workspace.resolve()), relative_path),
        ).fetchall()
    return [dict(row) for row in rows]


def _row_chunk(
    row: dict[str, object],
    *,
    origin: str,
    priority: int,
) -> Optional[dict[str, object]]:
    text = normalize_text(str(row.get("body", "")))
    if not text:
        return None
    kind = str(row["kind"])
    return {
        "kind": kind,
        "path": str(row["path"]),
        "blockId": row.get("block_id"),
        "blockIndex": row.get("block_index"),
        "page": row.get("page"),
        "headingPath": _heading_path(row.get("heading_path")),
        "title": str(row.get("title", "")),
        "quote": text[:240],
        "text": text,
        "origin": origin,
        "priority": priority,
    }


def _question_score(text: str, question: str) -> int:
    normalized = text.casefold()
    tokens = [
        token.casefold()
        for token in TOKEN_RE.findall(normalize_text(question))
        if token.strip()
    ]
    return sum(normalized.count(token) for token in tokens)


def _chunks_for_source(
    workspace: Path,
    source_row: dict[str, object],
    question: str,
    *,
    priority: int,
) -> list[dict[str, object]]:
    stored = _row_source(source_row)
    origin = "selected" if stored["isInitial"] else "pinned"
    resolved = resolve_tutor_source(
        workspace,
        str(stored["path"]),
        block_id=stored.get("blockId"),  # type: ignore[arg-type]
        page=stored.get("page"),  # type: ignore[arg-type]
        quote=str(stored.get("quote", "")),
    )
    if not resolved.get("wholeFile"):
        return [
            {
                **resolved,
                "origin": origin,
                "priority": priority,
            }
        ]

    sync_workspace_index(workspace)
    rows = _query_rows_for_path(workspace, str(stored["path"]))
    chunks = [
        chunk
        for row in rows
        if (chunk := _row_chunk(row, origin=origin, priority=priority))
        is not None
    ]
    chunks.sort(
        key=lambda chunk: (
            -_question_score(str(chunk["text"]), question),
            int(chunk.get("page") or chunk.get("blockIndex") or 0),
        )
    )
    return chunks


def _chunk_key(chunk: dict[str, object]) -> str:
    return source_key(
        str(chunk["kind"]),
        str(chunk["path"]),
        block_id=chunk.get("blockId"),  # type: ignore[arg-type]
        block_index=chunk.get("blockIndex"),  # type: ignore[arg-type]
        page=chunk.get("page"),  # type: ignore[arg-type]
        quote=str(chunk.get("quote", "")),
    )


def build_tutor_context(
    workspace: Path,
    session: dict[str, object],
    sources: list[dict[str, object]],
    question: str,
) -> dict[str, object]:
    sync_workspace_index(workspace)
    active_sources = sources
    if not active_sources:
        selected = resolve_tutor_source(
            workspace,
            str(session["path"]),
            block_id=session.get("block_id"),  # type: ignore[arg-type]
            page=session.get("page"),  # type: ignore[arg-type]
            quote=str(session["quote"]),
        )
        active_sources = [
            {
                "id": "legacy",
                "kind": selected["kind"],
                "path": selected["path"],
                "block_id": selected.get("blockId"),
                "block_index": selected.get("blockIndex"),
                "page": selected.get("page"),
                "heading_path_json": json.dumps(
                    selected.get("headingPath", []),
                    ensure_ascii=False,
                ),
                "quote": selected.get("quote", ""),
                "is_initial": 1,
            }
        ]

    candidates: list[dict[str, object]] = []
    for source_row in active_sources:
        candidates.extend(
            _chunks_for_source(
                workspace,
                source_row,
                question,
                priority=0 if source_row.get("is_initial") else 1,
            )
        )

    results, _ = search_workspace(workspace, question, limit=20)
    for result in results:
        text = normalize_text(str(result.get("snippet", "")))
        if not text:
            continue
        candidates.append(
            {
                "kind": result["kind"],
                "path": result["path"],
                "blockId": result.get("blockId"),
                "blockIndex": result.get("blockIndex"),
                "page": result.get("page"),
                "headingPath": result.get("headingPath", []),
                "title": result["title"],
                "quote": text,
                "text": text,
                "origin": "retrieved",
                "priority": 2,
            }
        )

    candidates.sort(key=lambda chunk: int(chunk.get("priority", 2)))
    chunks: list[dict[str, object]] = []
    omitted: list[dict[str, object]] = []
    seen: set[str] = set()
    character_count = 0
    deduplicated_count = 0
    truncated = False

    for candidate in candidates:
        key = _chunk_key(candidate)
        if key in seen:
            deduplicated_count += 1
            continue
        seen.add(key)
        text = str(candidate["text"])
        if (
            len(chunks) >= MAX_CONTEXT_CHUNKS
            or character_count + len(text) > MAX_CONTEXT_CHARACTERS
        ):
            if not chunks and int(candidate.get("priority", 2)) == 0:
                candidate = dict(candidate)
                candidate["text"] = text[:MAX_CONTEXT_CHARACTERS]
                candidate["quote"] = str(candidate["quote"])[:240]
                truncated = True
                text = str(candidate["text"])
            else:
                omitted.append(
                    {
                        "kind": candidate["kind"],
                        "path": candidate["path"],
                        "blockId": candidate.get("blockId"),
                        "page": candidate.get("page"),
                        "quote": str(candidate.get("quote", ""))[:240],
                        "reason": (
                            "fragment_limit"
                            if len(chunks) >= MAX_CONTEXT_CHUNKS
                            else "character_limit"
                        ),
                        "origin": candidate["origin"],
                    }
                )
                continue
        if not text:
            continue
        chunk = dict(candidate)
        chunk["sourceId"] = f"S{len(chunks) + 1}"
        chunk["text"] = text
        chunks.append(chunk)
        character_count += len(text)

    initial_source = _row_source(active_sources[0])
    selected_chunk = next(
        (chunk for chunk in chunks if chunk["origin"] == "selected"),
        chunks[0] if chunks else None,
    )
    selection = (
        {
            "kind": selected_chunk["kind"],
            "path": initial_source["path"],
            "blockId": initial_source.get("blockId"),
            "blockIndex": initial_source.get("blockIndex"),
            "page": initial_source.get("page"),
            "headingPath": initial_source["headingPath"],
            "quote": initial_source.get("quote", ""),
        }
        if selected_chunk
        else {
            "kind": initial_source["kind"],
            "path": initial_source["path"],
            "blockId": initial_source.get("blockId"),
            "blockIndex": initial_source.get("blockIndex"),
            "page": initial_source.get("page"),
            "headingPath": initial_source["headingPath"],
            "quote": initial_source.get("quote", ""),
        }
    )
    first_chunk = chunks[0] if chunks else None
    return {
        "selection": selection,
        "sources": [_row_source(source) for source in active_sources],
        "retrieved": [
            {
                "sourceId": chunk["sourceId"],
                "kind": chunk["kind"],
                "path": chunk["path"],
                "blockId": chunk.get("blockId"),
                "page": chunk.get("page"),
                "headingPath": chunk["headingPath"],
                "quote": chunk["quote"],
                "origin": chunk["origin"],
            }
            for chunk in chunks
            if chunk is not first_chunk
        ],
        "sent": {
            "sourceCount": len(chunks),
            "characterCount": character_count,
            "revision": (
                str(load_document(workspace / str(initial_source["path"])).get("revision"))
                if initial_source["kind"] == "markdown"
                else ""
            ),
            "chunks": chunks,
        },
        "budget": {
            "maxChunks": MAX_CONTEXT_CHUNKS,
            "maxCharacters": MAX_CONTEXT_CHARACTERS,
            "candidateCount": len(candidates),
            "deduplicatedCount": deduplicated_count,
            "omittedCount": len(omitted),
            "truncated": truncated,
        },
        "omitted": omitted,
    }


def tutor_messages(
    context: dict[str, object],
    question: str,
    mode: str,
    supplement_requested: bool,
    retry_note: Optional[str] = None,
) -> list[dict[str, str]]:
    mode_instruction = (
        "采用引导式辅导：先帮助学习者观察资料、提出追问，不直接替对方完成全部理解。"
        if mode == "guided"
        else "学习者要求直接解释：结论要清楚直接，但仍以资料为主要依据。"
    )
    supplement_instruction = (
        "用户已明确请求非资料补充。可以返回 unsupported_supplement，但必须说明不来自 Learning source。"
        if supplement_requested
        else "用户没有请求非资料补充。禁止返回 unsupported_supplement。"
    )
    system = (
        "你是 StudyNotes 的 Grounded tutor。你只能把给定 Learning source 支持的内容"
        "呈现为 grounded answer。资料不足时必须返回 insufficient_evidence 并说明缺口。"
        f"{mode_instruction}{supplement_instruction}"
        "只返回一个 JSON 对象，不要使用 Markdown 代码围栏。结构必须是："
        '{"type":"grounded|insufficient_evidence|unsupported_supplement",'
        '"answer":"简体中文回答","citations":[{"source_id":"S1","quote":"原文片段"}],'
        '"missing":["资料缺口"]}。'
        "grounded 的每个关键结论都要有至少一个 citation；source_id 只能使用上下文中的值，"
        "quote 必须逐字或规范化空白后出现在对应来源中。答案中的来源标记可写成 [S1]。"
    )
    context_json = json.dumps(context["sent"], ensure_ascii=False)
    messages = [
        {"role": "system", "content": system},
        {
            "role": "user",
            "content": f"Learning source 上下文：\n{context_json}\n\n问题：{question}",
        },
    ]
    if retry_note:
        messages.append(
            {
                "role": "user",
                "content": (
                    "上一次回答未通过引用验证："
                    f"{retry_note}。请只使用上下文中的有效 source_id 和原文重答。"
                ),
            }
        )
    return messages


def parse_answer_json(raw: str) -> dict[str, object]:
    value = JSON_FENCE_RE.sub("", raw.strip())
    start = value.find("{")
    end = value.rfind("}")
    if start < 0 or end < start:
        raise ValueError("模型没有返回 JSON 对象。")
    parsed = json.loads(value[start : end + 1])
    if not isinstance(parsed, dict):
        raise ValueError("模型回答必须是 JSON 对象。")
    return parsed


def validate_answer(
    answer: dict[str, object],
    context: dict[str, object],
    *,
    supplement_requested: bool,
) -> dict[str, object]:
    answer_type = answer.get("type")
    content = answer.get("answer")
    if answer_type not in ALLOWED_ANSWER_TYPES:
        raise ValueError("回答类型无效。")
    if not isinstance(content, str) or not content.strip():
        raise ValueError("回答正文为空。")

    chunks = {
        str(chunk["sourceId"]): chunk
        for chunk in context["sent"]["chunks"]  # type: ignore[index]
    }
    raw_citations = answer.get("citations", [])
    if not isinstance(raw_citations, list):
        raise ValueError("引用列表无效。")

    citations: list[dict[str, object]] = []
    for raw_citation in raw_citations:
        if not isinstance(raw_citation, dict):
            raise ValueError("引用条目无效。")
        source_id = raw_citation.get("source_id")
        quote = normalize_text(str(raw_citation.get("quote", "")))
        chunk = chunks.get(str(source_id))
        if chunk is None:
            raise ValueError(f"引用了不存在的来源 {source_id}。")
        if not quote or quote not in normalize_text(str(chunk["text"])):
            raise ValueError("引用原文不在实际发送的上下文片段中。")
        citations.append(
            {
                "sourceId": source_id,
                "kind": chunk["kind"],
                "path": chunk["path"],
                "blockId": chunk.get("blockId"),
                "blockIndex": chunk.get("blockIndex"),
                "page": chunk.get("page"),
                "headingPath": chunk["headingPath"],
                "quote": quote,
                "key": _chunk_key({**chunk, "quote": quote}),
            }
        )

    if answer_type == "grounded" and not citations:
        raise ValueError("Grounded answer 没有有效 Source citation。")
    if answer_type == "unsupported_supplement" and not supplement_requested:
        raise ValueError("用户没有请求非资料补充。")

    missing = answer.get("missing", [])
    if not isinstance(missing, list):
        missing = []
    return {
        "type": answer_type,
        "answer": content.strip(),
        "citations": citations,
        "missing": [str(item) for item in missing if str(item).strip()],
    }


def generate_answer(
    config: ModelConfig,
    context: dict[str, object],
    question: str,
    mode: str,
    supplement_requested: bool,
) -> dict[str, object]:
    retry_note: Optional[str] = None
    last_error = "模型回答未通过验证。"

    for _attempt in range(2):
        messages = tutor_messages(
            context,
            question,
            mode,
            supplement_requested,
            retry_note,
        )
        raw = "".join(
            stream_chat_completion(
                config,
                messages,
                metadata={
                    "study_notes_mode": mode,
                    "supplement_requested": supplement_requested,
                },
            )
        )
        try:
            parsed = parse_answer_json(raw)
            return validate_answer(
                parsed,
                context,
                supplement_requested=supplement_requested,
            )
        except (ValueError, json.JSONDecodeError) as validation_error:
            last_error = str(validation_error)
            retry_note = last_error

    return {
        "type": "insufficient_evidence",
        "answer": "当前资料不足以形成可验证的回答，模型也未能返回有效引用。",
        "citations": [],
        "missing": [last_error],
    }


def event_stream(
    workspace: Path,
    session: dict[str, object],
    sources: list[dict[str, object]],
    config: ModelConfig,
    question: str,
    mode: str,
    supplement_requested: bool,
) -> Iterator[str]:
    try:
        context = build_tutor_context(workspace, session, sources, question)
        save_session_message(
            workspace,
            str(session["id"]),
            "user",
            question,
            context=context,
        )
        yield sse_event("context", context)
        answer = generate_answer(
            config,
            context,
            question,
            mode,
            supplement_requested,
        )
        save_session_message(
            workspace,
            str(session["id"]),
            "assistant",
            str(answer["answer"]),
            answer_type=str(answer["type"]),
            citations=answer["citations"],
            context=context,
        )
        yield sse_event(
            "start",
            {
                "type": answer["type"],
                "missing": answer["missing"],
            },
        )
        answer_text = str(answer["answer"])
        for index in range(0, len(answer_text), 18):
            yield sse_event(
                "delta",
                {"text": answer_text[index : index + 18]},
            )
        yield sse_event("done", answer)
    except TutorContextError as context_error:
        yield sse_event(
            "error",
            {"message": str(context_error), "retryable": True},
        )
    except (ModelRequestError, ValueError, OSError) as tutor_error:
        yield sse_event(
            "error",
            {"message": str(tutor_error), "retryable": True},
        )


def sse_event(event: str, payload: object) -> str:
    return (
        f"event: {event}\n"
        f"data: {json.dumps(payload, ensure_ascii=False)}\n\n"
    )
