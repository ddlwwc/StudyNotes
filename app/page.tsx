"use client";

import {
  BookOpenText,
  ChevronDown,
  ChevronRight,
  FileText,
  FolderOpen,
  Library,
  LoaderCircle,
  Pencil,
  Plus,
  Search,
  Settings2,
  Trash2
} from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import type { FormEvent } from "react";
import {
  BlockNoteEditor,
  type MarkdownDocument
} from "./blocknote-editor";
import { PdfViewer } from "./pdf-viewer";
import { SearchDialog, type SearchResult } from "./search-dialog";

type TreeNode = {
  name: string;
  path: string;
  type: "directory" | "file";
  kind?: "markdown" | "pdf";
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

type QiniuSettings = {
  bucket: string;
  configured: boolean;
  domain: string;
  hasAccessKey: boolean;
  hasSecretKey: boolean;
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
  const [openPdfPath, setOpenPdfPath] = useState<string | null>(null);
  const [pdfInitialPage, setPdfInitialPage] = useState(1);
  const [markdownSearchTarget, setMarkdownSearchTarget] =
    useState<SearchResult | null>(null);
  const [selectedNode, setSelectedNode] = useState<TreeNode | null>(null);
  const [workspacePath, setWorkspacePath] = useState("");
  const [canBrowse, setCanBrowse] = useState(false);
  const [loading, setLoading] = useState(true);
  const [openingFile, setOpeningFile] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [working, setWorking] = useState(false);
  const [createDialogOpen, setCreateDialogOpen] = useState(false);
  const [newPageName, setNewPageName] = useState("");
  const [moveDialogOpen, setMoveDialogOpen] = useState(false);
  const [movePath, setMovePath] = useState("");
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [qiniuSettings, setQiniuSettings] = useState<QiniuSettings | null>(
    null
  );
  const [qiniuBucket, setQiniuBucket] = useState("");
  const [qiniuDomain, setQiniuDomain] = useState("");
  const [qiniuAccessKey, setQiniuAccessKey] = useState("");
  const [qiniuSecretKey, setQiniuSecretKey] = useState("");
  const [settingsStatus, setSettingsStatus] = useState<string | null>(null);
  const [settingsError, setSettingsError] = useState<string | null>(null);
  const [searchOpen, setSearchOpen] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;

    async function loadWorkspace() {
      try {
        const response = await fetch("/api/workspace");
        if (!response.ok) {
          throw new Error("无法读取当前 Notebook workspace。");
        }
        const data = (await response.json()) as WorkspaceState;
        if (active) {
          setWorkspace(data.workspace);
          setStaleWorkspace(data.staleWorkspace);
          setTree(data.tree);
          if (data.workspace) {
            setWorkspacePath(data.workspace.path);
          } else if (data.staleWorkspace) {
            setWorkspacePath(data.staleWorkspace.path);
          }
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
        throw new Error(data.detail ?? "无法打开这个 Notebook workspace。");
      }

      setWorkspace(data.workspace);
      setStaleWorkspace(data.staleWorkspace);
      setTree(data.tree);
      setOpenFile(null);
      setOpenPdfPath(null);
      setSelectedNode(null);
      if (data.workspace) {
        setWorkspacePath(data.workspace.path);
      }
    } catch (openError) {
      setError(
        openError instanceof Error
          ? openError.message
          : "无法打开这个 Notebook workspace。"
      );
    } finally {
      setSubmitting(false);
    }
  }

  async function openFileNode(
    node: TreeNode,
    searchTarget: SearchResult | null = null
  ) {
    setOpeningFile(true);
    setError(null);

    if (node.kind === "pdf" || node.path.toLowerCase().endsWith(".pdf")) {
      setOpenFile(null);
      setMarkdownSearchTarget(null);
      setPdfInitialPage(searchTarget?.page ?? 1);
      setOpenPdfPath(node.path);
      setOpeningFile(false);
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
      setMarkdownSearchTarget(searchTarget);
      setPdfInitialPage(1);
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

  function openSearchResult(result: SearchResult) {
    setSearchOpen(false);
    const node = findTreeNode(tree, result.path);
    if (!node) {
      setError("搜索结果对应的资料已移动或删除。");
      return;
    }
    setSelectedNode(node);
    void openFileNode(node, result);
  }

  const handlePathAvailability = useCallback((available: boolean) => {
    if (!available) {
      setOpenFile(null);
      setError("当前 Markdown 页面已从磁盘移除或移动。");
    }
  }, []);

  function selectedDirectoryPath(): string {
    if (!selectedNode) {
      return "";
    }
    if (selectedNode.type === "directory") {
      return selectedNode.path;
    }
    return selectedNode.path.split("/").slice(0, -1).join("/");
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
          name: newPageName
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
    setSettingsError(null);
    setSettingsStatus(null);

    try {
      const response = await fetch("/api/settings/qiniu", { cache: "no-store" });
      const data = (await response.json()) as QiniuSettings & {
        detail?: string;
      };
      if (!response.ok) {
        throw new Error(data.detail ?? "无法读取七牛配置。");
      }
      setQiniuSettings(data);
      setQiniuBucket(data.bucket);
      setQiniuDomain(data.domain);
      setQiniuAccessKey("");
      setQiniuSecretKey("");
    } catch (settingsLoadError) {
      setSettingsError(
        settingsLoadError instanceof Error
          ? settingsLoadError.message
          : "无法读取七牛配置。"
      );
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
          {workspace?.name ?? "Notebook workspace"}
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
          <button className="rail-button is-active" type="button" aria-label="Workspace">
            <Library aria-hidden="true" size={18} />
          </button>
          <button className="rail-button" type="button" aria-label="Review" disabled>
            <BookOpenText aria-hidden="true" size={18} />
          </button>
        </nav>

        <aside className="sidebar">
          <div className="sidebar-heading">
            <span>资料</span>
            <div className="sidebar-actions">
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
              activePath={openFile?.path ?? openPdfPath}
              nodes={tree}
              onOpenFile={(node) => void openFileNode(node)}
              onSelect={setSelectedNode}
              selectedPath={selectedNode?.path ?? null}
            />
          ) : (
            <p className="sidebar-empty">打开 workspace 后显示目录与页面。</p>
          )}
          {workspace ? (
            <p className="workspace-path" title={workspace.path}>
              {workspace.path}
            </p>
          ) : null}
        </aside>

        <section className="content">
          {loading ? (
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
            <PdfViewer
              key={`${openPdfPath}:${pdfInitialPage}`}
              initialPage={pdfInitialPage}
              path={openPdfPath}
            />
          ) : openFile ? (
            <article className="document">
              <header className="document-header">
                <span>{openFile.path}</span>
                <span className="blocknote-label">BlockNote</span>
              </header>
              <BlockNoteEditor
                key={`${openFile.path}:${markdownSearchTarget?.id ?? ""}`}
                initialDocument={openFile}
                initialSearchTarget={markdownSearchTarget}
                onPathAvailability={handlePathAvailability}
              />
            </article>
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
              <h1>Notebook workspace 需要重新定位</h1>
              <p className="stale-workspace-label">原路径</p>
              <p className="stale-workspace-path">{staleWorkspace.path}</p>
              <p className="picker-copy">
                本地学习记录仍然保留，请选择改名或移动后的目录。
              </p>
              <form className="picker-form" onSubmit={openWorkspace}>
                <label htmlFor="relocated-workspace-path">
                  新的 workspace 路径
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
                选择一个本地 Notebook workspace，开始你的学习。
              </p>
              <form className="picker-form" onSubmit={openWorkspace}>
                <label htmlFor="workspace-path">Notebook workspace 路径</label>
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
                资料保留在本机，product data 保存在本地应用目录。
              </p>
            </div>
          )}
        </section>
      </div>

      {settingsOpen ? (
        <div className="modal-backdrop">
          <div
            aria-labelledby="settings-title"
            aria-modal="true"
            className="dialog settings-dialog"
            role="dialog"
          >
            <h2 id="settings-title">七牛图片存储</h2>
            <p className="dialog-copy">
              新图片会上传到公开读桶。Access Key 与 Secret Key
              只写入系统安全存储，不会进入页面或配置数据库。
            </p>
            <form className="settings-form" onSubmit={saveQiniuSettings}>
              <label htmlFor="qiniu-bucket">七牛桶</label>
              <input
                autoFocus
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
                      qiniuSettings?.hasAccessKey ? "已保存在 Keychain" : ""
                    }
                    spellCheck={false}
                    type="password"
                    value={qiniuAccessKey}
                    onChange={(event) => setQiniuAccessKey(event.target.value)}
                  />
                </div>
                <div>
                  <label htmlFor="qiniu-secret-key">Secret Key</label>
                  <input
                    id="qiniu-secret-key"
                    name="qiniu-secret-key"
                    autoComplete="new-password"
                    placeholder={
                      qiniuSettings?.hasSecretKey ? "已保存在 Keychain" : ""
                    }
                    spellCheck={false}
                    type="password"
                    value={qiniuSecretKey}
                    onChange={(event) => setQiniuSecretKey(event.target.value)}
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
                  disabled={!qiniuBucket.trim() || !qiniuDomain.trim()}
                >
                  保存七牛配置
                </button>
              </div>
            </form>
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
              创建位置：{selectedDirectoryPath() || workspace?.name || "workspace 根目录"}
            </p>
            <form onSubmit={createPage}>
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
              输入相对于 workspace 的新路径。目录使用名称，页面保留 .md 后缀。
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
        onSelect={openSearchResult}
      />
    </main>
  );
}
