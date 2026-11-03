"use client";

import { useEffect, useState } from "react";
import {
  ChevronRight,
  Download,
  Link2,
  List,
  MessageSquareText,
  X
} from "lucide-react";
import type {
  AiAppendixItem,
  ArticleAnnotation,
  TableOfContentsItem
} from "@/domain/types";

interface ArticleExperienceProps {
  title: string;
  summary: string;
  publishedAt: string;
  readerHtml: string;
  toc: TableOfContentsItem[];
  annotations: ArticleAnnotation[];
  aiAppendix: AiAppendixItem[];
  exportHref: string;
  visibilityLabel: string;
}

export function ArticleExperience({
  title,
  summary,
  publishedAt,
  readerHtml,
  toc,
  annotations,
  aiAppendix,
  exportHref,
  visibilityLabel
}: ArticleExperienceProps) {
  const hasStudyLayer = annotations.length > 0 || aiAppendix.length > 0;
  const [studyOpen, setStudyOpen] = useState(false);
  const [mobileTocOpen, setMobileTocOpen] = useState(false);
  const [activeTab, setActiveTab] = useState<"annotations" | "ai">(
    annotations.length ? "annotations" : "ai"
  );
  const [progress, setProgress] = useState(0);
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    let frame = 0;
    const update = () => {
      frame = 0;
      const max = document.documentElement.scrollHeight - window.innerHeight;
      setProgress(max <= 0 ? 100 : Math.min(100, (window.scrollY / max) * 100));
    };
    const onScroll = () => {
      if (!frame) {
        frame = window.requestAnimationFrame(update);
      }
    };
    update();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => {
      window.removeEventListener("scroll", onScroll);
      if (frame) {
        window.cancelAnimationFrame(frame);
      }
    };
  }, []);

  async function copyLink() {
    await navigator.clipboard.writeText(window.location.href);
    setCopied(true);
    window.setTimeout(() => setCopied(false), 1800);
  }

  return (
    <>
      <div className="reading-progress" style={{ width: `${progress}%` }} />
      <div className="reading-toolbar">
        <div className="reading-toolbar__inner">
          <span className="breadcrumb">公开阅览室 / {title}</span>
          <button
            type="button"
            className="toolbar-button"
            onClick={() => setMobileTocOpen(true)}
            aria-label="目录"
          >
            <List size={16} aria-hidden="true" />
            <span>目录</span>
          </button>
          <button
            type="button"
            className={`toolbar-button${studyOpen ? " toolbar-button--active" : ""}`}
            onClick={() => setStudyOpen((value) => !value)}
            disabled={!hasStudyLayer}
            aria-pressed={studyOpen}
            aria-label="研读层"
          >
            <MessageSquareText size={16} aria-hidden="true" />
            <span>研读层</span>
          </button>
          <button
            type="button"
            className="toolbar-button"
            onClick={copyLink}
            aria-label="复制链接"
          >
            <Link2 size={16} aria-hidden="true" />
            <span>{copied ? "已复制" : "复制链接"}</span>
          </button>
          <a className="toolbar-button" href={exportHref} aria-label="导出">
            <Download size={16} aria-hidden="true" />
            <span>导出</span>
          </a>
        </div>
      </div>

      <div
        className={`mobile-toc-overlay${mobileTocOpen ? " mobile-toc-overlay--open" : ""}`}
        aria-hidden={!mobileTocOpen}
      >
        <button
          type="button"
          className="toolbar-button mobile-toc-overlay__close"
          onClick={() => setMobileTocOpen(false)}
          aria-label="关闭目录"
        >
          <X size={16} aria-hidden="true" />
          <span>关闭目录</span>
        </button>
        <TocList toc={toc} onNavigate={() => setMobileTocOpen(false)} />
      </div>

      <div className={`reading-shell${studyOpen ? " reading-shell--study" : ""}`}>
        <nav className="toc-panel" aria-label="文章目录">
          <h2>文章目录</h2>
          <TocList toc={toc} />
          <div className="reading-progress-label">
            <span>阅读进度</span>
            <div className="reading-progress-track">
              <i style={{ width: `${progress}%` }} />
            </div>
          </div>
        </nav>

        <article className="article-document">
          <p className="article-kicker">{visibilityLabel} · 学习文章</p>
          <h1>{title}</h1>
          {summary ? <p className="article-subtitle">{summary}</p> : null}
          <p className="article-meta">
            {visibilityLabel} · 更新于 {formatDate(publishedAt)}
          </p>
          <div className="article-divider" />
          <div
            className="article-body"
            dangerouslySetInnerHTML={{ __html: readerHtml }}
          />
          {aiAppendix.length ? (
            <details className="ai-appendix">
              <summary>AI 研读附录 · {aiAppendix.length} 项</summary>
              {aiAppendix.map((item) => (
                <section key={item.id}>
                  <h2>{item.title}</h2>
                  {item.body
                    .split(/\n{2,}/)
                    .map((paragraph) => (
                      <p key={paragraph}>{paragraph}</p>
                    ))}
                </section>
              ))}
            </details>
          ) : null}
        </article>

        {studyOpen ? (
          <aside className="study-panel" aria-label="研读层">
            <div className="study-panel__heading">
              <h2>研读层</h2>
              <span>由发布者主动公开</span>
            </div>
            <div className="study-tabs" role="tablist">
              {annotations.length ? (
                <button
                  type="button"
                  role="tab"
                  aria-selected={activeTab === "annotations"}
                  className={`study-tab${activeTab === "annotations" ? " study-tab--active" : ""}`}
                  onClick={() => setActiveTab("annotations")}
                >
                  公开标注 {annotations.length}
                </button>
              ) : null}
              {aiAppendix.length ? (
                <button
                  type="button"
                  role="tab"
                  aria-selected={activeTab === "ai"}
                  className={`study-tab${activeTab === "ai" ? " study-tab--active" : ""}`}
                  onClick={() => setActiveTab("ai")}
                >
                  AI 附录 {aiAppendix.length}
                </button>
              ) : null}
            </div>
            <div className="study-list">
              {activeTab === "annotations"
                ? annotations.map((annotation, index) => (
                    <section
                      className="study-annotation"
                      key={annotation.id}
                    >
                      <span className="study-annotation__id">
                        {String(index + 1).padStart(2, "0")}
                      </span>
                      <blockquote>“{annotation.quote}”</blockquote>
                      <p>{annotation.note}</p>
                    </section>
                  ))
                : aiAppendix.map((item) => (
                    <section className="study-ai-item" key={item.id}>
                      <h3>{item.title}</h3>
                      <p>{item.body}</p>
                    </section>
                  ))}
            </div>
            <div className="study-export">
              <h3>导出与分享</h3>
              <a className="export-link" href={exportHref}>
                <Download size={17} aria-hidden="true" />
                导出当前文章的独立 HTML 包
                <ChevronRight size={15} style={{ marginLeft: "auto" }} />
              </a>
            </div>
          </aside>
        ) : null}
      </div>
    </>
  );
}

function TocList({
  toc,
  onNavigate
}: {
  toc: TableOfContentsItem[];
  onNavigate?: () => void;
}) {
  return (
    <ol className="toc-list">
      {toc.map((item) => (
        <li className={`toc-level-${item.level}`} key={item.id}>
          <a href={`#${item.id}`} onClick={onNavigate}>
            {item.text}
          </a>
        </li>
      ))}
    </ol>
  );
}

function formatDate(value: string): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return "";
  }
  return new Intl.DateTimeFormat("zh-CN", {
    year: "numeric",
    month: "long",
    day: "numeric"
  }).format(date);
}
