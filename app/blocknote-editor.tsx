"use client";

import type { Block, PartialBlock } from "@blocknote/core";
import { BlockNoteView } from "@blocknote/mantine";
import { useCreateBlockNote } from "@blocknote/react";
import "@blocknote/mantine/style.css";
import { AlertTriangle, RotateCcw, X } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import type { SearchResult } from "./search-dialog";

export type BlockMetadata = {
  children?: BlockMetadata[];
  custom?: Record<string, unknown>;
  id: string;
  layout?: unknown;
  props: Record<string, unknown>;
  type: string;
};

export type DocumentDraft = {
  baseRevision: string;
  blocks: BlockMetadata[];
  content: string;
  updatedAt: string;
};

export type MarkdownDocument = {
  blocks: BlockMetadata[];
  content: string;
  draft: DocumentDraft | null;
  path: string;
  revision: string;
  sidecarBackupPath: string | null;
  sidecarStatus: "missing" | "rebuilt" | "valid";
  title: string;
};

export type TutorSelection = {
  blockId: string;
  quote: string;
};

type ConflictState = {
  current: MarkdownDocument;
  message: string;
};

type BlockLike = {
  children?: BlockLike[];
  id: string;
  props?: Record<string, unknown>;
  type: string;
};

const AUTOSAVE_DELAY_MS = 700;
const POLL_INTERVAL_MS = 800;

function hydrateBlocks(
  blocks: BlockLike[],
  metadata: BlockMetadata[],
  parentKey = ""
): PartialBlock[] {
  const used = new Set<number>();

  return blocks.map((block, index) => {
    let metadataIndex = -1;
    if (metadata[index]?.type === block.type) {
      metadataIndex = index;
    } else {
      metadataIndex = metadata.findIndex(
        (candidate, candidateIndex) =>
          !used.has(candidateIndex) && candidate.type === block.type
      );
    }

    const blockMetadata =
      metadataIndex >= 0 ? metadata[metadataIndex] : undefined;
    if (metadataIndex >= 0) {
      used.add(metadataIndex);
    }

    const parsedProps = block.props ?? {};
    const restoredProps = Object.fromEntries(
      Object.entries(blockMetadata?.props ?? {}).filter(([key]) =>
        Object.hasOwn(parsedProps, key)
      )
    );

    return {
      ...block,
      id: blockMetadata?.id ?? `${parentKey}${index}-${block.id}`,
      props: {
        ...parsedProps,
        ...restoredProps
      },
      children: hydrateBlocks(
        block.children ?? [],
        blockMetadata?.children ?? [],
        `${parentKey}${index}/`
      )
    } as PartialBlock;
  });
}

function extractMetadata(
  blocks: BlockLike[],
  loadedMetadata: Map<string, BlockMetadata>
): BlockMetadata[] {
  return blocks.map((block) => {
    const previous = loadedMetadata.get(block.id);
    const metadata: BlockMetadata = {
      id: block.id,
      type: block.type,
      props: {
        ...(block.props ?? {}),
        ...(previous?.props ?? {})
      },
      children: extractMetadata(block.children ?? [], loadedMetadata)
    };
    if (previous?.layout !== undefined) {
      metadata.layout = previous.layout;
    }
    if (previous?.custom && Object.keys(previous.custom).length > 0) {
      metadata.custom = previous.custom;
    }
    return metadata;
  });
}

function metadataMap(blocks: BlockMetadata[]) {
  const entries = new Map<string, BlockMetadata>();
  const visit = (items: BlockMetadata[]) => {
    for (const item of items) {
      entries.set(item.id, item);
      visit(item.children ?? []);
    }
  };
  visit(blocks);
  return entries;
}

async function readJson<T>(response: Response): Promise<T> {
  return (await response.json()) as T;
}

