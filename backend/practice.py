from __future__ import annotations

import json
from typing import Optional

from model_client import ModelConfig, request_chat_completion
from search_index import normalize_text
from storage import (
    list_practice_attempts,
    list_learning_session_sources,
    list_session_messages,
    save_practice_set,
)
from tutor import build_tutor_context, parse_answer_json


class PracticeGenerationError(Exception):
    pass


class PracticeGradingError(Exception):
    pass


def _dialogue_for_session(
    workspace,
    session: dict[str, object],
) -> list[dict[str, str]]:
    messages = list_session_messages(workspace, str(session["id"]))
    return [
        {
            "role": str(message["role"]),
            "content": str(message["content"]),
        }
        for message in messages
        if str(message["content"]).strip()
    ]


def _practice_context(
    workspace,
    session: dict[str, object],
) -> tuple[dict[str, object], list[dict[str, str]]]:
    dialogue = _dialogue_for_session(workspace, session)
    dialogue_text = "\n".join(
        f"{message['role']}: {message['content']}" for message in dialogue
    )
    retrieval_query = (
        f"{session['quote']}\n{dialogue_text}"
        if dialogue_text
        else str(session["quote"])
    )
    context = build_tutor_context(
        workspace,
        session,
        list_learning_session_sources(workspace, str(session["id"])),
        retrieval_query[:4_000],
    )
    return context, dialogue


def practice_messages(
    context: dict[str, object],
    dialogue: list[dict[str, str]],
    question_count: int,
    retry_note: Optional[str] = None,
) -> list[dict[str, str]]:
    sent = context["sent"]
    system = (
        "你是 StudyNotes 的 Practice item 生成器。你必须只根据给定的 "
        "学习资料 上下文和当前 学习会话 对话出题，不得引入资料"
        "之外的模型知识。请生成恰好 "
        f"{question_count} 道简体中文 Practice item。"
        "题型只能是 single_choice 或 short_answer。"
        + (
            "至少包含一道 single_choice 和一道 short_answer。"
            if question_count >= 2
            else "可以生成任一支持的题型。"
        )
        +
        "只返回一个 JSON 对象，不要使用 Markdown 代码围栏。结构必须是："
        '{"questions":['
        '{"type":"single_choice","stem":"题干",'
        '"options":["选项A","选项B","选项C","选项D"],"correct_index":0,'
        '"explanation":"解释","citation":{"source_id":"S1","quote":"原文片段"}},'
        '{"type":"short_answer","stem":"题干","reference_answer":"参考要点",'
        '"citation":{"source_id":"S2","quote":"原文片段"}}'
        "]}。"
        "单选题 correct_index 是唯一正确选项的零起始下标，options 至少两项且不得重复。"
        "短答题提供可评分的 reference_answer，不返回 options 或 correct_index。"
        "每道题的 citation.source_id 只能使用上下文中的 source_id，"
        "citation.quote 必须在对应来源 text 中逐字或规范化空白后存在。"
    )
    messages = [
        {"role": "system", "content": system},
        {
            "role": "user",
            "content": (
                "学习资料 可审计上下文：\n"
                f"{json.dumps(sent, ensure_ascii=False)}\n\n"
                "当前 学习会话 对话：\n"
                f"{json.dumps(dialogue, ensure_ascii=False)}"
            ),
        },
    ]
    if retry_note:
        messages.append(
            {
                "role": "user",
                "content": (
                    "上一组题目未通过验证："
                    f"{retry_note}。请严格按要求重新生成完整题目列表。"
                ),
            }
        )
    return messages


