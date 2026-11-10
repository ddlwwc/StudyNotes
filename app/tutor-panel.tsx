"use client";

import {
  BookOpenCheck,
  BookmarkPlus,
  PanelRight,
  RotateCcw,
  Send,
  Square,
  X
} from "lucide-react";
import { useEffect, useRef, useState } from "react";
import type { TutorSelection } from "./blocknote-editor";
import { GapDialog } from "./gap-dialog";
import { PracticePanel } from "./practice-panel";

export type TutorCitation = {
  blockId: string | null;
  blockIndex: number | null;
  headingPath: string[];
  key?: string;
  kind: "markdown" | "pdf";
  path: string;
  page: number | null;
  quote: string;
  sourceId: string;
};

export type TutorSourceOption = {
  kind: "markdown" | "pdf";
  name: string;
  path: string;
};

type TutorSource = {
  blockId: string | null;
  blockIndex: number | null;
  headingPath: string[];
  id: string;
  isInitial: boolean;
  kind: "markdown" | "pdf";
  page: number | null;
  path: string;
  quote: string;
};

type TutorContext = {
  budget: {
    candidateCount: number;
    deduplicatedCount: number;
    maxCharacters: number;
    maxChunks: number;
    omittedCount: number;
    truncated: boolean;
  };
  omitted: Array<{
    blockId: string | null;
    kind: "markdown" | "pdf";
    origin: string;
    page: number | null;
    path: string;
    quote: string;
    reason: string;
  }>;
  sources: TutorSource[];
  retrieval: {
    fallback: boolean;
    label: string;
    mode: "semantic" | "fulltext";
    reason: string | null;
  };
  retrieved: Array<{
    blockId: string | null;
    headingPath: string[];
    kind: "markdown" | "pdf";
    origin: string;
    path: string;
    page: number | null;
    quote: string;
    sourceId: string;
  }>;
  selection: {
    blockId: string | null;
    blockIndex: number | null;
    headingPath: string[];
    kind: "markdown" | "pdf";
    path: string;
    page: number | null;
    quote: string;
  };
  sent: {
    characterCount: number;
    chunks: Array<{
      blockId: string | null;
      headingPath: string[];
      kind: "markdown" | "pdf";
      path: string;
      page: number | null;
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
  selection,
  sourceOptions
}: {
  onCitationSelect: (citation: TutorCitation) => void;
  path: string;
  selection: TutorSelection | null;
  sourceOptions: TutorSourceOption[];
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
  const [retrievalComplete, setRetrievalComplete] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [lastRequest, setLastRequest] = useState<LastRequest | null>(null);
  const [sources, setSources] = useState<TutorSource[]>([]);
  const [sourcePath, setSourcePath] = useState("");
  const [sourceStatus, setSourceStatus] = useState<string | null>(null);
  const [sourceWorking, setSourceWorking] = useState(false);
  const [gapDialogOpen, setGapDialogOpen] = useState(false);
  const [gapSessionId, setGapSessionId] = useState<string | null>(null);
  const [gapCreating, setGapCreating] = useState(false);
  const [gapStatus, setGapStatus] = useState<string | null>(null);
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
    setRetrievalComplete(false);
    setError(null);
    setLastRequest(null);
    setSources([]);
    setSourcePath("");
    setSourceStatus(null);
    setGapDialogOpen(false);
    setGapSessionId(null);
    setGapStatus(null);
  }, [path]);

  async function ensureSession(): Promise<string> {
    if (sessionId) {
      return sessionId;
    }
    if (!selection) {
      throw new Error("请先在资料块、Markdown 选区或 PDF 选区上建立 Learning session。");
    }
    const response = await fetch("/api/tutor/sessions", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        path,
        block_id: selection.blockId,
        page: selection.page,
        quote: selection.quote
      })
    });
    if (!response.ok) {
      throw new Error(await readError(response));
    }
    const session = (await response.json()) as {
      id: string;
      sources?: TutorSource[];
    };
    setSessionId(session.id);
    setSources(session.sources ?? []);
    return session.id;
  }

  async function pinSource(nextPath: string) {
    if (!nextPath) {
      return;
    }
    setSourceWorking(true);
    setSourceStatus(null);
    try {
      const activeSessionId = await ensureSession();
      const response = await fetch(
        `/api/tutor/sessions/${activeSessionId}/sources`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ path: nextPath })
        }
      );
      const payload = (await response.json()) as {
        deduplicated?: boolean;
        detail?: string;
        source?: TutorSource;
      };
      if (!response.ok || !payload.source) {
        throw new Error(payload.detail ?? "无法固定这个 Learning source。");
      }
      setSources((current) =>
        current.some((source) => source.id === payload.source?.id)
          ? current
          : [...current, payload.source as TutorSource]
      );
      setSourceStatus(
        payload.deduplicated
          ? "该位置已固定，已自动去重。"
          : `已固定 ${payload.source.path}`
      );
    } catch (pinError) {
      setSourceStatus(
        pinError instanceof Error ? pinError.message : "无法固定 Learning source。"
      );
    } finally {
      setSourceWorking(false);
    }
  }

  async function pinCurrentSelection() {
    if (!selection) {
      return;
    }
    setSourceWorking(true);
    setSourceStatus(null);
    try {
      const activeSessionId = await ensureSession();
      const response = await fetch(
        `/api/tutor/sessions/${activeSessionId}/sources`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            block_id: selection.blockId,
            page: selection.page,
            path,
            quote: selection.quote
          })
        }
      );
      const payload = (await response.json()) as {
        deduplicated?: boolean;
        detail?: string;
        source?: TutorSource;
      };
      if (!response.ok || !payload.source) {
        throw new Error(payload.detail ?? "无法固定当前选区。");
      }
      setSources((current) =>
        current.some((source) => source.id === payload.source?.id)
          ? current
          : [...current, payload.source as TutorSource]
      );
      setSourceStatus(
        payload.deduplicated
          ? "当前选区已经固定。"
          : "已固定当前选区"
      );
    } catch (pinError) {
      setSourceStatus(
        pinError instanceof Error ? pinError.message : "无法固定当前选区。"
      );
    } finally {
      setSourceWorking(false);
    }
  }

  async function removeSource(sourceId: string) {
    if (!sessionId) {
      return;
    }
    setSourceWorking(true);
    setSourceStatus(null);
    try {
      const response = await fetch(
        `/api/tutor/sessions/${sessionId}/sources/${sourceId}`,
        { method: "DELETE" }
      );
      if (!response.ok) {
        throw new Error(await readError(response));
      }
      setSources((current) =>
        current.filter((source) => source.id !== sourceId)
      );
      setSourceStatus("已移除 Learning source");
    } catch (removeError) {
      setSourceStatus(
        removeError instanceof Error
          ? removeError.message
          : "无法移除 Learning source。"
      );
    } finally {
      setSourceWorking(false);
    }
  }

  async function openSessionGapDialog() {
    setGapCreating(true);
    setGapStatus(null);
    try {
      const activeSessionId = await ensureSession();
      setGapSessionId(activeSessionId);
      setGapDialogOpen(true);
    } catch (gapError) {
      setGapStatus(
        gapError instanceof Error ? gapError.message : "无法创建知识缺口。"
      );
    } finally {
      setGapCreating(false);
    }
  }

  function handleEvent(
    eventName: string,
    payload: Record<string, unknown>
  ) {
    if (eventName === "context") {
      setContext(payload as TutorContext);
      setRetrievalComplete(true);
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
    setRetrievalComplete(false);
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
          <span className="field-label">
            {selection.kind === "pdf"
              ? `已绑定 PDF 第 ${selection.page} 页`
              : "已绑定 Markdown 选区"}
          </span>
          <p>{selection.quote}</p>
          <div className="tutor-gap-action">
            {gapStatus === "已记录为知识缺口" ? (
              <span role="status">{gapStatus}</span>
            ) : (
              <button
                disabled={gapCreating}
                type="button"
                onClick={() => void openSessionGapDialog()}
              >
                <BookmarkPlus aria-hidden="true" size={13} />
                {gapCreating ? "正在准备…" : "记为知识缺口"}
              </button>
            )}
            {gapStatus && gapStatus !== "已记录为知识缺口" ? (
              <small role="alert">{gapStatus}</small>
            ) : null}
          </div>
        </div>
      ) : (
        <p className="tutor-empty">
          点击 Markdown 块，或选中 Markdown / PDF 原文后提问。
        </p>
      )}

      {selection ? (
        <section className="tutor-sources" aria-label="Learning sources">
          <div className="tutor-sources-heading">
            <strong>资料范围</strong>
            <span>{Math.max(sources.length, sessionId ? 1 : 0)} 个来源</span>
          </div>
          {sources.map((source) => (
            <div className="tutor-source-row" key={source.id}>
              <span>
                {source.path}
                {source.kind === "pdf"
                  ? source.page
                    ? ` · 第 ${source.page} 页`
                    : " · 完整 PDF"
                  : source.isInitial
                    ? " · 当前锚点"
                    : " · Markdown"}
              </span>
              {!source.isInitial ? (
                <button
                  aria-label={`移除 ${source.path}`}
                  disabled={sourceWorking}
                  type="button"
                  onClick={() => void removeSource(source.id)}
                >
                  <X aria-hidden="true" size={12} />
                </button>
              ) : null}
            </div>
          ))}
          <div className="tutor-source-picker">
            <select
              aria-label="选择其他 Learning source"
              disabled={sourceWorking}
              value={sourcePath}
              onChange={(event) => setSourcePath(event.target.value)}
            >
              <option value="">选择 Markdown 或 PDF</option>
              {sourceOptions.map((option) => (
                <option key={option.path} value={option.path}>
                  {option.path}
                </option>
              ))}
            </select>
            <button
              type="button"
              disabled={!sourcePath || sourceWorking}
              onClick={() => void pinSource(sourcePath)}
            >
              固定来源
            </button>
          </div>
          {sessionId ? (
            <button
              className="tutor-pin-selection"
              disabled={sourceWorking || !selection}
              type="button"
              onClick={() => void pinCurrentSelection()}
            >
              固定当前选区
            </button>
          ) : null}
          {sourceStatus ? (
            <p className="tutor-source-status" role="status">
              {sourceStatus}
            </p>
          ) : null}
        </section>
      ) : null}

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
            ? retrievalComplete
              ? "正在生成…"
              : "正在检索资料…"
            : status === "done"
              ? "已完成"
              : status === "stopped"
                ? "已停止"
                : status === "error"
                  ? "回答失败"
                  : "等待选择资料"}
      </div>

      {context ? (
        <div
          className={`tutor-retrieval-mode ${
            context.retrieval.fallback ? "is-fallback" : ""
          }`}
          role="status"
        >
          <span>检索模式：{context.retrieval.label}</span>
          {context.retrieval.reason ? (
            <small>{context.retrieval.reason}</small>
          ) : null}
        </div>
      ) : null}

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
                  key={citation.key ?? `${citation.sourceId}:${citation.path}:${
                    citation.blockId ?? citation.page ?? ""
                  }:${citation.quote}`}
                  type="button"
                  onClick={() => onCitationSelect(citation)}
                >
                  <span>
                    Source citation · {citation.path}
                    {citation.kind === "pdf"
                      ? ` · 第 ${citation.page} 页`
                      : citation.headingPath.length > 0
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

      {gapDialogOpen && gapSessionId && selection ? (
        <GapDialog
          defaultTitle={selection.quote}
          onClose={() => setGapDialogOpen(false)}
          onCreated={() => {
            setGapDialogOpen(false);
            setGapStatus("已记录为知识缺口");
          }}
          sessionId={gapSessionId}
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
            <strong>检索模式</strong>
            <span>
              检索模式：{context.retrieval.label}
              {context.retrieval.reason
                ? ` · ${context.retrieval.reason}`
                : ""}
            </span>
          </div>
          <div className="tutor-context-section">
            <strong>选中资料</strong>
            <span>{context.selection.path}</span>
            <p>{context.selection.quote}</p>
          </div>
          <div className="tutor-context-section">
            <strong>固定资料</strong>
            <span>{context.sources.length} 个来源</span>
            {context.sources.map((source) => (
              <div key={source.id}>
                <span>
                  {source.path}
                  {source.kind === "pdf" && source.page
                    ? ` · 第 ${source.page} 页`
                    : ""}
                </span>
              </div>
            ))}
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
            {context.budget.omittedCount > 0 ||
            context.budget.truncated ||
            context.budget.deduplicatedCount > 0 ? (
              <div className="tutor-context-budget">
                <strong>上下文限额</strong>
                {context.budget.omittedCount > 0 ? (
                  <p>
                    已省略 {context.budget.omittedCount} 个片段；发送上限为{" "}
                    {context.budget.maxChunks} 个片段 /{" "}
                    {context.budget.maxCharacters} 字符。
                  </p>
                ) : null}
                {context.budget.deduplicatedCount > 0 ? (
                  <p>已去重 {context.budget.deduplicatedCount} 个重复片段。</p>
                ) : null}
                {context.budget.truncated ? <p>起点片段已按字符上限截断。</p> : null}
                {context.omitted.slice(0, 4).map((item) => (
                  <span key={`${item.kind}:${item.path}:${item.page}:${item.quote}`}>
                    {item.path}
                    {item.page ? ` · 第 ${item.page} 页` : ""}
                    {item.origin === "pinned" ? " · 固定来源" : " · 自动检索"}
                  </span>
                ))}
              </div>
            ) : null}
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
