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


def chat_completion_url(base_url: str) -> str:
    normalized = base_url.strip().rstrip("/")
    if not normalized:
        raise ModelRequestError("请先填写 Base URL。", status=422)
    if normalized.endswith("/chat/completions"):
        return normalized
    return f"{normalized}/chat/completions"


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