def validate_questions(
    payload: dict[str, object],
    context: dict[str, object],
    expected_count: int,
) -> list[dict[str, object]]:
    raw_questions = payload.get("questions")
    if not isinstance(raw_questions, list):
        raise ValueError("模型没有返回题目列表。")
    if len(raw_questions) != expected_count:
        raise ValueError(
            f"模型应生成 {expected_count} 道题，实际生成 {len(raw_questions)} 道。"
        )

    chunks = {
        str(chunk["sourceId"]): chunk
        for chunk in context["sent"]["chunks"]  # type: ignore[index]
    }
    questions: list[dict[str, object]] = []
    stems: set[str] = set()
    for raw_question in raw_questions:
        if not isinstance(raw_question, dict):
            raise ValueError("题目条目无效。")
        stem = raw_question.get("stem")
        if not isinstance(stem, str) or not stem.strip():
            raise ValueError("题干不能为空。")
        normalized_stem = normalize_text(stem)
        if normalized_stem in stems:
            raise ValueError("题目不能重复。")
        stems.add(normalized_stem)

        raw_citation = raw_question.get("citation")
        if not isinstance(raw_citation, dict):
            raise ValueError("每道题必须有 资料引用。")
        source_id = str(raw_citation.get("source_id", ""))
        quote = normalize_text(str(raw_citation.get("quote", "")))
        chunk = chunks.get(source_id)
        if chunk is None:
            raise ValueError(f"题目引用了不存在的来源 {source_id}。")
        if not quote or quote not in normalize_text(str(chunk["text"])):
            raise ValueError("题目引用原文不在实际发送的上下文片段中。")

        citation = {
            "sourceId": source_id,
            "kind": chunk["kind"],
            "path": chunk["path"],
            "blockId": chunk.get("blockId"),
            "blockIndex": chunk.get("blockIndex"),
            "page": chunk.get("page"),
            "headingPath": chunk["headingPath"],
            "quote": quote,
        }
        item_type = str(raw_question.get("type", "single_choice")).strip()
        if item_type == "short_answer":
            reference_answer = raw_question.get("reference_answer")
            if (
                not isinstance(reference_answer, str)
                or not reference_answer.strip()
            ):
                raise ValueError("短答题必须有参考要点。")
            questions.append(
                {
                    "itemType": "short_answer",
                    "stem": stem.strip(),
                    "options": [],
                    "correctIndex": None,
                    "explanation": "",
                    "referenceAnswer": reference_answer.strip(),
                    "citation": citation,
                }
            )
            continue
        if item_type != "single_choice":
            raise ValueError("Practice item 题型无效。")

        raw_options = raw_question.get("options")
        if not isinstance(raw_options, list) or len(raw_options) < 2:
            raise ValueError("每道单选题至少需要两个选项。")
        options = [
            normalize_text(str(option))
            for option in raw_options
            if str(option).strip()
        ]
        if len(options) != len(raw_options) or len(set(options)) != len(options):
            raise ValueError("题目选项不能为空或重复。")

        correct_index = raw_question.get("correct_index")
        if (
            isinstance(correct_index, bool)
            or not isinstance(correct_index, int)
            or correct_index < 0
            or correct_index >= len(options)
        ):
            raise ValueError("每道单选题必须指定一个有效且唯一的正确选项。")

        explanation = raw_question.get("explanation")
        if not isinstance(explanation, str) or not explanation.strip():
            raise ValueError("每道单选题必须有解释。")

        questions.append(
            {
                "itemType": "single_choice",
                "stem": stem.strip(),
                "options": [str(option).strip() for option in raw_options],
                "correctIndex": correct_index,
                "explanation": explanation.strip(),
                "referenceAnswer": None,
                "citation": citation,
            }
        )
    return questions


def generate_practice(
    workspace,
    session: dict[str, object],
    config: ModelConfig,
    question_count: int,
) -> dict[str, object]:
    context, dialogue = _practice_context(workspace, session)
    retry_note: Optional[str] = None
    last_error = "模型题目未通过验证。"

    for _attempt in range(2):
        raw = request_chat_completion(
            config,
            practice_messages(
                context,
                dialogue,
                question_count,
                retry_note,
            ),
            metadata={
                "study_notes_mode": "practice",
                "practice_count": question_count,
            },
            timeout=90,
        )
        try:
            parsed = parse_answer_json(raw)
            questions = validate_questions(parsed, context, question_count)
            loaded = save_practice_set(workspace, str(session["id"]), questions)
            return serialize_practice(
                loaded,
                list_practice_attempts(
                    workspace,
                    str(session["id"]),
                    str(loaded["practice"]["id"]),  # type: ignore[index]
                ),
            )
        except (ValueError, json.JSONDecodeError) as validation_error:
            last_error = str(validation_error)
            retry_note = last_error

    raise PracticeGenerationError(last_error)


def short_answer_feedback_messages(
    context: dict[str, object],
    item: dict[str, object],
    answer_text: str,
) -> list[dict[str, str]]:
    system = (
        "你是 StudyNotes 的短答题评分器。你必须只根据给定的 学习资料 "
        "上下文、题目、参考要点和学习者答案给出反馈，不得引入资料之外的模型知识。"
        "评分要帮助学习者理解自己命中了什么、遗漏了什么。"
        "只返回一个 JSON 对象，不要使用 Markdown 代码围栏。结构必须是："
        '{"score":0到100的整数,"reference_points":["参考要点"],'
        '"scoring_basis":"评分依据","matched_points":["已命中项"],'
        '"missing_points":["遗漏项"],'
        '"citations":[{"source_id":"S1","quote":"原文片段"}]}。'
        "reference_points、scoring_basis 和 citations 不得为空。"
        "citation.source_id 只能使用上下文中的 source_id，"
        "citation.quote 必须逐字或规范化空白后出现在对应来源 text 中。"
    )
    return [
        {"role": "system", "content": system},
        {
            "role": "user",
            "content": (
                "学习资料 可审计上下文：\n"
                f"{json.dumps(context['sent'], ensure_ascii=False)}\n\n"
                f"短答题：{item['stem']}\n"
                f"参考要点：{item.get('reference_answer') or ''}\n"
                f"学习者答案：{answer_text}"
            ),
        },
    ]


