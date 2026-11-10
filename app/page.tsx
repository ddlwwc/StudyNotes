"use client";

import {
  BookOpenText,
  Check,
  ChevronDown,
  ChevronRight,
  CalendarDays,
  FileText,
  FolderOpen,
  Library,
  Link2,
  LoaderCircle,
  Pencil,
  Plus,
  Search,
  Settings2,
  Trash2
} from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import type { FormEvent, MouseEvent as ReactMouseEvent } from "react";
import { BackupSettings } from "./backup-settings";
import {
  BlockNoteEditor,
  type MarkdownDocument,
  type TutorSelection
} from "./blocknote-editor";
import { PdfViewer } from "./pdf-viewer";
import { ReviewPage } from "./review-page";
import { SearchDialog, type SearchResult } from "./search-dialog";
import {
  TutorPanel,
  type TutorCitation,
  type TutorSourceOption
} from "./tutor-panel";

type TreeNode = {
  name: string;
  path: string;
  type: "directory" | "file";
  kind?: "markdown" | "pdf" | "text";
  children?: TreeNode[];
};

type WorkspaceState = {
  staleWorkspace: null | {
    path: string;
  };
  tree: TreeNode[];
  workspace: null | {
    name: string;
    path: string;
  };
};

type OpenFile = MarkdownDocument;

type TextFile = {
  content: string;
  path: string;
  readOnly: true;
  revision: string;
  title: string;
};

type QiniuSettings = {
  bucket: string;
  configured: boolean;
  domain: string;
  hasAccessKey: boolean;
  hasSecretKey: boolean;
};

type ModelSettings = {
  baseUrl: string;
  configured: boolean;
  embeddingConfigured: boolean;
  embeddingEnabled: boolean;
  embeddingModel: string;
  hasApiKey: boolean;
  model: string;
};

type RegisteredWorkspace = {
  active: boolean;
  name: string;
  path: string;
};

function findTreeNode(nodes: TreeNode[], path: string): TreeNode | null {
  for (const node of nodes) {
    if (node.path === path) {
      return node;
    }
    if (node.children) {
      const match = findTreeNode(node.children, path);
      if (match) {
        return match;
      }
    }
  }
  return null;
}

function mapMovedPath(path: string, oldPath: string, newPath: string): string {
  if (path === oldPath) {
    return newPath;
  }
  if (path.startsWith(`${oldPath}/`)) {
    return `${newPath}${path.slice(oldPath.length)}`;
  }
  return path;
}

function flattenSourceOptions(nodes: TreeNode[]): TutorSourceOption[] {
  return nodes.flatMap((node) => {
    if (node.type === "directory") {
      return flattenSourceOptions(node.children ?? []);
    }
    return [
      {
        kind: node.kind ?? "markdown",
        name: node.name,
        path: node.path
      }
    ];
  });
}

function filterTree(nodes: TreeNode[], paths: Set<string>): TreeNode[] {
  return nodes.flatMap((node) => {
    if (node.type === "file") {
      return paths.has(node.path) ? [node] : [];
    }
    const children = filterTree(node.children ?? [], paths);
    return children.length > 0 ? [{ ...node, children }] : [];
  });
}

function TreeNodes({
  activePath,
  nodes,
  onOpenFile,
  onSelect,
  selectedPath,
  depth = 0
}: {
  activePath: string | null;
  nodes: TreeNode[];
  onOpenFile: (node: TreeNode) => void;
  onSelect: (node: TreeNode) => void;
  selectedPath: string | null;
  depth?: number;
}) {
  const [collapsed, setCollapsed] = useState<Record<string, boolean>>({});

  return (
    <ul className="tree-list">
      {nodes.map((node) => {
        const isCollapsed = collapsed[node.path] ?? false;
        return (
          <li key={node.path}>
            <button
              aria-pressed={selectedPath === node.path}
              className={`tree-row ${node.type === "file" ? "is-file" : ""} ${
                activePath === node.path ? "is-active" : ""
              } ${selectedPath === node.path ? "is-selected" : ""}`}
              style={{ paddingLeft: `${8 + depth * 16}px` }}
              type="button"
              onClick={() => {
                const wasSelected = selectedPath === node.path;
                onSelect(node);
                if (node.type === "directory" && wasSelected) {
                  setCollapsed((current) => ({
                    ...current,
                    [node.path]: !isCollapsed
                  }));
                } else if (node.type === "file") {
                  onOpenFile(node);
                }
              }}
            >
              {node.type === "directory" ? (
                isCollapsed ? (
                  <ChevronRight aria-hidden="true" size={14} />
                ) : (
                  <ChevronDown aria-hidden="true" size={14} />
                )
              ) : (
                <FileText aria-hidden="true" size={14} />
              )}
              <span>{node.name}</span>
            </button>
            {node.type === "directory" && node.children && !isCollapsed ? (
              <TreeNodes
                activePath={activePath}
                nodes={node.children}
                onOpenFile={onOpenFile}
                onSelect={onSelect}
                selectedPath={selectedPath}
                depth={depth + 1}
              />
            ) : null}
          </li>
        );
      })}
    </ul>
  );
}

