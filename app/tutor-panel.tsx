"use client";

import {
  BookOpenCheck,
  PanelRight,
  RotateCcw,
  Send,
  Square
} from "lucide-react";
import { useEffect, useRef, useState } from "react";
import type { TutorSelection } from "./blocknote-editor";
import { PracticePanel } from "./practice-panel";

export type TutorCitation = {
  blockId: string | null;
  blockIndex: number | null;
  headingPath: string[];
  path: string;
  quote: string;
  sourceId: string;
};

type TutorContext = {
  retrieved: Array<{
    blockId: string | null;
    headingPath: string[];
    path: string;
    quote: string;
    sourceId: string;
  }>;
  selection: {
    blockId: string;
    blockIndex: number | null;
    headingPath: string[];
    path: string;
    quote: string;
  };
  sent: {
    characterCount: number;
    chunks: Array<{
      blockId: string | null;
      headingPath: string[];
      path: string;
      quote: string;
      sourceId: string;
      text: string;
    }>;
    revision: string;
    sourceCount: number;
  };
};

type TutorStatus = "idle" | "streaming" | "done" | "stopped" | "error";

type LastRequest = {
  question: string;
  supplementRequested: boolean;
};

async function readError(response: Response): Promise<string> {
  try {
    const payload = (await response.json()) as { detail?: string };
    return payload.detail ?? "请求失败。";
  } catch {
    return "请求失败。";
  }
}