def validate_short_answer_feedback(
    payload: dict[str, object],
    context: dict[str, object],
) -> dict[str, object]:
    score = payload.get("score")
    if isinstance(score, bool) or not isinstance(score, int) or not 0 <= score <= 100:
        raise ValueError("AI 初评必须是 0 到 100 的整数。")

    def text_list(name: str, *, required: bool) -> list[str]:
        value = payload.get(name)
        if not isinstance(value, list):
            raise ValueError(f"{name} 必须是列表。")
        normalized = [str(item).strip() for item in value if str(item).strip()]
        if required and not normalized:
            raise ValueError(f"{name} 不能为空。")
        return normalized

    scoring_basis = payload.get("scoring_basis")
    if not isinstance(scoring_basis, str) or not scoring_basis.strip():
        raise ValueError("评分依据不能为空。")

    chunks = {
        str(chunk["sourceId"]): chunk
        for chunk in context["sent"]["chunks"]  # type: ignore[index]
    }
    raw_citations = payload.get("citations")
    if not isinstance(raw_citations, list) or not raw_citations:
        raise ValueError("短答题反馈必须有 资料引用。")
    citations: list[dict[str, object]] = []
    for raw_citation in raw_citations:
        if not isinstance(raw_citation, dict):
            raise ValueError("资料引用 条目无效。")
        source_id = str(raw_citation.get("source_id", ""))
        quote = normalize_text(str(raw_citation.get("quote", "")))
        chunk = chunks.get(source_id)
        if chunk is None:
            raise ValueError(f"反馈引用了不存在的来源 {source_id}。")
        if not quote or quote not in normalize_text(str(chunk["text"])):
            raise ValueError("反馈引用原文不在实际发送的上下文片段中。")
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
            }
        )

    return {
        "score": score,
        "referencePoints": text_list("reference_points", required=True),
        "scoringBasis": scoring_basis.strip(),
        "matchedPoints": text_list("matched_points", required=False),
        "missingPoints": text_list("missing_points", required=False),
        "citations": citations,
    }


def score_short_answer(
    workspace,
    session: dict[str, object],
    item: dict[str, object],
    answer_text: str,
    config: ModelConfig,
) -> dict[str, object]:
    context = build_tutor_context(
        workspace,
        session,
        list_learning_session_sources(workspace, str(session["id"])),
        f"{item['stem']}\n{answer_text}"[:4_000],
    )
    raw = request_chat_completion(
        config,
        short_answer_feedback_messages(context, item, answer_text),
        metadata={
            "study_notes_mode": "practice_grade",
            "practice_item_id": str(item["id"]),
        },
        timeout=90,
    )
    try:
        return validate_short_answer_feedback(parse_answer_json(raw), context)
    except (ValueError, json.JSONDecodeError) as validation_error:
        raise PracticeGradingError(str(validation_error)) from validation_error


def serialize_practice_attempt(attempt: dict[str, object]) -> dict[str, object]:
    feedback = None
    if attempt.get("feedback_json"):
        try:
            feedback = json.loads(str(attempt["feedback_json"]))
        except json.JSONDecodeError:
            feedback = None
    return {
        "id": attempt["id"],
        "practiceItemId": attempt["practice_item_id"],
        "selectedIndex": (
            attempt["selected_index"]
            if attempt.get("selected_index") is not None
            and int(attempt["selected_index"]) >= 0
            else None
        ),
        "answerText": attempt.get("answer_text"),
        "correct": bool(attempt["correct"]),
        "feedback": feedback,
        "aiScore": attempt.get("ai_score"),
        "finalScore": attempt.get("final_score"),
        "feedbackStatus": attempt.get("feedback_status", "graded"),
        "feedbackError": attempt.get("feedback_error"),
        "answeredAt": attempt["answered_at"],
        "feedbackUpdatedAt": attempt.get("feedback_updated_at"),
    }


def serialize_practice(
    loaded: Optional[dict[str, object]],
    attempts: list[dict[str, object]],
) -> dict[str, object]:
    if loaded is None:
        return {"attempts": [], "practice": None}

    practice = loaded["practice"]
    items = loaded["items"]
    questions = []
    for item in items:  # type: ignore[union-attr]
        questions.append(
            {
                "id": item["id"],
                "ordinal": item["ordinal"],
                "itemType": item.get("item_type", "single_choice"),
                "stem": item["stem"],
                "options": json.loads(str(item["options_json"])),
                "correctIndex": (
                    item["correct_index"]
                    if item.get("item_type", "single_choice") == "single_choice"
                    else None
                ),
                "explanation": item["explanation"],
                "referenceAnswer": item.get("reference_answer"),
                "citation": json.loads(str(item["citation_json"])),
            }
        )
    return {
        "practice": {
            "id": practice["id"],  # type: ignore[index]
            "sessionId": practice["session_id"],  # type: ignore[index]
            "questionCount": practice["question_count"],  # type: ignore[index]
            "createdAt": practice["created_at"],  # type: ignore[index]
            "questions": questions,
        },
        "attempts": [serialize_practice_attempt(attempt) for attempt in attempts],
    }