export function BlockNoteEditor({
  citationTargetId,
  citationTargetQuote,
  initialDocument,
  initialSearchTarget,
  onPathAvailability,
  onTutorSelectionChange
}: {
  citationTargetId?: string | null;
  citationTargetQuote?: string | null;
  initialDocument: MarkdownDocument;
  initialSearchTarget: SearchResult | null;
  onPathAvailability: (available: boolean) => void;
  onTutorSelectionChange?: (selection: TutorSelection | null) => void;
}) {
  const editor = useCreateBlockNote({
    initialContent: [{ type: "paragraph", content: "" }]
  });
  const [status, setStatus] = useState("正在加载…");
  const [draftStatus, setDraftStatus] = useState<string | null>(null);
  const [conflict, setConflict] = useState<ConflictState | null>(null);
  const [pendingDraft, setPendingDraft] = useState<DocumentDraft | null>(
    initialDocument.draft
  );
  const [sidecarStatus, setSidecarStatus] = useState(
    initialDocument.sidecarStatus
  );
  const [sidecarBackupPath, setSidecarBackupPath] = useState(
    initialDocument.sidecarBackupPath
  );

  const revisionRef = useRef(initialDocument.revision);
  const dirtyRef = useRef(false);
  const conflictRef = useRef<ConflictState | null>(null);
  const savingRef = useRef(false);
  const changeVersionRef = useRef(0);
  const baselineMarkdownRef = useRef(initialDocument.content);
  const currentDocumentRef = useRef(initialDocument);
  const loadedMetadataRef = useRef(metadataMap(initialDocument.blocks));
  const saveTimerRef = useRef<number | null>(null);
  const draftQueueRef = useRef<Promise<void>>(Promise.resolve());
  const hydratingRef = useRef(true);
  const pageRef = useRef<HTMLDivElement>(null);

  function updateDirtySnapshot() {
    const markdown = editor.blocksToMarkdownLossy();
    const blocks = extractMetadata(
      editor.document as unknown as BlockLike[],
      loadedMetadataRef.current
    );
    return { markdown, blocks };
  }

  function queueDraft(
    markdown: string,
    blocks: BlockMetadata[],
    version: number
  ) {
    const baseRevision = revisionRef.current;
    draftQueueRef.current = draftQueueRef.current
      .then(async () => {
        const response = await fetch("/api/drafts", {
          method: "PUT",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            path: initialDocument.path,
            content: markdown,
            blocks,
            base_revision: baseRevision
          })
        });
        if (response.ok && changeVersionRef.current === version) {
          setDraftStatus("草稿已保存");
        }
      })
      .catch(() => {
        setDraftStatus("草稿暂未保存");
      });
  }

  function deleteServerDraft() {
    draftQueueRef.current = draftQueueRef.current
      .then(async () => {
        await fetch(`/api/drafts?path=${encodeURIComponent(initialDocument.path)}`, {
          method: "DELETE"
        });
      })
      .catch(() => undefined);
  }

  function loadDocumentIntoEditor(document: MarkdownDocument) {
    hydratingRef.current = true;
    onTutorSelectionChange?.(null);
    loadedMetadataRef.current = metadataMap(document.blocks);
    const parsed = editor.tryParseMarkdownToBlocks(
      document.content
    ) as unknown as BlockLike[];
    const hydrated = hydrateBlocks(parsed, document.blocks);
    editor.replaceBlocks(editor.document, hydrated);
    revisionRef.current = document.revision;
    currentDocumentRef.current = document;
    baselineMarkdownRef.current = editor.blocksToMarkdownLossy();
    dirtyRef.current = false;
    setSidecarStatus(document.sidecarStatus);
    setSidecarBackupPath(document.sidecarBackupPath);
    window.setTimeout(() => {
      hydratingRef.current = false;
    }, 0);
  }

  useEffect(() => {
    loadDocumentIntoEditor(initialDocument);
    setStatus("已加载");
  }, []);

  useEffect(() => {
    if (!initialSearchTarget) {
      return;
    }

    let attempts = 0;
    let timer = 0;

    const focusTarget = () => {
      const surface = pageRef.current;
      if (!surface) {
        return false;
      }

      let target: Element | null = null;
      if (initialSearchTarget.blockId) {
        try {
          target = surface.querySelector(
            `[data-node-type="blockContainer"][data-id="${CSS.escape(
              initialSearchTarget.blockId
            )}"]`
          );
        } catch {
          target = null;
        }
      }

      if (!target && initialSearchTarget.snippet) {
        const expected = initialSearchTarget.snippet
          .replace(/…/g, "")
          .replace(/\s+/g, " ")
          .trim();
        target =
          [...surface.querySelectorAll('[data-node-type="blockContainer"]')].find(
            (element) =>
              (element.textContent ?? "").replace(/\s+/g, " ").includes(expected)
          ) ?? null;
      }

      if (!target && initialSearchTarget.blockIndex !== null) {
        target =
          surface.querySelectorAll('[data-node-type="blockContainer"]')[
            initialSearchTarget.blockIndex
          ] ?? null;
      }

      if (!target) {
        return false;
      }
      surface
        .querySelectorAll(".search-target")
        .forEach((element) => element.classList.remove("search-target"));
      target?.classList.add("search-target");
      target.scrollIntoView({ block: "center", behavior: "instant" });
      return true;
    };

    const pollTarget = () => {
      attempts += 1;
      if (focusTarget() || attempts >= 25) {
        window.clearInterval(timer);
      }
    };

    timer = window.setInterval(pollTarget, 100);
    pollTarget();

    return () => window.clearInterval(timer);
  }, [initialDocument.path, initialSearchTarget]);

  useEffect(() => {
    if (!citationTargetId && !citationTargetQuote) {
      return;
    }
    const surface = pageRef.current;
    if (!surface) {
      return;
    }
    surface
      .querySelectorAll(".citation-target")
      .forEach((element) => {
        element.classList.remove("citation-target");
        element.removeAttribute("aria-current");
      });
    let target: Element | null = null;
    if (citationTargetId) {
      try {
        target = surface.querySelector(
          `[data-node-type="blockContainer"][data-id="${CSS.escape(
            citationTargetId
          )}"]`
        );
      } catch {
        target = null;
      }
    }
    if (!target && citationTargetQuote) {
      const expected = citationTargetQuote.replace(/\s+/g, " ").trim();
      target =
        [...surface.querySelectorAll('[data-node-type="blockContainer"]')].find(
          (element) =>
            (element.textContent ?? "")
              .replace(/\s+/g, " ")
              .includes(expected)
        ) ?? null;
    }
    if (target) {
      target.classList.add("citation-target");
      target.setAttribute("aria-current", "citation");
      target.scrollIntoView({ block: "center", behavior: "smooth" });
    }
  }, [citationTargetId, citationTargetQuote]);

  useEffect(() => {
    let active = true;

    async function pollDocument() {
      try {
        const response = await fetch(
          `/api/file?path=${encodeURIComponent(initialDocument.path)}`,
          { cache: "no-store" }
        );
        if (!active || !response.ok) {
          if (response.status === 404 && active) {
            setStatus("页面已从磁盘移除");
            onPathAvailability(false);
          }
          return;
        }

        const document = await readJson<MarkdownDocument>(response);
        currentDocumentRef.current = document;
        if (document.revision === revisionRef.current) {
          return;
        }

        if (!dirtyRef.current && !conflictRef.current) {
          loadDocumentIntoEditor(document);
          setStatus("已从磁盘刷新");
          return;
        }

        const nextConflict = {
          current: document,
          message: "检测到外部修改，当前编辑尚未覆盖磁盘。"
        };
        conflictRef.current = nextConflict;
        setConflict(nextConflict);
        setStatus("存在冲突");
      } catch {
        // Keep the editor usable while the local service recovers.
      }
    }

    const interval = window.setInterval(
      () => void pollDocument(),
      POLL_INTERVAL_MS
    );
    return () => {
      active = false;
      window.clearInterval(interval);
    };
  }, [editor, initialDocument.path, onPathAvailability]);

  async function commitLatest(
    snapshot?: { blocks: BlockMetadata[]; markdown: string },
    expectedRevision = revisionRef.current
  ) {
    if (savingRef.current) {
      return;
    }
    if (conflictRef.current && expectedRevision === revisionRef.current) {
      return;
    }

    const latest = snapshot ?? updateDirtySnapshot();
    const version = changeVersionRef.current;
    savingRef.current = true;
    setStatus("正在保存…");

    try {
      const response = await fetch("/api/file", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          path: initialDocument.path,
          content: latest.markdown,
          blocks: latest.blocks,
          expected_revision: expectedRevision
        })
      });
      const payload = await readJson<
        | MarkdownDocument
        | {
            detail: {
              current: MarkdownDocument;
              message: string;
            };
          }
      >(response);

      if (response.status === 409) {
        const current =
          "detail" in payload
            ? payload.detail.current
            : currentDocumentRef.current;
        const nextConflict = {
          current,
          message: "保存冲突：Markdown 已在外部修改，本地内容未覆盖磁盘。"
        };
        revisionRef.current = current.revision;
        currentDocumentRef.current = current;
        conflictRef.current = nextConflict;
        setConflict(nextConflict);
        setStatus("存在冲突");
        return;
      }
      if (!response.ok || "detail" in payload) {
        throw new Error("保存 Markdown 失败。");
      }

      revisionRef.current = payload.revision;
      currentDocumentRef.current = payload;
      baselineMarkdownRef.current = latest.markdown;
      setSidecarStatus(payload.sidecarStatus);
      setSidecarBackupPath(payload.sidecarBackupPath);

      if (version === changeVersionRef.current) {
        dirtyRef.current = false;
        setDraftStatus(null);
        setStatus("已保存");
        deleteServerDraft();
      } else {
        setStatus("正在保存…");
        saveTimerRef.current = window.setTimeout(
          () => void commitLatest(),
          AUTOSAVE_DELAY_MS
        );
      }
    } catch {
      setStatus("保存失败，草稿已保留");
    } finally {
      savingRef.current = false;
    }
  }

  function handleEditorChange() {
    if (hydratingRef.current) {
      return;
    }

    const snapshot = updateDirtySnapshot();
    if (snapshot.markdown === baselineMarkdownRef.current) {
      return;
    }

    dirtyRef.current = true;
    changeVersionRef.current += 1;
    setStatus("未保存");
    queueDraft(snapshot.markdown, snapshot.blocks, changeVersionRef.current);

    if (saveTimerRef.current !== null) {
      window.clearTimeout(saveTimerRef.current);
    }
    saveTimerRef.current = window.setTimeout(
      () => void commitLatest(snapshot),
      AUTOSAVE_DELAY_MS
    );
  }

  function restoreDraft() {
    if (!pendingDraft) {
      return;
    }

    hydratingRef.current = true;
    loadedMetadataRef.current = metadataMap(pendingDraft.blocks);
    const parsed = editor.tryParseMarkdownToBlocks(
      pendingDraft.content
    ) as unknown as BlockLike[];
    editor.replaceBlocks(editor.document, hydrateBlocks(parsed, pendingDraft.blocks));
    baselineMarkdownRef.current = editor.blocksToMarkdownLossy();
    dirtyRef.current = true;
    changeVersionRef.current += 1;
    setPendingDraft(null);

    window.setTimeout(() => {
      hydratingRef.current = false;
      if (pendingDraft.baseRevision !== revisionRef.current) {
        const nextConflict = {
          current: currentDocumentRef.current,
          message: "草稿基于旧版 Markdown，请选择保留草稿或载入磁盘版本。"
        };
        conflictRef.current = nextConflict;
        setConflict(nextConflict);
        setStatus("存在冲突");
        return;
      }

      const snapshot = updateDirtySnapshot();
      setStatus("未保存");
      queueDraft(snapshot.markdown, snapshot.blocks, changeVersionRef.current);
      saveTimerRef.current = window.setTimeout(
        () => void commitLatest(snapshot),
        AUTOSAVE_DELAY_MS
      );
    }, 0);
  }

  function discardDraft() {
    setPendingDraft(null);
    setDraftStatus(null);
    deleteServerDraft();
  }

  function loadRemoteVersion() {
    if (!conflict) {
      return;
    }
    loadDocumentIntoEditor(conflict.current);
    conflictRef.current = null;
    setConflict(null);
    setPendingDraft(null);
    setDraftStatus(null);
    setStatus("已载入磁盘版本");
    deleteServerDraft();
  }

  function overwriteRemoteVersion() {
    if (!conflict) {
      return;
    }
    const remoteRevision = conflict.current.revision;
    conflictRef.current = null;
    setConflict(null);
    revisionRef.current = remoteRevision;
    void commitLatest(updateDirtySnapshot(), remoteRevision);
  }

  function flushDraft() {
    if (!dirtyRef.current) {
      return;
    }
    const snapshot = updateDirtySnapshot();
    void fetch("/api/drafts", {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        path: initialDocument.path,
        content: snapshot.markdown,
        blocks: snapshot.blocks,
        base_revision: revisionRef.current
      }),
      keepalive: true
    });
  }

  function captureTutorSelection() {
    if (!onTutorSelectionChange) {
      return;
    }
    const surface = pageRef.current;
    const selection = window.getSelection();
    if (!surface || !selection || selection.rangeCount === 0) {
      return;
    }
    const range = selection.getRangeAt(0);
    const anchor =
      range.startContainer.nodeType === Node.ELEMENT_NODE
        ? (range.startContainer as Element)
        : range.startContainer.parentElement;
    if (!anchor || !surface.contains(anchor)) {
      return;
    }
    const block = anchor.closest(
      '[data-node-type="blockContainer"]'
    ) as HTMLElement | null;
    const blockId = block?.dataset.id;
    if (!block || !blockId) {
      return;
    }
    const selectedText = selection.toString().replace(/\s+/g, " ").trim();
    const blockText = (block.textContent ?? "").replace(/\s+/g, " ").trim();
    const quote = selectedText || blockText;
    if (quote) {
      onTutorSelectionChange({ blockId, quote });
    }
  }

  useEffect(() => {
    window.addEventListener("beforeunload", flushDraft);
    return () => {
      window.removeEventListener("beforeunload", flushDraft);
      if (saveTimerRef.current !== null) {
        window.clearTimeout(saveTimerRef.current);
      }
      flushDraft();
    };
  }, []);

  return (
    <div
      className="blocknote-page"
      ref={pageRef}
      onKeyUp={captureTutorSelection}
      onMouseUp={captureTutorSelection}
    >
      <div className="editor-statusbar" aria-live="polite">
        <span
          className={`save-state ${
            status === "存在冲突" || status.includes("失败") ? "is-error" : ""
          }`}
        >
          {status}
        </span>
        {draftStatus ? <span className="draft-state">{draftStatus}</span> : null}
      </div>

      {sidecarStatus !== "valid" ? (
        <div className="editor-notice">
          <RotateCcw aria-hidden="true" size={15} />
          <span>
            {sidecarStatus === "missing"
              ? "sidecar 缺失，已从 Markdown 重建基础块。"
              : "sidecar 已损坏或过期，已从 Markdown 重建并备份旧文件。"}
          </span>
          {sidecarBackupPath ? (
            <code title={sidecarBackupPath}>
              {sidecarBackupPath.split("/").at(-1)}
            </code>
          ) : null}
        </div>
      ) : null}

      {pendingDraft ? (
        <div className="editor-banner">
          <div>
            <strong>发现未保存草稿</strong>
            <span>{pendingDraft.updatedAt}</span>
          </div>
          <div className="editor-banner-actions">
            <button type="button" onClick={restoreDraft}>
              恢复草稿
            </button>
            <button
              aria-label="放弃草稿"
              className="icon-text-button"
              type="button"
              onClick={discardDraft}
            >
              <X aria-hidden="true" size={14} />
              放弃
            </button>
          </div>
        </div>
      ) : null}

      {conflict ? (
        <div className="editor-conflict" role="alert">
          <AlertTriangle aria-hidden="true" size={18} />
          <div>
            <strong>{conflict.message}</strong>
            <span>本地草稿仍保存在应用数据中，不会自动覆盖 Markdown。</span>
          </div>
          <div className="editor-banner-actions">
            <button type="button" onClick={loadRemoteVersion}>
              载入磁盘版本
            </button>
            <button
              className="danger-text-button"
              type="button"
              onClick={overwriteRemoteVersion}
            >
              用当前内容覆盖
            </button>
          </div>
        </div>
      ) : null}

      <BlockNoteView
        className="blocknote-surface"
        editor={editor}
        onChange={handleEditorChange}
        theme="light"
      />
    </div>
  );
}
