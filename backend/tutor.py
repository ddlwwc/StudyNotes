from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Iterator, Optional

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


class TutorContextError(Exception):
    pass


def bind_tutor_selection(
    workspace: Path,
    relative_path: str,
    block_id: str,
    quote: str,
) -> dict[str, object]:
    return _load_block(workspace, relative_path, block_id, quote)


def _load_block(
    workspace: Path,
    relative_path: str,
    block_id: str,
    quote: str,
) -> dict[str, object]:
    sync_workspace_index(workspace)
    with connect() as connection:
        row = connection.execute(
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
              AND block_id = ?
            LIMIT 1
            """,
            (str(workspace.resolve()), relative_path, block_id),
        ).fetchone()
        if row is None:
            row = connection.execute(
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
            matching = next(
                (
                    candidate
                    for candidate in row
                    if normalize_text(quote)
                    and normalize_text(quote) in normalize_text(str(candidate["body"]))
                ),
                None,
            )
            if matching is None:
                raise TutorContextError("选中的 Markdown 块不属于当前页面。")
            row = matching

    body = normalize_text(str(row["body"]))
    normalized_quote = normalize_text(quote) or body
    if normalized_quote not in body:
        raise TutorContextError("选区内容已变化，请重新选择 Markdown 块。")
    heading_path = [
        heading
        for heading in str(row["heading_path"]).split("\x1f")
        if heading
    ]
    return {
        "blockId": row["block_id"],
        "blockIndex": row["block_index"],
        "headingPath": heading_path,
        "path": relative_path,
        "text": body,
        "title": str(row["title"]),
        "quote": normalized_quote,
    }


def build_tutor_context(
    workspace: Path,
    relative_path: str,
    block_id: str,
    quote: str,
    question: str,
) -> dict[str, object]:
    document = load_document(workspace / relative_path)
    selected = _load_block(workspace, relative_path, block_id, quote)
    chunks: list[dict[str, object]] = [
        {
            "sourceId": "S1",
            "path": relative_path,
            "blockId": selected["blockId"],
            "blockIndex": selected["blockIndex"],
            "headingPath": selected["headingPath"],
            "title": selected["title"],
            "quote": selected["quote"],
            "text": selected["text"],
            "selected": True,
        }
    ]

    results, _ = search_workspace(workspace, question, limit=12)
    for result in results:
        if str(result["kind"]) != "markdown":
            continue
        result_path = str(result["path"])
        result_block = result.get("blockId")
        if (
            result_path == relative_path
            and result_block == selected["blockId"]
        ):
            continue
        if any(
            item["path"] == result_path
            and item.get("blockId") == result_block
            for item in chunks
        ):
            continue
        snippet = normalize_text(str(result["snippet"])).replace("…", "")
        if not snippet:
            continue
        chunks.append(
            {
                "sourceId": f"S{len(chunks) + 1}",
                "path": result_path,
                "blockId": result_block,
                "blockIndex": result.get("blockIndex"),
                "headingPath": result.get("headingPath", []),
                "title": result["title"],
                "quote": snippet,
                "text": snippet,
                "selected": False,
            }
        )
        if len(chunks) >= 5:
            break

    return {
        "selection": {
            "path": relative_path,
            "blockId": selected["blockId"],
            "blockIndex": selected["blockIndex"],
            "headingPath": selected["headingPath"],
            "quote": selected["quote"],
        },
        "retrieved": [
            {
                "sourceId": chunk["sourceId"],
                "path": chunk["path"],
                "blockId": chunk.get("blockId"),
                "headingPath": chunk["headingPath"],
                "quote": chunk["quote"],
            }
            for chunk in chunks[1:]
        ],
        "sent": {
            "sourceCount": len(chunks),
            "characterCount": sum(len(str(chunk["text"])) for chunk in chunks),
            "revision": document["revision"],
            "chunks": chunks,
        },
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
                "path": chunk["path"],
                "blockId": chunk.get("blockId"),
                "blockIndex": chunk.get("blockIndex"),
                "headingPath": chunk["headingPath"],
                "quote": quote,
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
    config: ModelConfig,
    question: str,
    mode: str,
    supplement_requested: bool,
) -> Iterator[str]:
    try:
        context = build_tutor_context(
            workspace,
            str(session["path"]),
            str(session["block_id"]),
            str(session["quote"]),
            question,
        )
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