export default function HomePage() {
  const [workspace, setWorkspace] = useState<WorkspaceState["workspace"]>(null);
  const [staleWorkspace, setStaleWorkspace] =
    useState<WorkspaceState["staleWorkspace"]>(null);
  const [tree, setTree] = useState<TreeNode[]>([]);
  const [openFile, setOpenFile] = useState<OpenFile | null>(null);
  const [openTextFile, setOpenTextFile] = useState<TextFile | null>(null);
  const [tutorSelection, setTutorSelection] = useState<TutorSelection | null>(
    null
  );
  const [citationTarget, setCitationTarget] = useState<{
    blockId: string | null;
    quote: string;
  } | null>(null);
  const [openPdfPath, setOpenPdfPath] = useState<string | null>(null);
  const [pdfInitialPage, setPdfInitialPage] = useState(1);
  const [pdfCitationTarget, setPdfCitationTarget] = useState<{
    page: number;
    quote: string;
  } | null>(null);
  const [markdownSearchTarget, setMarkdownSearchTarget] =
    useState<SearchResult | null>(null);
  const [sessionTargetId, setSessionTargetId] = useState<string | null>(null);
  const [selectedNode, setSelectedNode] = useState<TreeNode | null>(null);
  const [mainView, setMainView] = useState<"workspace" | "review">("workspace");
  const [workspacePath, setWorkspacePath] = useState("");
  const [canBrowse, setCanBrowse] = useState(false);
  const [loading, setLoading] = useState(true);
  const [openingFile, setOpeningFile] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [working, setWorking] = useState(false);
  const [createDialogOpen, setCreateDialogOpen] = useState(false);
  const [newPageName, setNewPageName] = useState("");
  const [templates, setTemplates] = useState<
    Array<{ name: string; path: string }>
  >([]);
  const [selectedTemplate, setSelectedTemplate] = useState("");
  const [tags, setTags] = useState<string[]>([]);
  const [activeTag, setActiveTag] = useState("");
  const [taggedPaths, setTaggedPaths] = useState<Set<string>>(new Set());
  const [dailyStatus, setDailyStatus] = useState<string | null>(null);
  const [backlinks, setBacklinks] = useState<{
    backlinks: Array<{
      context: string;
      label: string;
      sourcePath: string;
      syntax: string;
      targetPath: string;
    }>;
    outgoing: Array<{
      context: string;
      label: string;
      sourcePath: string;
      syntax: string;
      targetPath: string;
    }>;
  } | null>(null);
  const [backlinksOpen, setBacklinksOpen] = useState(false);
  const [moveDialogOpen, setMoveDialogOpen] = useState(false);
  const [movePath, setMovePath] = useState("");
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [settingsLoading, setSettingsLoading] = useState(false);
  const [qiniuSettings, setQiniuSettings] = useState<QiniuSettings | null>(
    null
  );
  const [qiniuBucket, setQiniuBucket] = useState("");
  const [qiniuDomain, setQiniuDomain] = useState("");
  const [qiniuAccessKey, setQiniuAccessKey] = useState("");
  const [qiniuSecretKey, setQiniuSecretKey] = useState("");
  const [settingsStatus, setSettingsStatus] = useState<string | null>(null);
  const [settingsError, setSettingsError] = useState<string | null>(null);
  const [modelBaseUrl, setModelBaseUrl] = useState("");
  const [modelApiKey, setModelApiKey] = useState("");
  const [modelName, setModelName] = useState("");
  const [embeddingModel, setEmbeddingModel] = useState("");
  const [embeddingEnabled, setEmbeddingEnabled] = useState(false);
  const [hasModelApiKey, setHasModelApiKey] = useState(false);
  const [modelTesting, setModelTesting] = useState(false);
  const [embeddingTesting, setEmbeddingTesting] = useState(false);
  const [modelSaving, setModelSaving] = useState(false);
  const [modelStatus, setModelStatus] = useState<string | null>(null);
  const [modelError, setModelError] = useState<string | null>(null);
  const [registeredWorkspaces, setRegisteredWorkspaces] = useState<
    RegisteredWorkspace[]
  >([]);
  const [workspaceNames, setWorkspaceNames] = useState<Record<string, string>>(
    {}
  );
  const [newWorkspacePath, setNewWorkspacePath] = useState("");
  const [workspaceStatus, setWorkspaceStatus] = useState<string | null>(null);
  const [onboardingCompleted, setOnboardingCompleted] = useState<
    boolean | null
  >(null);
  const [boundaryAccepted, setBoundaryAccepted] = useState(false);
  const [onboardingStep, setOnboardingStep] = useState<1 | 2 | 3>(1);
  const [searchOpen, setSearchOpen] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const sourceOptions = flattenSourceOptions(tree);
  const visibleTree = activeTag ? filterTree(tree, taggedPaths) : tree;

  useEffect(() => {
    let active = true;

    async function loadWorkspace() {
      try {
        const [response, onboardingResponse] = await Promise.all([
          fetch("/api/workspace"),
          fetch("/api/onboarding", { cache: "no-store" })
        ]);
        if (!response.ok) {
          throw new Error("无法读取当前 学习工作区。");
        }
        const data = (await response.json()) as WorkspaceState;
        if (onboardingResponse.ok) {
          const onboarding = (await onboardingResponse.json()) as {
            boundaryAccepted: boolean;
            completed: boolean;
          };
          if (active) {
            setBoundaryAccepted(onboarding.boundaryAccepted);
            setOnboardingCompleted(onboarding.completed);
            setOnboardingStep(data.workspace ? 2 : 1);
          }
        }
        if (active) {
          setWorkspace(data.workspace);
          setStaleWorkspace(data.staleWorkspace);
          setTree(data.tree);
          if (data.workspace) {
            setWorkspacePath(data.workspace.path);
          } else if (data.staleWorkspace) {
            setWorkspacePath(data.staleWorkspace.path);
          }
          void loadNotebookMetadata();
        }
      } catch (loadError) {
        if (active) {
          setError(
            loadError instanceof Error ? loadError.message : "本地服务暂不可用。"
          );
        }
      } finally {
        if (active) {
          setLoading(false);
        }
      }
    }

    void loadWorkspace();
    return () => {
      active = false;
    };
  }, []);

  async function loadNotebookMetadata() {
    try {
      const [tagsResponse, templatesResponse] = await Promise.all([
        fetch("/api/tags", { cache: "no-store" }),
        fetch("/api/templates", { cache: "no-store" })
      ]);
      if (tagsResponse.ok) {
        const tagData = (await tagsResponse.json()) as { tags: string[] };
        setTags(tagData.tags);
      }
      if (templatesResponse.ok) {
        const templateData = (await templatesResponse.json()) as {
          templates: Array<{ name: string; path: string }>;
        };
        setTemplates(templateData.templates);
      }
    } catch {
      // The workspace tree remains usable while metadata is refreshed.
    }
  }

  useEffect(() => {
    if (!workspace) {
      return;
    }

    let active = true;

    async function refreshWorkspace() {
      try {
        const response = await fetch("/api/workspace", { cache: "no-store" });
        if (!response.ok) {
          return;
        }
        const data = (await response.json()) as WorkspaceState;
        if (!active) {
          return;
        }

        setWorkspace(data.workspace);
        setStaleWorkspace(data.staleWorkspace);
        setTree(data.tree);
        if (!data.workspace) {
          setOpenFile(null);
        }
        setSelectedNode((current) =>
          current && data.workspace ? findTreeNode(data.tree, current.path) : null
        );
      } catch {
        // Keep the last usable tree while the local service recovers.
      }
    }

    const interval = window.setInterval(() => void refreshWorkspace(), 800);
    return () => {
      active = false;
      window.clearInterval(interval);
    };
  }, [workspace?.path]);

  useEffect(() => {
    setCanBrowse(Boolean(window.studyNotes));
  }, []);

  useEffect(() => {
    if (!openFile) {
      setBacklinks(null);
      return;
    }
    let active = true;
    void fetch(`/api/links?path=${encodeURIComponent(openFile.path)}`, {
      cache: "no-store"
    })
      .then(async (response) => {
        if (!response.ok) {
          throw new Error("无法读取页面链接。");
        }
        const data = (await response.json()) as NonNullable<typeof backlinks>;
        if (active) {
          setBacklinks(data);
        }
      })
      .catch(() => {
        if (active) {
          setBacklinks({ backlinks: [], outgoing: [] });
        }
      });
    return () => {
      active = false;
    };
  }, [openFile?.path]);

  useEffect(() => {
    function handleSearchShortcut(event: KeyboardEvent) {
      if (
        workspace &&
        event.key.toLowerCase() === "k" &&
        (event.metaKey || event.ctrlKey)
      ) {
        event.preventDefault();
        setSearchOpen(true);
      }
    }
    window.addEventListener("keydown", handleSearchShortcut);
    return () => window.removeEventListener("keydown", handleSearchShortcut);
  }, [workspace]);

  async function openWorkspace(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSubmitting(true);
    setError(null);

    try {
      const response = await fetch("/api/workspace", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ path: workspacePath })
      });
      const data = (await response.json()) as WorkspaceState & {
        detail?: string;
      };
      if (!response.ok) {
        throw new Error(data.detail ?? "无法打开这个 学习工作区。");
      }

      setWorkspace(data.workspace);
      setStaleWorkspace(data.staleWorkspace);
      setTree(data.tree);
      setOpenFile(null);
      setOpenTextFile(null);
      setOpenPdfPath(null);
      setSelectedNode(null);
      setMainView("workspace");
      setOnboardingStep(2);
      if (data.workspace) {
        setWorkspacePath(data.workspace.path);
        void loadNotebookMetadata();
      }
    } catch (openError) {
      setError(
        openError instanceof Error
          ? openError.message
          : "无法打开这个 学习工作区。"
      );
    } finally {
      setSubmitting(false);
    }
  }

  async function setDataBoundary(accepted: boolean) {
    setBoundaryAccepted(accepted);
    try {
      const response = await fetch("/api/onboarding", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ boundary_accepted: accepted })
      });
      if (!response.ok) {
        throw new Error("无法保存资料发送边界确认。");
      }
      setBoundaryAccepted(accepted);
    } catch (boundaryError) {
      setBoundaryAccepted(!accepted);
      setError(
        boundaryError instanceof Error
          ? boundaryError.message
          : "无法保存资料发送边界确认。"
      );
    }
  }

  async function acceptDataBoundary() {
    await setDataBoundary(true);
  }

  async function completeOnboarding() {
    try {
      const response = await fetch("/api/onboarding", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          boundary_accepted: boundaryAccepted,
          completed: true
        })
      });
      if (!response.ok) {
        throw new Error("无法完成首次设置。");
      }
      setOnboardingCompleted(true);
    } catch (onboardingError) {
      setError(
        onboardingError instanceof Error
          ? onboardingError.message
          : "无法完成首次设置。"
      );
    }
  }

  async function openFileNode(
    node: TreeNode,
    searchTarget: SearchResult | null = null
  ) {
    setMainView("workspace");
    setOpeningFile(true);
    setError(null);
    setSessionTargetId(null);

    if (node.kind === "pdf" || node.path.toLowerCase().endsWith(".pdf")) {
      setOpenFile(null);
      setOpenTextFile(null);
      setTutorSelection(null);
      setMarkdownSearchTarget(null);
      setPdfInitialPage(searchTarget?.page ?? 1);
      setPdfCitationTarget(null);
      setOpenPdfPath(node.path);
      setOpeningFile(false);
      return;
    }

    if (node.kind === "text" || node.path.toLowerCase().endsWith(".txt")) {
      try {
        const response = await fetch(
          `/api/file?path=${encodeURIComponent(node.path)}`
        );
        const data = (await response.json()) as TextFile & { detail?: string };
        if (!response.ok) {
          throw new Error(data.detail ?? "无法读取这个纯文本页面。");
        }
        setOpenFile(null);
        setOpenTextFile(data);
        setTutorSelection(null);
        setCitationTarget(null);
        setMarkdownSearchTarget(searchTarget);
        setPdfCitationTarget(null);
        setOpenPdfPath(null);
      } catch (fileError) {
        setError(
          fileError instanceof Error
            ? fileError.message
            : "无法读取这个纯文本页面。"
        );
      } finally {
        setOpeningFile(false);
      }
      return;
    }

    try {
      const response = await fetch(
        `/api/file?path=${encodeURIComponent(node.path)}`
      );
      const data = (await response.json()) as OpenFile & { detail?: string };
      if (!response.ok) {
        throw new Error(data.detail ?? "无法读取这个 Markdown 页面。");
      }

      setOpenFile(data);
      setOpenTextFile(null);
      setTutorSelection(null);
      setCitationTarget(null);
      setMarkdownSearchTarget(searchTarget);
      setPdfInitialPage(1);
      setPdfCitationTarget(null);
      setOpenPdfPath(null);
    } catch (fileError) {
      setError(
        fileError instanceof Error
          ? fileError.message
          : "无法读取这个 Markdown 页面。"
      );
    } finally {
      setOpeningFile(false);
    }
  }

  async function openSearchResult(result: SearchResult) {
    setSearchOpen(false);
    const node = findTreeNode(tree, result.path);
    if (!node) {
      setError("搜索结果对应的资料已移动或删除。");
      return;
    }
    setSelectedNode(node);
    await openFileNode(node, result);
    if (
      result.resultType === "session" ||
      result.resultType === "practice" ||
      result.resultType === "gap"
    ) {
      setSessionTargetId(result.sessionId ?? null);
      setTutorSelection({
        blockId: result.blockId,
        kind: result.kind,
        page: result.page,
        quote: result.quote ?? result.snippet
      });
    }
  }

  const handlePathAvailability = useCallback((available: boolean) => {
    if (!available) {
      setOpenFile(null);
      setError("当前 Markdown 页面已从磁盘移除或移动。");
    }
  }, []);

  const handleCitationSelect = useCallback(
    (citation: TutorCitation) => {
      setMainView("workspace");
      const node = findTreeNode(tree, citation.path);
      if (node) {
        setSelectedNode(node);
      }
      setSearchOpen(false);
      setMarkdownSearchTarget(null);
      setError(null);
      if (citation.kind === "pdf") {
        setOpenFile(null);
        setCitationTarget(null);
        setPdfInitialPage(citation.page ?? 1);
        setPdfCitationTarget({
          page: citation.page ?? 1,
          quote: citation.quote
        });
        setOpenPdfPath(citation.path);
        return;
      }

      if (citation.kind === "text") {
        setOpeningFile(true);
        void (async () => {
          try {
            const response = await fetch(
              `/api/file?path=${encodeURIComponent(citation.path)}`
            );
            const data = (await response.json()) as TextFile & {
              detail?: string;
            };
            if (!response.ok) {
              throw new Error(data.detail ?? "无法打开资料引用。");
            }
            setOpenFile(null);
            setOpenTextFile(data);
            setOpenPdfPath(null);
            setCitationTarget(null);
            setPdfCitationTarget(null);
            setMarkdownSearchTarget(null);
          } catch (citationError) {
            setError(
              citationError instanceof Error
                ? citationError.message
                : "无法打开资料引用。"
            );
          } finally {
            setOpeningFile(false);
          }
        })();
        return;
      }

      if (openFile?.path === citation.path) {
        setCitationTarget({
          blockId: citation.blockId,
          quote: citation.quote
        });
        return;
      }

      setOpeningFile(true);
      void (async () => {
        try {
          const response = await fetch(
            `/api/file?path=${encodeURIComponent(citation.path)}`
          );
          const data = (await response.json()) as OpenFile & {
            detail?: string;
          };
          if (!response.ok) {
            throw new Error(data.detail ?? "无法打开 citation 对应的页面。");
          }
          setCitationTarget({
            blockId: citation.blockId,
            quote: citation.quote
          });
          setOpenFile(data);
          setOpenTextFile(null);
          setPdfInitialPage(1);
          setPdfCitationTarget(null);
          setOpenPdfPath(null);
        } catch (citationError) {
          setError(
            citationError instanceof Error
              ? citationError.message
              : "无法打开 citation 对应的页面。"
          );
        } finally {
          setOpeningFile(false);
        }
      })();
    },
    [openFile?.path, tree]
  );

  function selectedDirectoryPath(): string {
    if (!selectedNode) {
      return "";
    }
    if (selectedNode.type === "directory") {
      return selectedNode.path;
    }
    return selectedNode.path.split("/").slice(0, -1).join("/");
  }

  function selectTextLine(
    event: ReactMouseEvent<HTMLParagraphElement>,
    line: string
  ) {
    const selectedText = window
      .getSelection()
      ?.toString()
      .replace(/\s+/g, " ")
      .trim();
    const quote = selectedText || line.replace(/\s+/g, " ").trim();
    if (quote) {
      setTutorSelection({
        blockId: null,
        kind: "text",
        page: null,
        quote
      });
      event.currentTarget.classList.add("citation-target");
    }
  }

  async function createPage(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setWorking(true);
    setError(null);

    try {
      const response = await fetch("/api/pages", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          directory: selectedDirectoryPath(),
          name: newPageName,
          template: selectedTemplate || null
        })
      });
      const data = (await response.json()) as {
        detail?: string;
        path: string;
        tree: TreeNode[];
      };
      if (!response.ok) {
        throw new Error(data.detail ?? "无法创建 Markdown 页面。");
      }

      setTree(data.tree);
      setSelectedNode(findTreeNode(data.tree, data.path));
      setCreateDialogOpen(false);
      setNewPageName("");
      setSelectedTemplate("");
      void loadNotebookMetadata();
    } catch (createError) {
      setError(
        createError instanceof Error
          ? createError.message
          : "无法创建 Markdown 页面。"
      );
    } finally {
      setWorking(false);
    }
  }

  async function createDailyNote() {
    setWorking(true);
    setDailyStatus(null);
    setError(null);
    try {
      const response = await fetch("/api/daily", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({})
      });
      const data = (await response.json()) as {
        detail?: string;
        path: string;
        tree: TreeNode[];
      };
      if (!response.ok) {
        throw new Error(data.detail ?? "无法创建今日笔记。");
      }
      setTree(data.tree);
      setDailyStatus("今日笔记已创建");
      setSelectedNode(findTreeNode(data.tree, data.path));
      await openFileNode({
        name: data.path.split("/").at(-1) ?? data.path,
        path: data.path,
        type: "file",
        kind: "markdown"
      });
      void loadNotebookMetadata();
    } catch (dailyError) {
      setDailyStatus(
        dailyError instanceof Error ? dailyError.message : "无法创建今日笔记。"
      );
    } finally {
      setWorking(false);
    }
  }

  async function applyTag(tag: string) {
    if (activeTag === tag) {
      setActiveTag("");
      setTaggedPaths(new Set());
      return;
    }
    setActiveTag(tag);
    try {
      const response = await fetch(`/api/tagged?tag=${encodeURIComponent(tag)}`, {
        cache: "no-store"
      });
      if (!response.ok) {
        throw new Error("无法筛选标签。");
      }
      const data = (await response.json()) as { paths: string[] };
      setTaggedPaths(new Set(data.paths));
    } catch (tagError) {
      setError(tagError instanceof Error ? tagError.message : "无法筛选标签。");
      setTaggedPaths(new Set());
    }
  }

  async function moveEntry(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!selectedNode) {
      return;
    }

    setWorking(true);
    setError(null);

    try {
      const response = await fetch("/api/entries", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          path: selectedNode.path,
          new_path: movePath
        })
      });
      const data = (await response.json()) as {
        detail?: string;
        newPath: string;
        oldPath: string;
        tree: TreeNode[];
      };
      if (!response.ok) {
        throw new Error(data.detail ?? "无法重命名或移动这个条目。");
      }

      setTree(data.tree);
      setSelectedNode(findTreeNode(data.tree, data.newPath));
      setOpenFile((current) => {
        if (!current) {
          return current;
        }
        const movedPath = mapMovedPath(current.path, data.oldPath, data.newPath);
        if (movedPath === current.path) {
          return current;
        }
        return {
          ...current,
          path: movedPath,
          title: movedPath.split("/").at(-1)?.replace(/\.md$/i, "") ?? current.title
        };
      });
      setMoveDialogOpen(false);
      setMovePath("");
    } catch (moveError) {
      setError(
        moveError instanceof Error
          ? moveError.message
          : "无法重命名或移动这个条目。"
      );
    } finally {
      setWorking(false);
    }
  }

  async function deleteEntry() {
    if (!selectedNode) {
      return;
    }

    setWorking(true);
    setError(null);

    try {
      const response = await fetch(
        `/api/entries?path=${encodeURIComponent(selectedNode.path)}`,
        { method: "DELETE" }
      );
      const data = (await response.json()) as {
        deletedPath: string;
        detail?: string;
        tree: TreeNode[];
      };
      if (!response.ok) {
        throw new Error(data.detail ?? "无法删除这个条目。");
      }

      setTree(data.tree);
      setOpenFile((current) => {
        if (
          current &&
          (current.path === data.deletedPath ||
            current.path.startsWith(`${data.deletedPath}/`))
        ) {
          return null;
        }
        return current;
      });
      const parentPath = data.deletedPath.split("/").slice(0, -1).join("/");
      setSelectedNode(findTreeNode(data.tree, parentPath));
      setDeleteDialogOpen(false);
    } catch (deleteError) {
      setError(
        deleteError instanceof Error
          ? deleteError.message
          : "无法删除这个条目。"
      );
    } finally {
      setWorking(false);
    }
  }

  async function chooseWorkspace() {
    const selected = await window.studyNotes?.chooseWorkspaceDirectory();
    if (selected) {
      setWorkspacePath(selected);
      setError(null);
    }
  }

  async function openSettings() {
    setSettingsOpen(true);
    setSettingsLoading(true);
    setSettingsError(null);
    setSettingsStatus(null);
    setModelError(null);
    setModelStatus(null);

    try {
      const [qiniuResponse, modelResponse, workspacesResponse] = await Promise.all([
        fetch("/api/settings/qiniu", { cache: "no-store" }),
        fetch("/api/model-settings", { cache: "no-store" }),
        fetch("/api/workspaces", { cache: "no-store" })
      ]);
      const qiniuData = (await qiniuResponse.json()) as QiniuSettings & {
        detail?: string;
      };
      const modelData = (await modelResponse.json()) as ModelSettings & {
        detail?: string;
      };
      const workspaceData = (await workspacesResponse.json()) as {
        detail?: string;
        workspaces: RegisteredWorkspace[];
      };
      if (!qiniuResponse.ok) {
        throw new Error(qiniuData.detail ?? "无法读取七牛配置。");
      }
      if (!modelResponse.ok) {
        throw new Error(modelData.detail ?? "无法读取模型设置。");
      }
      if (!workspacesResponse.ok) {
        throw new Error(workspaceData.detail ?? "无法读取工作区列表。");
      }
      setQiniuSettings(qiniuData);
      setQiniuBucket(qiniuData.bucket);
      setQiniuDomain(qiniuData.domain);
      setQiniuAccessKey("");
      setQiniuSecretKey("");
      setModelBaseUrl(modelData.baseUrl);
      setModelName(modelData.model);
      setEmbeddingModel(modelData.embeddingModel);
      setEmbeddingEnabled(modelData.embeddingEnabled);
      setHasModelApiKey(modelData.hasApiKey);
      setModelApiKey("");
      setRegisteredWorkspaces(workspaceData.workspaces);
      setWorkspaceNames(
        Object.fromEntries(
          workspaceData.workspaces.map((item) => [item.path, item.name])
        )
      );
    } catch (settingsLoadError) {
      setSettingsError(
        settingsLoadError instanceof Error
          ? settingsLoadError.message
          : "无法读取设置。"
      );
    } finally {
      setSettingsLoading(false);
    }
  }

  function applyWorkspaceResponse(data: WorkspaceState) {
    setWorkspace(data.workspace);
    setStaleWorkspace(data.staleWorkspace);
    setTree(data.tree);
    setOpenFile(null);
    setOpenTextFile(null);
    setOpenPdfPath(null);
    setTutorSelection(null);
    setSelectedNode(null);
    setMainView("workspace");
    setWorkspacePath(data.workspace?.path ?? data.staleWorkspace?.path ?? "");
    void loadNotebookMetadata();
  }

  async function activateWorkspacePath(path: string) {
    setWorkspaceStatus(null);
    try {
      const response = await fetch("/api/workspace", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ path })
      });
      const data = (await response.json()) as WorkspaceState & {
        detail?: string;
      };
      if (!response.ok) {
        throw new Error(data.detail ?? "无法切换工作区。");
      }
      applyWorkspaceResponse(data);
      setWorkspaceStatus("工作区已切换");
      await reloadRegisteredWorkspaces();
    } catch (workspaceError) {
      setWorkspaceStatus(
        workspaceError instanceof Error
          ? workspaceError.message
          : "无法切换工作区。"
      );
    }
  }

  async function reloadRegisteredWorkspaces() {
    const response = await fetch("/api/workspaces", { cache: "no-store" });
    if (!response.ok) {
      return;
    }
    const data = (await response.json()) as {
      workspaces: RegisteredWorkspace[];
    };
    setRegisteredWorkspaces(data.workspaces);
    setWorkspaceNames(
      Object.fromEntries(
        data.workspaces.map((item) => [item.path, item.name])
      )
    );
  }

  async function renameWorkspace(path: string) {
    const name = workspaceNames[path] ?? "";
    setWorkspaceStatus(null);
    try {
      const response = await fetch("/api/workspaces", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ path, name })
      });
      const data = (await response.json()) as {
        detail?: string;
        workspace?: { name: string; path: string };
        workspaces?: RegisteredWorkspace[];
      };
      if (!response.ok || !data.workspaces) {
        throw new Error(data.detail ?? "无法重命名工作区。");
      }
      setRegisteredWorkspaces(data.workspaces);
      setWorkspace((current) =>
        current && current.path === path
          ? { ...current, name: data.workspace?.name ?? name }
          : current
      );
      setWorkspaceStatus("工作区名称已保存");
    } catch (renameError) {
      setWorkspaceStatus(
        renameError instanceof Error
          ? renameError.message
          : "无法重命名工作区。"
      );
    }
  }

  async function removeWorkspaceRegistration(path: string) {
    setWorkspaceStatus(null);
    try {
      const response = await fetch(
        `/api/workspaces?path=${encodeURIComponent(path)}`,
        { method: "DELETE" }
      );
      const data = (await response.json()) as {
        detail?: string;
        workspaces?: RegisteredWorkspace[];
      };
      if (!response.ok || !data.workspaces) {
        throw new Error(data.detail ?? "无法移除工作区注册。");
      }
      const removedActive = workspace?.path === path;
      setRegisteredWorkspaces(data.workspaces);
      if (removedActive) {
        setWorkspace(null);
        setTree([]);
        setOpenFile(null);
        setOpenTextFile(null);
        setOpenPdfPath(null);
        setWorkspacePath("");
      }
      setWorkspaceStatus("已移除注册记录，磁盘文件未删除");
    } catch (removeError) {
      setWorkspaceStatus(
        removeError instanceof Error
          ? removeError.message
          : "无法移除工作区注册。"
      );
    }
  }

  function modelPayload() {
    return {
      base_url: modelBaseUrl,
      model: modelName,
      api_key: modelApiKey,
      embedding_model: embeddingModel,
      embedding_enabled: embeddingEnabled
    };
  }

  async function testModelConnection() {
    setModelTesting(true);
    setModelStatus(null);
    setModelError(null);
    try {
      const response = await fetch("/api/model-settings/test", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(modelPayload())
      });
      const data = (await response.json()) as {
        detail?: string;
        ok?: boolean;
      };
      if (!response.ok || !data.ok) {
        throw new Error(data.detail ?? "连接失败。");
      }
      setModelStatus("连接成功");
    } catch (modelTestError) {
      setModelError(
        modelTestError instanceof Error ? modelTestError.message : "连接失败。"
      );
    } finally {
      setModelTesting(false);
    }
  }

  async function saveModelSettings(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setModelSaving(true);
    setModelStatus(null);
    setModelError(null);
    try {
      const response = await fetch("/api/model-settings", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(modelPayload())
      });
      const data = (await response.json()) as ModelSettings & {
        detail?: string;
      };
      if (!response.ok) {
        throw new Error(data.detail ?? "无法保存模型设置。");
      }
      setHasModelApiKey(data.hasApiKey);
      setEmbeddingModel(data.embeddingModel);
      setEmbeddingEnabled(data.embeddingEnabled);
      setModelApiKey("");
      setSettingsOpen(false);
    } catch (modelSaveError) {
      setModelError(
        modelSaveError instanceof Error
          ? modelSaveError.message
          : "无法保存模型设置。"
      );
    } finally {
      setModelSaving(false);
    }
  }

  async function testEmbeddingConnection() {
    setEmbeddingTesting(true);
    setModelStatus(null);
    setModelError(null);
    try {
      const response = await fetch("/api/model-settings/test-embedding", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(modelPayload())
      });
      const data = (await response.json()) as {
        detail?: string;
        ok?: boolean;
      };
      if (!response.ok || !data.ok) {
        throw new Error(data.detail ?? "向量模型连接失败。");
      }
      setModelStatus("向量模型连接成功");
    } catch (embeddingTestError) {
      setModelError(
        embeddingTestError instanceof Error
          ? embeddingTestError.message
          : "向量模型连接失败。"
      );
    } finally {
      setEmbeddingTesting(false);
    }
  }

  async function saveQiniuSettings(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSettingsError(null);
    setSettingsStatus(null);

    try {
      const response = await fetch("/api/settings/qiniu", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          bucket: qiniuBucket,
          domain: qiniuDomain,
          access_key: qiniuAccessKey || null,
          secret_key: qiniuSecretKey || null
        })
      });
      const data = (await response.json()) as QiniuSettings & {
        detail?: string;
      };
      if (!response.ok) {
        throw new Error(data.detail ?? "无法保存七牛配置。");
      }

      setQiniuSettings(data);
      setQiniuBucket(data.bucket);
      setQiniuDomain(data.domain);
      setQiniuAccessKey("");
      setQiniuSecretKey("");
      setSettingsStatus("七牛配置已保存");
    } catch (settingsSaveError) {
      setSettingsError(
        settingsSaveError instanceof Error
          ? settingsSaveError.message
          : "无法保存七牛配置。"
      );
    }
  }

  return (
    <main className="app-shell">
      <header className="topbar">
        <div className="brand-mark">SN</div>
        <div className="brand-name">StudyNotes</div>
        <div className="workspace-label">
          {workspace?.name ?? "学习工作区"}
        </div>
        <div className="top-actions">
          <button
            className="search-button"
            type="button"
            disabled={!workspace}
            onClick={() => setSearchOpen(true)}
          >
            <Search aria-hidden="true" size={16} />
            <span>搜索</span>
            <kbd>⌘ K</kbd>
          </button>
          <button
            className="icon-button"
            type="button"
            aria-label="设置"
            onClick={() => void openSettings()}
          >
            <Settings2 aria-hidden="true" size={17} />
          </button>
        </div>
      </header>

      <div className="workspace-body">
        <nav className="rail" aria-label="主导航">
          <button
            aria-label="资料"
            aria-pressed={mainView === "workspace"}
            className={`rail-button ${
              mainView === "workspace" ? "is-active" : ""
            }`}
            type="button"
            onClick={() => setMainView("workspace")}
          >
            <Library aria-hidden="true" size={18} />
          </button>
          <button
            aria-label="复习"
            aria-pressed={mainView === "review"}
            className={`rail-button ${mainView === "review" ? "is-active" : ""}`}
            disabled={!workspace}
            type="button"
            onClick={() => setMainView("review")}
          >
            <BookOpenText aria-hidden="true" size={18} />
          </button>
        </nav>

        <aside className="sidebar">
          <div className="sidebar-heading">
            <span>资料</span>
            <div className="sidebar-actions">
              <button
                aria-label="今日笔记"
                className="sidebar-action"
                disabled={!workspace || working}
                title="打开今日笔记"
                type="button"
                onClick={() => void createDailyNote()}
              >
                <CalendarDays aria-hidden="true" size={14} />
              </button>
              <button
                aria-label="新建页面"
                className="sidebar-action"
                disabled={!workspace}
                title="新建页面"
                type="button"
                onClick={() => {
                  setNewPageName("未命名.md");
                  setCreateDialogOpen(true);
                }}
              >
                <Plus aria-hidden="true" size={15} />
              </button>
              <button
                aria-label="重命名或移动"
                className="sidebar-action"
                disabled={!workspace || !selectedNode}
                title="重命名或移动"
                type="button"
                onClick={() => {
                  if (!selectedNode) {
                    return;
                  }
                  setMovePath(selectedNode.path);
                  setMoveDialogOpen(true);
                }}
              >
                <Pencil aria-hidden="true" size={14} />
              </button>
              <button
                aria-label="删除"
                className="sidebar-action"
                disabled={!workspace || selectedNode?.type !== "file"}
                title="删除"
                type="button"
                onClick={() => setDeleteDialogOpen(true)}
              >
                <Trash2 aria-hidden="true" size={14} />
              </button>
            </div>
          </div>
          {tree.length > 0 ? (
            <TreeNodes
              activePath={openFile?.path ?? openTextFile?.path ?? openPdfPath}
              nodes={visibleTree}
              onOpenFile={(node) => void openFileNode(node)}
              onSelect={setSelectedNode}
              selectedPath={selectedNode?.path ?? null}
            />
          ) : (
            <p className="sidebar-empty">打开学习工作区后显示目录与页面。</p>
          )}
          {tags.length > 0 ? (
            <section className="notebook-tags" aria-label="标签筛选">
              <div className="notebook-tags-heading">
                <strong>标签</strong>
                {activeTag ? (
                  <button type="button" onClick={() => void applyTag(activeTag)}>
                    清除
                  </button>
                ) : null}
              </div>
              <div className="notebook-tag-list">
                {tags.map((tag) => (
                  <button
                    aria-pressed={activeTag === tag}
                    className={activeTag === tag ? "is-active" : ""}
                    key={tag}
                    type="button"
                    onClick={() => void applyTag(tag)}
                  >
                    {tag}
                  </button>
                ))}
              </div>
            </section>
          ) : null}
          {dailyStatus ? (
            <p className="notebook-status" role="status">
              {dailyStatus}
            </p>
          ) : null}
          {workspace ? (
            <p className="workspace-path" title={workspace.path}>
              {workspace.path}
            </p>
          ) : null}
        </aside>

        <section
          className={`content ${
            mainView === "review"
              ? "is-review"
              : openFile || openTextFile || openPdfPath
                ? "has-reading-surface"
                : ""
          }`}
        >
          {mainView === "review" ? (
            <ReviewPage
              onCitationSelect={handleCitationSelect}
              workspacePath={workspace?.path ?? ""}
            />
          ) : loading ? (
            <div className="center-state" role="status">
              <LoaderCircle className="spin" aria-hidden="true" size={22} />
              <span>正在连接本地服务…</span>
            </div>
          ) : openingFile ? (
            <div className="center-state" role="status">
              <LoaderCircle className="spin" aria-hidden="true" size={22} />
              <span>正在打开页面…</span>
            </div>
          ) : openPdfPath ? (
            <div className="reading-workspace is-pdf">
              <PdfViewer
                citationTargetQuote={pdfCitationTarget?.quote}
                key={`${openPdfPath}:${pdfInitialPage}:${
                  pdfCitationTarget?.quote ?? ""
                }`}
                initialPage={pdfInitialPage}
                path={openPdfPath}
                onTutorSelectionChange={(selection) => {
                  setTutorSelection(selection);
                  setPdfCitationTarget(null);
                }}
              />
              <TutorPanel
                initialSessionId={sessionTargetId}
                onCitationSelect={handleCitationSelect}
                path={openPdfPath}
                selection={tutorSelection}
                sourceOptions={sourceOptions}
              />
            </div>
          ) : openTextFile ? (
            <div className="reading-workspace">
              <article className="document text-document">
                <header className="document-header">
                  <span>{openTextFile.path}</span>
                  <span className="blocknote-label">纯文本 · 只读</span>
                </header>
                <p className="text-readonly-notice">
                  纯文本资料为只读；需要编辑时请另存为 Markdown 页面。
                </p>
                <div className="text-reader" aria-label="纯文本阅读器">
                  {openTextFile.content.split(/\r?\n/).map((line, index) =>
                    line ? (
                      <p
                        key={`${index}:${line}`}
                        onMouseUp={(event) => selectTextLine(event, line)}
                      >
                        {line}
                      </p>
                    ) : (
                      <br key={`line-${index}`} />
                    )
                  )}
                </div>
              </article>
              <TutorPanel
                initialSessionId={sessionTargetId}
                onCitationSelect={handleCitationSelect}
                path={openTextFile.path}
                selection={tutorSelection}
                sourceOptions={sourceOptions}
              />
            </div>
          ) : openFile ? (
            <div className="reading-workspace">
              <article className="document">
                <header className="document-header">
                  <span>{openFile.path}</span>
                  <span className="blocknote-label">BlockNote</span>
                </header>
                <BlockNoteEditor
                  citationTargetId={citationTarget?.blockId}
                  citationTargetQuote={citationTarget?.quote}
                  key={`${openFile.path}:${markdownSearchTarget?.id ?? ""}`}
                  initialDocument={openFile}
                  initialSearchTarget={markdownSearchTarget}
                  onPathAvailability={handlePathAvailability}
                  onTutorSelectionChange={(selection) => {
                    setTutorSelection(selection);
                    setCitationTarget(null);
                  }}
                />
                <section className="backlink-tools">
                  <button
                    aria-expanded={backlinksOpen}
                    type="button"
                    onClick={() => setBacklinksOpen((current) => !current)}
                  >
                    <Link2 aria-hidden="true" size={14} />
                    反向链接
                  </button>
                  {backlinks && backlinks.backlinks.length > 0 ? (
                    <span>{backlinks.backlinks.length} 条</span>
                  ) : null}
                </section>
                {backlinksOpen ? (
                  <section
                    aria-label="反向链接"
                    className="backlink-panel"
                    role="region"
                  >
                    <h3>指向当前页面的链接</h3>
                    {backlinks && backlinks.backlinks.length > 0 ? (
                      backlinks.backlinks.map((link) => (
                        <button
                          key={`${link.sourcePath}:${link.syntax}:${link.context}`}
                          type="button"
                          onClick={() => {
                            const node = findTreeNode(tree, link.sourcePath);
                            if (node) {
                              void openFileNode(node);
                            }
                          }}
                        >
                          <span>
                            {link.sourcePath} ·{" "}
                            {link.syntax === "wiki" ? "Wiki 链接" : "相对链接"}
                          </span>
                          <p>{link.context}</p>
                        </button>
                      ))
                    ) : (
                      <p>还没有其他页面链接到这里。</p>
                    )}
                    {backlinks && backlinks.outgoing.length > 0 ? (
                      <>
                        <h3>当前页面的外部链接</h3>
                        {backlinks.outgoing.map((link) => (
                          <div
                            className="backlink-outgoing"
                            key={`${link.targetPath}:${link.syntax}`}
                          >
                            {link.targetPath} · {link.label}
                          </div>
                        ))}
                      </>
                    ) : null}
                  </section>
                ) : null}
              </article>
              <TutorPanel
                initialSessionId={sessionTargetId}
                onCitationSelect={handleCitationSelect}
                path={openFile.path}
                selection={tutorSelection}
                sourceOptions={sourceOptions}
              />
            </div>
          ) : workspace && onboardingCompleted === false ? (
            <section
              aria-label="首次设置"
              className="onboarding-panel"
            >
              <p className="eyebrow">三步开始</p>
              <h1>先完成资料、模型和图片设置</h1>
              <p className="picker-copy">
                学习记录、索引和会话保存在本机。只有模型推理与图片上传会访问网络。
              </p>
              <div className="onboarding-steps">
                <article className="is-complete">
                  <span>1</span>
                  <div>
                    <strong>资料目录</strong>
                    <p>{workspace.path}</p>
                  </div>
                  <Check aria-hidden="true" size={16} />
                </article>
                <article className={onboardingStep === 2 ? "is-current" : ""}>
                  <span>2</span>
                  <div>
                    <strong>模型服务</strong>
                    <p>配置 Base URL、API Key 与聊天模型；也可以稍后设置。</p>
                  </div>
                </article>
                <article className={onboardingStep === 3 ? "is-current" : ""}>
                  <span>3</span>
                  <div>
                    <strong>七牛图片</strong>
                    <p>可选；跳过不影响阅读、编辑、辅导、练习和复习。</p>
                  </div>
                </article>
              </div>
              <label className="data-boundary-confirm">
                <input
                  aria-label="首次联网资料边界确认"
                  checked={boundaryAccepted}
                  type="checkbox"
                  onChange={(event) =>
                    void setDataBoundary(event.target.checked)
                  }
                />
                <span>
                  我了解：模型会收到当前选区、固定资料与检索片段；图片上传会把图片发送到七牛云。
                </span>
              </label>
              <div className="onboarding-actions">
                {onboardingStep === 2 ? (
                  <>
                    <button
                      className="secondary-button"
                      disabled={!boundaryAccepted}
                      type="button"
                      onClick={() => void openSettings()}
                    >
                      打开模型设置
                    </button>
                    <button
                      className="secondary-text-button"
                      type="button"
                      onClick={() => setOnboardingStep(3)}
                    >
                      稍后配置模型
                    </button>
                  </>
                ) : null}
                {onboardingStep === 3 ? (
                  <>
                    <button
                      className="secondary-button"
                      disabled={!boundaryAccepted}
                      type="button"
                      onClick={() => void openSettings()}
                    >
                      打开七牛设置
                    </button>
                    <button
                      className="primary-button"
                      type="button"
                      onClick={() => void completeOnboarding()}
                    >
                      跳过七牛并完成
                    </button>
                  </>
                ) : null}
              </div>
            </section>
          ) : workspace ? (
            <div className="empty-document">
              <h1>{workspace.name}</h1>
              <p>从左侧资料树选择一个 Markdown 页面或 PDF。</p>
            </div>
          ) : staleWorkspace ? (
            <div className="workspace-picker">
              <div className="picker-icon" aria-hidden="true">
                <FolderOpen size={24} />
              </div>
              <p className="eyebrow">路径已变化</p>
              <h1>学习工作区需要重新定位</h1>
              <p className="stale-workspace-label">原路径</p>
              <p className="stale-workspace-path">{staleWorkspace.path}</p>
              <p className="picker-copy">
                本地学习记录仍然保留，请选择改名或移动后的目录。
              </p>
              <form className="picker-form" onSubmit={openWorkspace}>
                <label htmlFor="relocated-workspace-path">
                  新的学习工作区路径
                </label>
                <div className="path-row">
                  <input
                    id="relocated-workspace-path"
                    name="relocated-workspace-path"
                    autoComplete="off"
                    spellCheck={false}
                    value={workspacePath}
                    onChange={(event) => setWorkspacePath(event.target.value)}
                  />
                  <button
                    className="primary-button"
                    type="submit"
                    disabled={submitting || workspacePath.trim().length === 0}
                  >
                    {submitting ? "正在恢复…" : "重新定位工作区"}
                  </button>
                </div>
              </form>
              {error ? <p className="error-message">{error}</p> : null}
            </div>
          ) : (
            <div className="workspace-picker">
              <div className="picker-icon" aria-hidden="true">
                <FolderOpen size={24} />
              </div>
              <p className="eyebrow">本地优先</p>
              <h1>打开你的学习空间</h1>
              <p className="picker-copy">
                选择一个本地 学习工作区，开始你的学习。
              </p>
              <form className="picker-form" onSubmit={openWorkspace}>
                <label htmlFor="workspace-path">学习工作区路径</label>
                <div className="path-row">
                  <input
                    id="workspace-path"
                    name="workspace-path"
                    placeholder="/Users/you/Documents/Study"
                    autoComplete="off"
                    spellCheck={false}
                    value={workspacePath}
                    onChange={(event) => setWorkspacePath(event.target.value)}
                  />
                  {canBrowse ? (
                    <button
                      className="secondary-button"
                      type="button"
                      aria-label="选择文件夹"
                      onClick={() => void chooseWorkspace()}
                    >
                      <FolderOpen aria-hidden="true" size={16} />
                    </button>
                  ) : null}
                  <button
                    className="primary-button"
                    type="submit"
                    disabled={submitting || workspacePath.trim().length === 0}
                  >
                    {submitting ? "正在打开…" : "打开工作区"}
                  </button>
                </div>
              </form>
              {error ? <p className="error-message">{error}</p> : null}
              <p className="privacy-note">
                资料保留在本机，学习数据 保存在本地应用目录。
              </p>
            </div>
          )}
        </section>
      </div>

      {settingsOpen ? (
        <div className="modal-backdrop">
          <div
            aria-labelledby="model-settings-title"
            aria-modal="true"
            className="dialog settings-dialog"
            role="dialog"
          >
            <div className="dialog-title-row">
              <div>
                <h2 id="model-settings-title">模型设置</h2>
                <p className="dialog-copy">
                  连接你自己配置的兼容 OpenAI 接口的模型服务。资料片段只会发送到这个服务。
                </p>
              </div>
              <button
                aria-label="收起设置面板"
                className="icon-button"
                type="button"
                onClick={() => setSettingsOpen(false)}
              >
                ×
              </button>
            </div>

            {settingsLoading ? (
              <div className="settings-loading" role="status">
                <LoaderCircle className="spin" aria-hidden="true" size={17} />
                正在读取设置…
              </div>
            ) : (
              <>
                <label className="data-boundary-confirm">
                  <input
                    aria-label="资料发送边界确认"
                    checked={boundaryAccepted}
                    type="checkbox"
                    onChange={(event) =>
                      void setDataBoundary(event.target.checked)
                    }
                  />
                  <span>
                    我了解：向模型提问时，选中的资料片段与检索上下文会发送到我配置的模型服务；上传图片时会发送到七牛云。
                  </span>
                </label>
                <form className="settings-form" onSubmit={saveModelSettings}>
                  <label htmlFor="model-base-url">Base URL</label>
                  <input
                    autoFocus
                    id="model-base-url"
                    name="model-base-url"
                    autoComplete="url"
                    placeholder="https://api.example.com/v1"
                    spellCheck={false}
                    value={modelBaseUrl}
                    onChange={(event) => setModelBaseUrl(event.target.value)}
                  />
                  <label htmlFor="model-api-key">API Key</label>
                  <input
                    id="model-api-key"
                    name="model-api-key"
                    autoComplete="new-password"
                    placeholder={
                      hasModelApiKey ? "已保存在系统安全存储，留空则不修改" : ""
                    }
                    spellCheck={false}
                    type="password"
                    value={modelApiKey}
                    onChange={(event) => setModelApiKey(event.target.value)}
                  />
                  <label htmlFor="model-name">聊天模型</label>
                  <input
                    id="model-name"
                    name="model-name"
                    autoComplete="off"
                    placeholder="gpt-4.1-mini"
                    spellCheck={false}
                    value={modelName}
                    onChange={(event) => setModelName(event.target.value)}
                  />
                  <div className="settings-toggle">
                    <input
                      checked={embeddingEnabled}
                      id="embedding-enabled"
                      name="embedding-enabled"
                      type="checkbox"
                      onChange={(event) =>
                        setEmbeddingEnabled(event.target.checked)
                      }
                    />
                    <label htmlFor="embedding-enabled">启用语义检索</label>
                    <p>关闭后只使用本地全文检索，资料仍可正常提问。</p>
                  </div>
                  <label htmlFor="embedding-model">向量模型</label>
                  <input
                    id="embedding-model"
                    name="embedding-model"
                    autoComplete="off"
                    placeholder="text-embedding-3-small"
                    spellCheck={false}
                    value={embeddingModel}
                    onChange={(event) => setEmbeddingModel(event.target.value)}
                  />
                  {modelStatus ? (
                    <p className="settings-result is-success" role="status">
                      {modelStatus}
                    </p>
                  ) : null}
                  {modelError ? (
                    <p className="settings-result is-error" role="alert">
                      {modelError}
                    </p>
                  ) : null}
                  <div className="dialog-actions">
                    <button
                      className="secondary-text-button settings-test"
                      disabled={
                        !boundaryAccepted ||
                        modelTesting ||
                        embeddingTesting ||
                        modelSaving
                      }
                      type="button"
                      onClick={() => void testModelConnection()}
                    >
                      {modelTesting ? "正在测试…" : "测试连接"}
                    </button>
                    <button
                      className="secondary-text-button settings-test"
                      disabled={
                        !boundaryAccepted ||
                        modelTesting ||
                        embeddingTesting ||
                        modelSaving
                      }
                      type="button"
                      onClick={() => void testEmbeddingConnection()}
                    >
                      {embeddingTesting
                        ? "正在测试向量模型…"
                        : "测试向量模型"}
                    </button>
                    <button
                      className="secondary-text-button"
                      type="button"
                      onClick={() => setSettingsOpen(false)}
                    >
                      取消
                    </button>
                    <button
                      className="primary-button"
                      disabled={modelSaving || !boundaryAccepted}
                      type="submit"
                    >
                      {modelSaving ? "正在保存…" : "保存设置"}
                    </button>
                  </div>
                </form>

                <section className="settings-section">
                  <h2 id="settings-title">七牛图片存储</h2>
                  <p className="dialog-copy">
                    新图片会上传到公开读桶。Access Key 与 Secret Key
                    只写入系统安全存储，不会进入页面或配置数据库。
                  </p>
                  <form className="settings-form" onSubmit={saveQiniuSettings}>
                    <label htmlFor="qiniu-bucket">七牛桶</label>
                    <input
                      id="qiniu-bucket"
                      name="qiniu-bucket"
                      autoComplete="off"
                      spellCheck={false}
                      value={qiniuBucket}
                      onChange={(event) => setQiniuBucket(event.target.value)}
                    />
                    <label htmlFor="qiniu-domain">访问域名</label>
                    <input
                      id="qiniu-domain"
                      name="qiniu-domain"
                      autoComplete="url"
                      placeholder="https://images.example.com"
                      spellCheck={false}
                      value={qiniuDomain}
                      onChange={(event) => setQiniuDomain(event.target.value)}
                    />
                    <div className="settings-grid">
                      <div>
                        <label htmlFor="qiniu-access-key">Access Key</label>
                        <input
                          id="qiniu-access-key"
                          name="qiniu-access-key"
                          autoComplete="new-password"
                          placeholder={
                            qiniuSettings?.hasAccessKey
                              ? "已保存在系统安全存储"
                              : ""
                          }
                          spellCheck={false}
                          type="password"
                          value={qiniuAccessKey}
                          onChange={(event) =>
                            setQiniuAccessKey(event.target.value)
                          }
                        />
                      </div>
                      <div>
                        <label htmlFor="qiniu-secret-key">Secret Key</label>
                        <input
                          id="qiniu-secret-key"
                          name="qiniu-secret-key"
                          autoComplete="new-password"
                          placeholder={
                            qiniuSettings?.hasSecretKey
                              ? "已保存在系统安全存储"
                              : ""
                          }
                          spellCheck={false}
                          type="password"
                          value={qiniuSecretKey}
                          onChange={(event) =>
                            setQiniuSecretKey(event.target.value)
                          }
                        />
                      </div>
                    </div>
                    {settingsError ? (
                      <p className="error-message">{settingsError}</p>
                    ) : null}
                    {settingsStatus ? (
                      <p className="settings-status" role="status">
                        {settingsStatus}
                      </p>
                    ) : null}
                    <div className="dialog-actions">
                      <button
                        className="secondary-text-button"
                        type="button"
                        onClick={() => setSettingsOpen(false)}
                      >
                        关闭
                      </button>
                      <button
                        className="primary-button"
                        type="submit"
                      disabled={
                        !boundaryAccepted ||
                        !qiniuBucket.trim() ||
                        !qiniuDomain.trim()
                      }
                      >
                        保存七牛配置
                      </button>
                    </div>
                  </form>
                </section>

                <section className="settings-section" aria-label="工作区管理">
                  <h2 id="workspace-management-title">工作区</h2>
                  <p className="dialog-copy">
                    同一时间只激活一个本地资料目录。移除注册记录不会删除磁盘文件。
                  </p>
                  <div className="workspace-management-list">
                    {registeredWorkspaces.map((workspaceItem) => (
                      <div
                        className={`workspace-management-row ${
                          workspaceItem.active ? "is-active" : ""
                        }`}
                        key={workspaceItem.path}
                      >
                        <div>
                          <input
                            aria-label={`工作区名称 ${workspaceItem.path}`}
                            value={workspaceNames[workspaceItem.path] ?? ""}
                            onChange={(event) =>
                              setWorkspaceNames((current) => ({
                                ...current,
                                [workspaceItem.path]: event.target.value
                              }))
                            }
                          />
                          <small title={workspaceItem.path}>
                            {workspaceItem.path}
                          </small>
                        </div>
                        <div className="workspace-management-actions">
                          <button
                            className="secondary-text-button"
                            disabled={workspaceItem.active}
                            type="button"
                            onClick={() =>
                              void activateWorkspacePath(workspaceItem.path)
                            }
                          >
                            {workspaceItem.active ? "当前工作区" : "切换"}
                          </button>
                          <button
                            className="secondary-text-button"
                            type="button"
                            onClick={() => void renameWorkspace(workspaceItem.path)}
                          >
                            保存名称
                          </button>
                          <button
                            className="danger-text-button"
                            type="button"
                            onClick={() =>
                              void removeWorkspaceRegistration(
                                workspaceItem.path
                              )
                            }
                          >
                            移除注册
                          </button>
                        </div>
                      </div>
                    ))}
                  </div>
                  <div className="workspace-add-row">
                    <label htmlFor="new-workspace-path">添加本地工作区</label>
                    <div className="path-row">
                      <input
                        id="new-workspace-path"
                        placeholder="/Users/you/Documents/另一个学习目录"
                        value={newWorkspacePath}
                        onChange={(event) => setNewWorkspacePath(event.target.value)}
                      />
                      <button
                        className="secondary-button"
                        disabled={!newWorkspacePath.trim()}
                        type="button"
                        onClick={() =>
                          void activateWorkspacePath(newWorkspacePath.trim())
                        }
                      >
                        添加并切换
                      </button>
                    </div>
                  </div>
                  {workspaceStatus ? (
                    <p className="settings-status" role="status">
                      {workspaceStatus}
                    </p>
                  ) : null}
                </section>

                <BackupSettings disabled={!workspace} />
              </>
            )}
          </div>
        </div>
      ) : null}

      {createDialogOpen ? (
        <div className="modal-backdrop">
          <div
            aria-labelledby="create-page-title"
            aria-modal="true"
            className="dialog"
            role="dialog"
          >
            <h2 id="create-page-title">新建 Markdown 页面</h2>
            <p className="dialog-copy">
              创建位置：{selectedDirectoryPath() || workspace?.name || "工作区根目录"}
            </p>
            <form onSubmit={createPage}>
              <label htmlFor="page-template">页面模板</label>
              <select
                id="page-template"
                name="page-template"
                value={selectedTemplate}
                onChange={(event) => setSelectedTemplate(event.target.value)}
              >
                <option value="">空白页面</option>
                {templates.map((template) => (
                  <option key={template.path} value={template.path}>
                    {template.name}
                  </option>
                ))}
              </select>
              <label htmlFor="new-page-name">页面名称</label>
              <input
                autoFocus
                id="new-page-name"
                name="new-page-name"
                value={newPageName}
                onChange={(event) => setNewPageName(event.target.value)}
              />
              {error ? <p className="error-message">{error}</p> : null}
              <div className="dialog-actions">
                <button
                  className="secondary-text-button"
                  type="button"
                  onClick={() => setCreateDialogOpen(false)}
                >
                  取消
                </button>
                <button
                  className="primary-button"
                  disabled={working || newPageName.trim().length === 0}
                  type="submit"
                >
                  {working ? "正在创建…" : "创建页面"}
                </button>
              </div>
            </form>
          </div>
        </div>
      ) : null}

      {moveDialogOpen ? (
        <div className="modal-backdrop">
          <div
            aria-labelledby="move-entry-title"
            aria-modal="true"
            className="dialog"
            role="dialog"
          >
            <h2 id="move-entry-title">重命名或移动</h2>
            <p className="dialog-copy">
              输入相对于工作区的新路径。目录使用名称，页面保留原后缀。
            </p>
            <form onSubmit={moveEntry}>
              <label htmlFor="new-entry-path">新相对路径</label>
              <input
                autoFocus
                id="new-entry-path"
                name="new-entry-path"
                value={movePath}
                onChange={(event) => setMovePath(event.target.value)}
              />
              {error ? <p className="error-message">{error}</p> : null}
              <div className="dialog-actions">
                <button
                  className="secondary-text-button"
                  type="button"
                  onClick={() => setMoveDialogOpen(false)}
                >
                  取消
                </button>
                <button
                  className="primary-button"
                  disabled={working || movePath.trim().length === 0}
                  type="submit"
                >
                  {working ? "正在保存…" : "保存路径"}
                </button>
              </div>
            </form>
          </div>
        </div>
      ) : null}

      {deleteDialogOpen && selectedNode ? (
        <div className="modal-backdrop">
          <div
            aria-labelledby="delete-entry-title"
            aria-modal="true"
            className="dialog"
            role="dialog"
          >
            <h2 id="delete-entry-title">
              删除 Markdown 页面
            </h2>
            <p className="dialog-copy">
              将永久删除“{selectedNode.path}”。这个操作无法撤销。
            </p>
            {error ? <p className="error-message">{error}</p> : null}
            <div className="dialog-actions">
              <button
                className="secondary-text-button"
                type="button"
                onClick={() => setDeleteDialogOpen(false)}
              >
                取消
              </button>
              <button
                className="danger-button"
                disabled={working}
                type="button"
                onClick={() => void deleteEntry()}
              >
                {working ? "正在删除…" : "确认删除"}
              </button>
            </div>
          </div>
        </div>
      ) : null}

      <SearchDialog
        open={searchOpen}
        onClose={() => setSearchOpen(false)}
        onSelect={(result) => void openSearchResult(result)}
      />
    </main>
  );
}
