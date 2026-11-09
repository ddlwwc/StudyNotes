"use client";

import {
  ChevronLeft,
  ChevronRight,
  LoaderCircle,
  Quote,
  ZoomIn,
  ZoomOut
} from "lucide-react";
import { useEffect, useRef, useState } from "react";
import type { PDFDocumentProxy, PDFPageProxy } from "pdfjs-dist";
import type * as PdfJsModule from "pdfjs-dist/legacy/build/pdf.mjs";

type PdfPageMetadata = {
  hasText: boolean;
  page: number;
};

type PdfMetadata = {
  extractorVersion: string;
  pageCount: number;
  pages: PdfPageMetadata[];
  path: string;
  pdfSha256: string;
  title: string;
};

type SavedCitation = {
  id: number;
  page: number;
  path: string;
  pdfSha256: string;
  quote: string;
};

type CitationValidationStatus =
  | "resolved"
  | "moved"
  | "unresolved"
  | "source_changed"
  | "unsupported_no_text";

const MIN_SCALE = 0.75;
const MAX_SCALE = 2.5;
const SCALE_STEP = 0.15;

export function PdfViewer({ path }: { path: string }) {
  const [metadata, setMetadata] = useState<PdfMetadata | null>(null);
  const [pdfDocument, setPdfDocument] = useState<PDFDocumentProxy | null>(null);
  const [pdfjs, setPdfjs] = useState<typeof PdfJsModule | null>(null);
  const [currentPage, setCurrentPage] = useState(1);
  const [scale, setScale] = useState(1.2);
  const [selectedQuote, setSelectedQuote] = useState("");
  const [savedCitation, setSavedCitation] = useState<SavedCitation | null>(null);
  const [validationMessage, setValidationMessage] = useState("");
  const [validating, setValidating] = useState(false);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const textLayerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    let cancelled = false;
    let loadingTask: ReturnType<typeof PdfJsModule.getDocument> | null = null;

    setLoading(true);
    setError(null);
    setMetadata(null);
    setPdfDocument(null);
    setCurrentPage(1);
    setSelectedQuote("");
    setSavedCitation(null);
    setValidationMessage("");

    async function loadPdf() {
      try {
        const [response, pdfjsModule] = await Promise.all([
          fetch(`/api/pdf?path=${encodeURIComponent(path)}`),
          import("pdfjs-dist/legacy/build/pdf.mjs")
        ]);
        const data = (await response.json()) as PdfMetadata & {
          detail?: string;
        };
        if (!response.ok) {
          throw new Error(data.detail ?? "无法读取这个 PDF 文件。");
        }

        pdfjsModule.GlobalWorkerOptions.workerSrc = "/pdfjs/pdf.worker.min.mjs";
        loadingTask = pdfjsModule.getDocument({
          url: `/api/pdf/content?path=${encodeURIComponent(path)}`,
          cMapPacked: true,
          cMapUrl: "/pdfjs/cmaps/",
          standardFontDataUrl: "/pdfjs/standard_fonts/"
        });
        const loadedDocument = await loadingTask.promise;

        if (!cancelled) {
          setMetadata(data);
          setPdfjs(pdfjsModule);
          setPdfDocument(loadedDocument);
        }
      } catch (loadError) {
        if (!cancelled) {
          setError(
            loadError instanceof Error
              ? loadError.message
              : "无法读取这个 PDF 文件。"
          );
        }
      } finally {
        if (!cancelled) {
          setLoading(false);
        }
      }
    }

    void loadPdf();

    return () => {
      cancelled = true;
      void loadingTask?.destroy();
    };
  }, [path]);

  useEffect(() => {
    if (!pdfDocument || !pdfjs) {
      return;
    }

    const activeDocument = pdfDocument;
    const activePdfjs = pdfjs;
    let cancelled = false;
    let renderTask: ReturnType<PDFPageProxy["render"]> | null = null;
    let textLayer: {
      cancel: () => void;
      render: () => Promise<unknown>;
    } | null = null;

    async function renderPage() {
      const canvas = canvasRef.current;
      const textContainer = textLayerRef.current;
      if (!canvas || !textContainer) {
        return;
      }

      try {
        const page = await activeDocument.getPage(currentPage);
        if (cancelled) {
          return;
        }

        const viewport = page.getViewport({ scale });
        const outputScale = window.devicePixelRatio || 1;
        const context = canvas.getContext("2d");
        if (!context) {
          throw new Error("浏览器无法创建 PDF 画布。");
        }

        canvas.width = Math.floor(viewport.width * outputScale);
        canvas.height = Math.floor(viewport.height * outputScale);
        canvas.style.width = `${Math.floor(viewport.width)}px`;
        canvas.style.height = `${Math.floor(viewport.height)}px`;

        renderTask = page.render({
          canvasContext: context,
          viewport,
          transform:
            outputScale === 1
              ? undefined
              : [outputScale, 0, 0, outputScale, 0, 0]
        });
        await renderTask.promise;

        if (cancelled) {
          return;
        }

        textContainer.replaceChildren();
        activePdfjs.setLayerDimensions(textContainer, viewport, false, false);
        textContainer.style.setProperty("--scale-factor", String(viewport.scale));
        const nextTextLayer = new activePdfjs.TextLayer({
          textContentSource: page.streamTextContent({
            includeMarkedContent: true
          }),
          container: textContainer,
          viewport
        });
        textLayer = nextTextLayer;
        await nextTextLayer.render();
      } catch (renderError) {
        if (
          !cancelled &&
          (!(renderError instanceof Error) ||
            renderError.name !== "RenderingCancelledException")
        ) {
          setError(
            renderError instanceof Error
              ? renderError.message
              : "无法渲染这个 PDF 页面。"
          );
        }
      }
    }

    void renderPage();

    return () => {
      cancelled = true;
      renderTask?.cancel();
      textLayer?.cancel();
    };
  }, [currentPage, pdfDocument, pdfjs, scale]);

  useEffect(() => {
    function captureSelection() {
      const selection = window.getSelection();
      const textContainer = textLayerRef.current;
      if (
        !selection ||
        selection.rangeCount === 0 ||
        !textContainer ||
        !textContainer.contains(selection.getRangeAt(0).commonAncestorContainer)
      ) {
        return;
      }

      const quote = selection.toString().trim().replace(/\s+/g, " ");
      setSelectedQuote(quote);
      setSavedCitation(null);
      setValidationMessage("");
    }

    document.addEventListener("selectionchange", captureSelection);
    return () => {
      document.removeEventListener("selectionchange", captureSelection);
    };
  }, []);

  function changePage(nextPage: number) {
    if (!metadata) {
      return;
    }

    const boundedPage = Math.min(metadata.pageCount, Math.max(1, nextPage));
    textLayerRef.current?.replaceChildren();
    setCurrentPage(boundedPage);
    setSelectedQuote("");
    setSavedCitation(null);
    setValidationMessage("");
    window.getSelection()?.removeAllRanges();
  }

  function changeScale(delta: number) {
    textLayerRef.current?.replaceChildren();
    setScale((current) =>
      Math.min(
        MAX_SCALE,
        Math.max(MIN_SCALE, Math.round((current + delta) * 100) / 100)
      )
    );
  }

  async function saveCitation() {
    if (!selectedQuote) {
      return;
    }

    setSaving(true);
    setError(null);
    try {
      const response = await fetch("/api/citations", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          path,
          page: currentPage,
          quote: selectedQuote
        })
      });
      const data = (await response.json()) as SavedCitation & {
        detail?: string;
      };
      if (!response.ok) {
        throw new Error(data.detail ?? "无法保存这条引用。");
      }
      setSavedCitation(data);
      setValidationMessage("");
    } catch (saveError) {
      setError(
        saveError instanceof Error ? saveError.message : "无法保存这条引用。"
      );
    } finally {
      setSaving(false);
    }
  }

  async function validateCitation() {
    if (!savedCitation) {
      return;
    }

    setValidating(true);
    setError(null);
    try {
      const response = await fetch(
        `/api/citations/${savedCitation.id}/validate`,
        { method: "POST" }
      );
      const data = (await response.json()) as {
        detail?: string;
        status: CitationValidationStatus;
      };
      if (!response.ok) {
        throw new Error(data.detail ?? "无法校验这条引用。");
      }

      const messages: Record<CitationValidationStatus, string> = {
        resolved: "引用仍有效",
        moved: "片段已移动到其他页面",
        unresolved: "无法在当前 PDF 中定位该片段",
        source_changed: "引用已失配：PDF 内容已变更",
        unsupported_no_text: "当前页没有可提取文本，首版不支持 OCR"
      };
      setValidationMessage(messages[data.status]);
    } catch (validationError) {
      setError(
        validationError instanceof Error
          ? validationError.message
          : "无法校验这条引用。"
      );
    } finally {
      setValidating(false);
    }
  }

  const currentPageMetadata = metadata?.pages.find(
    (page) => page.page === currentPage
  );

  return (
    <section className="pdf-reader" aria-label="PDF 阅读器">
      <header className="pdf-toolbar">
        <div className="pdf-title">
          <span>{metadata?.title ?? "PDF"}</span>
          <span className="read-only-label">只读</span>
        </div>
        <div className="pdf-page-controls">
          <button
            className="icon-button"
            type="button"
            aria-label="上一页"
            disabled={!metadata || currentPage <= 1}
            onClick={() => changePage(currentPage - 1)}
          >
            <ChevronLeft aria-hidden="true" size={17} />
          </button>
          <span className="page-counter">
            第 {currentPage} / {metadata?.pageCount ?? 0} 页
          </span>
          <button
            className="icon-button"
            type="button"
            aria-label="下一页"
            disabled={!metadata || currentPage >= metadata.pageCount}
            onClick={() => changePage(currentPage + 1)}
          >
            <ChevronRight aria-hidden="true" size={17} />
          </button>
          <span className="toolbar-divider" />
          <button
            className="icon-button"
            type="button"
            aria-label="缩小"
            disabled={scale <= MIN_SCALE}
            onClick={() => changeScale(-SCALE_STEP)}
          >
            <ZoomOut aria-hidden="true" size={17} />
          </button>
          <span className="zoom-label">{Math.round(scale * 100)}%</span>
          <button
            className="icon-button"
            type="button"
            aria-label="放大"
            disabled={scale >= MAX_SCALE}
            onClick={() => changeScale(SCALE_STEP)}
          >
            <ZoomIn aria-hidden="true" size={17} />
          </button>
        </div>
      </header>

      <div className="pdf-workspace">
        <div className="pdf-stage">
          {loading ? (
            <div className="center-state" role="status">
              <LoaderCircle className="spin" aria-hidden="true" size={22} />
              <span>正在加载 PDF…</span>
            </div>
          ) : error && !metadata ? (
            <p className="error-message">{error}</p>
          ) : (
            <div
              className="pdf-page-surface"
              role="region"
              aria-label="PDF 页面"
            >
              <canvas ref={canvasRef} />
              <div
                className="pdf-text-layer"
                ref={textLayerRef}
                aria-label="PDF 文本层"
              />
              {currentPageMetadata && !currentPageMetadata.hasText ? (
                <div className="pdf-no-text" role="status">
                  当前页没有可提取文本，首版不支持 OCR。
                </div>
              ) : null}
            </div>
          )}
        </div>

        <aside className="citation-panel" aria-label="资料引用">
          <div className="citation-heading">
            <Quote aria-hidden="true" size={16} />
            <span>Source citation</span>
          </div>
          <section className="selected-fragment" aria-label="选中片段">
            <span className="field-label">选中片段</span>
            <p>{selectedQuote || "尚未选择文本"}</p>
          </section>
          <button
            className="primary-button citation-save"
            type="button"
            disabled={!selectedQuote || saving}
            onClick={() => void saveCitation()}
          >
            {saving ? "正在保存…" : "保存引用"}
          </button>
          {savedCitation ? (
            <>
              <div className="citation-saved" role="status">
                <strong>引用已保存</strong>
                <span>
                  第 {savedCitation.page} 页 ·{" "}
                  {savedCitation.pdfSha256.slice(0, 12)}
                </span>
              </div>
              <button
                className="secondary-button citation-validate"
                type="button"
                disabled={validating}
                onClick={() => void validateCitation()}
              >
                {validating ? "正在校验…" : "校验引用"}
              </button>
              {validationMessage ? (
                <p
                  className={`citation-validation ${
                    validationMessage === "引用仍有效" ? "is-valid" : "is-invalid"
                  }`}
                  role="status"
                >
                  {validationMessage}
                </p>
              ) : null}
            </>
          ) : null}
          {error && metadata ? <p className="error-message">{error}</p> : null}
        </aside>
      </div>
    </section>
  );
}