export function TutorPanel({
  onCitationSelect,
  path,
  selection
}: {
  onCitationSelect: (citation: TutorCitation) => void;
  path: string;
  selection: TutorSelection | null;
}) {
  const [mode, setMode] = useState<"guided" | "direct">("guided");
  const [question, setQuestion] = useState("");
  const [sessionId, setSessionId] = useState<string | null>(null);
  const [status, setStatus] = useState<TutorStatus>("idle");
  const [answer, setAnswer] = useState("");
  const [answerType, setAnswerType] = useState<string | null>(null);
  const [citations, setCitations] = useState<TutorCitation[]>([]);
  const [missing, setMissing] = useState<string[]>([]);
  const [context, setContext] = useState<TutorContext | null>(null);
  const [contextOpen, setContextOpen] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [lastRequest, setLastRequest] = useState<LastRequest | null>(null);
  const controllerRef = useRef<AbortController | null>(null);

  useEffect(() => {
    controllerRef.current?.abort();
    controllerRef.current = null;
    setSessionId(null);
    setStatus("idle");
    setAnswer("");
    setAnswerType(null);
    setCitations([]);
    setMissing([]);
    setContext(null);
    setContextOpen(false);
    setError(null);
    setLastRequest(null);
  }, [path, selection?.blockId, selection?.quote]);

  async function ensureSession(): Promise<string> {
    if (sessionId) {
      return sessionId;
    }
    if (!selection) {
      throw new Error("请先在 Markdown 块或选区上建立 Learning session。");
    }
    const response = await fetch("/api/tutor/sessions", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        path,
        block_id: selection.blockId,
        quote: selection.quote
      })
    });
    if (!response.ok) {
      throw new Error(await readError(response));
    }
    const session = (await response.json()) as { id: string };
    setSessionId(session.id);
    return session.id;
  }

  function handleEvent(
    eventName: string,
    payload: Record<string, unknown>
  ) {
    if (eventName === "context") {
      setContext(payload as TutorContext);
      return;
    }
    if (eventName === "start") {
      setAnswerType(String(payload.type));
      setMissing(
        Array.isArray(payload.missing) ? payload.missing.map(String) : []
      );
      return;
    }
    if (eventName === "delta") {
      setAnswer((current) => current + String(payload.text ?? ""));
      return;
    }
    if (eventName === "done") {
      setAnswer(String(payload.answer ?? ""));
      setAnswerType(String(payload.type));
      setCitations(
        Array.isArray(payload.citations)
          ? (payload.citations as TutorCitation[])
          : []
      );
      setMissing(
        Array.isArray(payload.missing) ? payload.missing.map(String) : []
      );
      setStatus("done");
      return;
    }
    if (eventName === "error") {
      setError(String(payload.message ?? "回答失败。"));
      setStatus("error");
    }
  }

  async function runTurn(
    prompt: string,
    supplementRequested: boolean
  ) {
    if (!selection || !prompt.trim()) {
      return;
    }
    controllerRef.current?.abort();
    const controller = new AbortController();
    controllerRef.current = controller;
    setStatus("streaming");
    setAnswer("");
    setAnswerType(null);
    setCitations([]);
    setMissing([]);
    setContext(null);
    setError(null);
    setLastRequest({
      question: prompt.trim(),
      supplementRequested
    });

    try {
      const activeSessionId = await ensureSession();
      const response = await fetch(
        `/api/tutor/sessions/${activeSessionId}/turns`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            question: prompt.trim(),
            mode,
            supplement_requested: supplementRequested
          }),
          signal: controller.signal
        }
      );
      if (!response.ok || !response.body) {
        throw new Error(await readError(response));
      }

      const reader = response.body.getReader();
      const decoder = new TextDecoder();
      let buffer = "";
      while (true) {
        const { done, value } = await reader.read();
        if (done) {
          break;
        }
        buffer += decoder.decode(value, { stream: true });
        let boundary = buffer.indexOf("\n\n");
        while (boundary >= 0) {
          const block = buffer.slice(0, boundary);
          buffer = buffer.slice(boundary + 2);
          let eventName = "message";
          const dataLines: string[] = [];
          for (const line of block.split("\n")) {
            if (line.startsWith("event:")) {
              eventName = line.slice(6).trim();
            } else if (line.startsWith("data:")) {
              dataLines.push(line.slice(5).trim());
            }
          }
          if (dataLines.length > 0) {
            handleEvent(
              eventName,
              JSON.parse(dataLines.join("\n")) as Record<string, unknown>
            );
          }
          boundary = buffer.indexOf("\n\n");
        }
      }
    } catch (turnError) {
      if (turnError instanceof DOMException && turnError.name === "AbortError") {
        setStatus("stopped");
      } else {
        setError(
          turnError instanceof Error ? turnError.message : "回答失败。"
        );
        setStatus("error");
      }
    } finally {
      if (controllerRef.current === controller) {
        controllerRef.current = null;
      }
    }
  }

  function stopAnswer() {
    controllerRef.current?.abort();
    controllerRef.current = null;
    setStatus("stopped");
  }

  const streaming = status === "streaming";
  const answerTypeLabel =
    answerType === "grounded"
      ? "Grounded answer"
      : answerType === "insufficient_evidence"
        ? "证据不足"
        : answerType === "unsupported_supplement"
          ? "Unsupported supplement"
          : null;

  return (
    <aside
      aria-label="Grounded tutor"
      className="tutor-panel"
    >
      <header className="tutor-heading">
        <div>
          <span className="field-label">Learning session</span>
          <h2>学习私教</h2>
        </div>
        <BookOpenCheck aria-hidden="true" size={18} />
      </header>

      <div className="tutor-mode" aria-label="辅导模式">
        <button
          aria-pressed={mode === "guided"}
          className={mode === "guided" ? "is-active" : ""}
          disabled={streaming}
          type="button"
          onClick={() => setMode("guided")}
        >
          引导式
        </button>
        <button
          aria-pressed={mode === "direct"}
          className={mode === "direct" ? "is-active" : ""}
          disabled={streaming}
          type="button"
          onClick={() => setMode("direct")}
        >
          直接解释
        </button>
      </div>

      {selection ? (
        <div className="tutor-selection">
          <span className="field-label">已绑定 Markdown 选区</span>
          <p>{selection.quote}</p>
        </div>
      ) : (
        <p className="tutor-empty">
          点击 Markdown 块，或选中一段原文后提问。
        </p>
      )}

      <label className="tutor-question-label" htmlFor="tutor-question">
        向当前资料提问
      </label>
      <textarea
        disabled={!selection || streaming}
        id="tutor-question"
        placeholder={selection ? "这句话该怎么理解？" : "先选择资料范围"}
        rows={3}
        value={question}
        onChange={(event) => setQuestion(event.target.value)}
        onKeyDown={(event) => {
          if (
            event.key === "Enter" &&
            (event.metaKey || event.ctrlKey) &&
            !streaming &&
            selection
          ) {
            event.preventDefault();
            void runTurn(question, false);
          }
        }}
      />

      <div className="tutor-actions">
        {streaming ? (
          <button
            className="tutor-stop"
            type="button"
            onClick={stopAnswer}
          >
            <Square aria-hidden="true" size={13} />
            停止
          </button>
        ) : (
          <button
            className="tutor-send"
            disabled={!selection || !question.trim()}
            type="button"
            onClick={() => void runTurn(question, false)}
          >
            <Send aria-hidden="true" size={14} />
            发送
          </button>
        )}
        {context ? (
          <button
            className="tutor-context-button"
            type="button"
            onClick={() => setContextOpen((current) => !current)}
          >
            <PanelRight aria-hidden="true" size={14} />
            查看上下文
          </button>
        ) : null}
      </div>

      <div className="tutor-status" aria-live="polite">
        {status === "idle" && selection
          ? "已绑定当前资料位置"
          : streaming
            ? "正在生成…"
            : status === "done"
              ? "已完成"
              : status === "stopped"
                ? "已停止"
                : status === "error"
                  ? "回答失败"
                  : "等待选择资料"}
      </div>

      {error ? (
        <div className="tutor-error" role="alert">
          <span>{error}</span>
          {lastRequest ? (
            <button
              type="button"
              onClick={() =>
                void runTurn(
                  lastRequest.question,
                  lastRequest.supplementRequested
                )
              }
            >
              <RotateCcw aria-hidden="true" size={13} />
              重试
            </button>
          ) : null}
        </div>
      ) : null}

      {status === "stopped" && lastRequest ? (
        <button
          className="tutor-retry"
          type="button"
          onClick={() =>
            void runTurn(
              lastRequest.question,
              lastRequest.supplementRequested
            )
          }
        >
          <RotateCcw aria-hidden="true" size={13} />
          重试回答
        </button>
      ) : null}

      {answer || answerTypeLabel ? (
        <div
          className={`tutor-answer ${
            answerType === "unsupported_supplement"
              ? "is-unsupported"
              : answerType === "insufficient_evidence"
                ? "is-insufficient"
                : ""
          }`}
        >
          <div className="tutor-answer-heading">
            <span>{answerTypeLabel ?? "正在整理回答"}</span>
            {answerType === "unsupported_supplement" ? (
              <strong>不来自 Learning source</strong>
            ) : null}
          </div>
          <p>{answer}</p>
          {missing.length > 0 ? (
            <div className="tutor-missing">
              <span>证据缺口</span>
              <ul>
                {missing.map((item) => (
                  <li key={item}>{item}</li>
                ))}
              </ul>
            </div>
          ) : null}
          {citations.length > 0 ? (
            <div className="tutor-citations">
              {citations.map((citation) => (
                <button
                  aria-label={`Source citation ${citation.path}: ${citation.quote}`}
                  key={`${citation.sourceId}:${citation.blockId}`}
                  type="button"
                  onClick={() => onCitationSelect(citation)}
                >
                  <span>
                    Source citation · {citation.path}
                    {citation.headingPath.length > 0
                      ? ` / ${citation.headingPath.at(-1)}`
                      : ""}
                  </span>
                  <q>{citation.quote}</q>
                </button>
              ))}
            </div>
          ) : null}
          {answerType === "insufficient_evidence" && status === "done" ? (
            <button
              className="tutor-supplement"
              type="button"
              onClick={() =>
                void runTurn(
                  question.trim() || "请补充模型知识。",
                  true
                )
              }
            >
              请求模型补充
            </button>
          ) : null}
        </div>
      ) : null}

      {selection ? (
        <PracticePanel
          key={`${path}:${selection.blockId}`}
          onCitationSelect={onCitationSelect}
          onEnsureSession={ensureSession}
          sessionId={sessionId}
        />
      ) : null}

      {contextOpen && context ? (
        <section aria-label="上下文" className="tutor-context" role="region">
          <div className="tutor-context-heading">
            <div>
              <span className="field-label">可审计范围</span>
              <h3>本次发送的上下文</h3>
            </div>
            <button
              aria-label="关闭上下文"
              type="button"
              onClick={() => setContextOpen(false)}
            >
              ×
            </button>
          </div>
          <div className="tutor-context-section">
            <strong>选中资料</strong>
            <span>{context.selection.path}</span>
            <p>{context.selection.quote}</p>
          </div>
          <div className="tutor-context-section">
            <strong>检索片段</strong>
            {context.retrieved.length > 0 ? (
              context.retrieved.map((item) => (
                <div key={`${item.sourceId}:${item.blockId}`}>
                  <span>{item.path}</span>
                  <p>{item.quote}</p>
                </div>
              ))
            ) : (
              <p>没有额外检索片段。</p>
            )}
          </div>
          <div className="tutor-context-section">
            <strong>实际发送范围</strong>
            <span>
              {context.sent.sourceCount} 个片段 ·{" "}
              {context.sent.characterCount} 字符
            </span>
            {context.sent.chunks.map((chunk) => (
              <div key={chunk.sourceId}>
                <span>
                  [{chunk.sourceId}] {chunk.path}
                </span>
                <p>{chunk.text}</p>
              </div>
            ))}
          </div>
        </section>
      ) : null}
    </aside>
  );
}
