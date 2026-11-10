from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Iterator, Optional
from urllib import error, request


class ModelRequestError(Exception):
    def __init__(self, message: str, *, status: int = 502) -> None:
        super().__init__(message)
        self.status = status


@dataclass(frozen=True)
class ModelConfig:
    base_url: str
    api_key: str
    model: str


@dataclass(frozen=True)
class EmbeddingConfig:
    base_url: str
    api_key: str
    model: str


def chat_completion_url(base_url: str) -> str:
    normalized = base_url.strip().rstrip("/")
    if not normalized:
        raise ModelRequestError("请先填写 Base URL。", status=422)
    if normalized.endswith("/chat/completions"):
        return normalized
    return f"{normalized}/chat/completions"


def embedding_url(base_url: str) -> str:
    normalized = base_url.strip().rstrip("/")
    if not normalized:
        raise ModelRequestError("请先填写 Base URL。", status=422)
    if normalized.endswith("/embeddings"):
        return normalized
    if normalized.endswith("/chat/completions"):
        return f"{normalized[: -len('/chat/completions')]}/embeddings"
    return f"{normalized}/embeddings"


def request_chat_completion(
    config: ModelConfig,
    messages: list[dict[str, str]],
    *,
    metadata: dict[str, object] | None = None,
    timeout: float = 30,
) -> str:
    payload = json.dumps(
        {
            "model": config.model,
            "messages": messages,
            "metadata": metadata or {},
            "stream": False,
        }
    ).encode("utf-8")
    model_request = request.Request(
        chat_completion_url(config.base_url),
        data=payload,
        headers={
            "Authorization": f"Bearer {config.api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    try:
        with request.urlopen(model_request, timeout=timeout) as response:
            raw_response = response.read().decode("utf-8")
    except error.HTTPError as request_error:
        raise ModelRequestError(
            f"模型服务返回 HTTP {request_error.code}。",
            status=502,
        ) from request_error
    except (error.URLError, TimeoutError, OSError) as request_error:
        raise ModelRequestError(
            "无法连接模型服务，请检查 Base URL 与网络。",
            status=502,
        ) from request_error

    try:
        data = json.loads(raw_response)
        content = data["choices"][0]["message"]["content"]
    except (json.JSONDecodeError, KeyError, IndexError, TypeError) as parse_error:
        raise ModelRequestError(
            "模型服务返回了无法识别的响应。",
            status=502,
        ) from parse_error

    if not isinstance(content, str):
        raise ModelRequestError("模型服务没有返回文本内容。", status=502)
    return content


def stream_chat_completion(
    config: ModelConfig,
    messages: list[dict[str, str]],
    *,
    metadata: dict[str, object] | None = None,
    timeout: float = 90,
) -> Iterator[str]:
    payload = json.dumps(
        {
            "model": config.model,
            "messages": messages,
            "metadata": metadata or {},
            "stream": True,
        }
    ).encode("utf-8")
    model_request = request.Request(
        chat_completion_url(config.base_url),
        data=payload,
        headers={
            "Authorization": f"Bearer {config.api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    try:
        response = request.urlopen(model_request, timeout=timeout)
    except error.HTTPError as request_error:
        raise ModelRequestError(
            f"模型服务返回 HTTP {request_error.code}。",
            status=502,
        ) from request_error
    except (error.URLError, TimeoutError, OSError) as request_error:
        raise ModelRequestError(
            "无法连接模型服务，请检查 Base URL 与网络。",
            status=502,
        ) from request_error

    try:
        for raw_line in response:
            line = raw_line.decode("utf-8").strip()
            if not line.startswith("data:"):
                continue
            data = line[5:].strip()
            if data == "[DONE]":
                break
            try:
                event = json.loads(data)
                delta = event["choices"][0]["delta"].get("content")
            except (json.JSONDecodeError, KeyError, IndexError, TypeError):
                continue
            if isinstance(delta, str) and delta:
                yield delta
    except (error.URLError, TimeoutError, OSError) as stream_error:
        raise ModelRequestError(
            "模型流式响应中断。",
            status=502,
        ) from stream_error
    finally:
        response.close()


def test_model_connection(config: ModelConfig) -> None:
    content = request_chat_completion(
        config,
        [
            {
                "role": "system",
                "content": "Return the word OK.",
            },
            {"role": "user", "content": "Connection test"},
        ],
    )
    if not content.strip():
        raise ModelRequestError("模型服务返回了空响应。", status=502)


def request_embeddings(
    config: EmbeddingConfig,
    inputs: list[str],
    *,
    timeout: float = 45,
) -> list[list[float]]:
    if not inputs or any(not value.strip() for value in inputs):
        raise ValueError("向量模型输入不能为空。")
    payload = json.dumps(
        {
            "model": config.model,
            "input": inputs,
        }
    ).encode("utf-8")
    embedding_request = request.Request(
        embedding_url(config.base_url),
        data=payload,
        headers={
            "Authorization": f"Bearer {config.api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    try:
        with request.urlopen(embedding_request, timeout=timeout) as response:
            raw_response = response.read().decode("utf-8")
    except error.HTTPError as request_error:
        raise ModelRequestError(
            f"向量模型服务返回 HTTP {request_error.code}。",
            status=502,
        ) from request_error
    except (error.URLError, TimeoutError, OSError) as request_error:
        raise ModelRequestError(
            "无法连接 向量模型服务，已自动回退全文检索。",
            status=502,
        ) from request_error

    try:
        data = json.loads(raw_response)
        raw_embeddings = data["data"]
    except (json.JSONDecodeError, KeyError, TypeError) as parse_error:
        raise ModelRequestError(
            "向量模型服务返回了无法识别的响应。",
            status=502,
        ) from parse_error

    if not isinstance(raw_embeddings, list) or len(raw_embeddings) != len(inputs):
        raise ModelRequestError("向量模型服务返回的向量数量不匹配。", status=502)

    sorted_embeddings = sorted(
        enumerate(raw_embeddings),
        key=lambda item: (
            item[1].get("index", item[0])
            if isinstance(item[1], dict)
            else item[0]
        ),
    )
    vectors: list[list[float]] = []
    dimension: Optional[int] = None
    for _, entry in sorted_embeddings:
        if not isinstance(entry, dict) or not isinstance(entry.get("embedding"), list):
            raise ModelRequestError("向量模型服务返回了无效向量。", status=502)
        try:
            vector = [float(value) for value in entry["embedding"]]
        except (TypeError, ValueError) as parse_error:
            raise ModelRequestError(
                "向量模型服务返回了无效向量。",
                status=502,
            ) from parse_error
        if not vector:
            raise ModelRequestError("向量模型服务返回了空向量。", status=502)
        if dimension is None:
            dimension = len(vector)
        elif len(vector) != dimension:
            raise ModelRequestError("向量模型向量维度不一致。", status=502)
        vectors.append(vector)
    return vectors


def test_embedding_connection(config: EmbeddingConfig) -> None:
    vectors = request_embeddings(config, ["StudyNotes embedding connection test"])
    if not vectors:
        raise ModelRequestError("向量模型服务返回了空响应。", status=502)
