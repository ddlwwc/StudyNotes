"use client";

import {
  BookOpenCheck,
  Bookmark,
  FileText,
  FileType2,
  History,
  LoaderCircle,
  Search,
  X
} from "lucide-react";
import { useEffect, useRef, useState } from "react";

export type SearchResult = {
  blockId: string | null;
  blockIndex: number | null;
  headingPath: string[];
  id: string;
  kind: "markdown" | "pdf" | "text";
  matchedIn: string;
  page: number | null;
  path: string;
  snippet: string;
  tags: string[];
  title: string;
  entityId?: string;
  resultType: "source" | "session" | "gap" | "practice";
  sessionId?: string;
  quote?: string;
};

type SearchResponse = {
  detail?: string;
  index?: {
    failedSources: number;
    indexedSources: number;
    removedSources: number;
    totalSources: number;
    unchangedSources: number;
  };
  indexIssues?: Array<{
    error: string;
    indexedAt: string;
    kind: string;
    path: string;
  }>;
  results: SearchResult[];
};

export function SearchDialog({
  open,
  onClose,
  onSelect
}: {
  open: boolean;
  onClose: () => void;
  onSelect: (result: SearchResult) => void;
}) {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<SearchResult[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [indexIssues, setIndexIssues] = useState<SearchResponse["indexIssues"]>(
    []
  );
  const [indexStats, setIndexStats] = useState<SearchResponse["index"]>();
  const [reindexStatus, setReindexStatus] = useState<string | null>(null);
  const [reindexing, setReindexing] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (!open) {
      return;
    }
    setQuery("");
    setResults([]);
    setError(null);
    setIndexIssues([]);
    setIndexStats(undefined);
    setReindexStatus(null);
    window.setTimeout(() => inputRef.current?.focus(), 0);
  }, [open]);

  useEffect(() => {
    if (!open) {
      return;
    }

    const normalizedQuery = query.trim();
    if (!normalizedQuery) {
      setResults([]);
      setLoading(false);
      setError(null);
      return;
    }

    const controller = new AbortController();
    const timer = window.setTimeout(async () => {
      setLoading(true);
      setError(null);
      try {
        const response = await fetch(
          `/api/search?q=${encodeURIComponent(normalizedQuery)}`,
          { cache: "no-store", signal: controller.signal }
        );
        const data = (await response.json()) as SearchResponse;
        if (!response.ok) {
          throw new Error(data.detail ?? "搜索暂时不可用。");
        }
        setResults(data.results);
        setIndexIssues(data.indexIssues ?? []);
        setIndexStats(data.index);
      } catch (searchError) {
        if (!controller.signal.aborted) {
          setResults([]);
          setError(
            searchError instanceof Error
              ? searchError.message
              : "搜索暂时不可用。"
          );
        }
      } finally {
        if (!controller.signal.aborted) {
          setLoading(false);
        }
      }
    }, 120);

    return () => {
      controller.abort();
      window.clearTimeout(timer);
    };
  }, [open, query]);

  async function rebuildIndex() {
    setReindexing(true);
    setReindexStatus(null);
    try {
      const response = await fetch("/api/search/reindex", { method: "POST" });
      const data = (await response.json()) as SearchResponse;
      if (!response.ok) {
        throw new Error(data.detail ?? "索引重建失败。");
      }
      setIndexIssues(data.indexIssues ?? []);
      setIndexStats(data.index);
      setReindexStatus(
        data.index
          ? `重建完成：索引 ${data.index.indexedSources} 个文件`
          : "重建完成"
      );
    } catch (rebuildError) {
      setReindexStatus(
        rebuildError instanceof Error ? rebuildError.message : "索引重建失败。"
      );
    } finally {
      setReindexing(false);
    }
  }

  useEffect(() => {
    if (!open) {
      return;
    }
    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") {
        event.preventDefault();
        onClose();
      }
    }
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [onClose, open]);

  if (!open) {
    return null;
  }

  return (
    <div
      className="search-backdrop"
      role="presentation"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget) {
          onClose();
        }
      }}
    >
      <section
        aria-label="搜索学习资料"
        aria-modal="true"
        className="search-dialog"
        role="dialog"
      >
        <div className="search-field-row">
          <Search aria-hidden="true" size={18} />
          <input
            ref={inputRef}
            aria-label="搜索学习资料"
            autoComplete="off"
            placeholder="搜索标题、正文、标签和 PDF"
            role="searchbox"
            spellCheck={false}
            type="search"
            value={query}
            onChange={(event) => setQuery(event.target.value)}
          />
          {loading ? (
            <LoaderCircle
              aria-label="正在搜索"
              className="spin"
              size={17}
            />
          ) : null}
          <button
            aria-label="关闭搜索"
            className="search-close"
            type="button"
            onClick={onClose}
          >
            <X aria-hidden="true" size={16} />
          </button>
        </div>

        <div className="search-results" aria-live="polite">
          {results.map((result) => {
            const Icon =
              result.resultType === "session"
                ? History
                : result.resultType === "gap"
                  ? Bookmark
                  : result.resultType === "practice"
                    ? BookOpenCheck
                    : result.kind === "pdf"
                      ? FileType2
                      : FileText;
            return (
              <button
                className="search-result"
                key={result.id}
                type="button"
                onClick={() => onSelect(result)}
              >
                <span className="search-result-icon">
                  <Icon aria-hidden="true" size={17} />
                </span>
                <span className="search-result-copy">
                  <span className="search-result-heading">
                    <strong>{result.title}</strong>
                    <span>
                      {result.resultType === "source"
                        ? "资料"
                        : result.resultType === "session"
                          ? "学习会话"
                          : result.resultType === "gap"
                            ? "知识缺口"
                            : "练习项"}
                      {" · "}
                      {result.path}
                    </span>
                  </span>
                  {result.headingPath.length > 0 || result.page ? (
                    <span className="search-result-locator">
                      {result.page
                        ? `第 ${result.page} 页`
                        : result.headingPath.join(" / ")}
                    </span>
                  ) : null}
                  {result.tags.length > 0 ? (
                    <span className="search-result-tags">
                      标签：{result.tags.join("、")}
                    </span>
                  ) : null}
                  {result.snippet ? (
                    <span className="search-result-snippet">
                      {result.snippet}
                    </span>
                  ) : null}
                </span>
              </button>
            );
          })}
          {!loading && query.trim() && results.length === 0 && !error ? (
            <p className="search-empty">没有匹配结果</p>
          ) : null}
          {error ? <p className="search-error">{error}</p> : null}
        </div>
        <footer className="search-index-status">
          <div>
            <strong>本地索引</strong>
            <span>
              {indexStats
                ? `${indexStats.totalSources} 个资料，${indexStats.failedSources} 个失败`
                : "开始搜索后显示索引状态"}
            </span>
          </div>
          {indexIssues && indexIssues.length > 0 ? (
            <div className="search-index-issues" role="alert">
              <strong>索引问题</strong>
              {indexIssues.map((issue) => (
                <span key={issue.path}>
                  {issue.path} · {issue.error}
                </span>
              ))}
            </div>
          ) : null}
          {reindexStatus ? <span role="status">{reindexStatus}</span> : null}
          <button
            disabled={reindexing}
            type="button"
            onClick={() => void rebuildIndex()}
          >
            {reindexing ? "正在重建索引…" : "重建索引"}
          </button>
        </footer>
      </section>
    </div>
  );
}
