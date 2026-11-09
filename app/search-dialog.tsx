"use client";

import { FileText, FileType2, LoaderCircle, Search, X } from "lucide-react";
import { useEffect, useRef, useState } from "react";

export type SearchResult = {
  blockId: string | null;
  blockIndex: number | null;
  headingPath: string[];
  id: string;
  kind: "markdown" | "pdf";
  matchedIn: string;
  page: number | null;
  path: string;
  snippet: string;
  tags: string[];
  title: string;
};

type SearchResponse = {
  detail?: string;
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
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (!open) {
      return;
    }
    setQuery("");
    setResults([]);
    setError(null);
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
            const Icon = result.kind === "pdf" ? FileType2 : FileText;
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
                    <span>{result.path}</span>
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
      </section>
    </div>
  );
}
