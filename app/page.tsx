"use client";

import {
  BookOpenText,
  ChevronDown,
  ChevronRight,
  FileText,
  FolderOpen,
  Library,
  LoaderCircle,
  Search,
  Settings2
} from "lucide-react";
import { useEffect, useState } from "react";
import type { FormEvent } from "react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";

type TreeNode = {
  name: string;
  path: string;
  type: "directory" | "file";
  children?: TreeNode[];
};

type WorkspaceState = {
  tree: TreeNode[];
  workspace: null | {
    name: string;
    path: string;
  };
};

type OpenFile = {
  content: string;
  path: string;
  title: string;
};

function TreeNodes({
  activePath,
  nodes,
  onOpenFile,
  depth = 0
}: {
  activePath: string | null;
  nodes: TreeNode[];
  onOpenFile: (node: TreeNode) => void;
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
              className={`tree-row ${node.type === "file" ? "is-file" : ""} ${
                activePath === node.path ? "is-active" : ""
              }`}
              style={{ paddingLeft: `${8 + depth * 16}px` }}
              type="button"
              onClick={() => {
                if (node.type === "directory") {
                  setCollapsed((current) => ({
                    ...current,
                    [node.path]: !isCollapsed
                  }));
                } else {
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
  const [tree, setTree] = useState<TreeNode[]>([]);
  const [openFile, setOpenFile] = useState<OpenFile | null>(null);
  const [workspacePath, setWorkspacePath] = useState("");
  const [canBrowse, setCanBrowse] = useState(false);
  const [loading, setLoading] = useState(true);
  const [openingFile, setOpeningFile] = useState(false);
  const [submitting, setSubmitting] = useState(false);
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
          setTree(data.tree);
          if (data.workspace) {
            setWorkspacePath(data.workspace.path);
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
    setCanBrowse(Boolean(window.studyNotes));
  }, []);

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
      setTree(data.tree);
      setOpenFile(null);
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

  async function openMarkdown(node: TreeNode) {
    setOpeningFile(true);
    setError(null);

    try {
      const response = await fetch(
        `/api/file?path=${encodeURIComponent(node.path)}`
      );
      const data = (await response.json()) as OpenFile & { detail?: string };
      if (!response.ok) {
        throw new Error(data.detail ?? "无法读取这个 Markdown 页面。");
      }

      setOpenFile(data);
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

  async function chooseWorkspace() {
    const selected = await window.studyNotes?.chooseWorkspaceDirectory();
    if (selected) {
      setWorkspacePath(selected);
      setError(null);
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
          <button className="search-button" type="button" disabled>
            <Search aria-hidden="true" size={16} />
            <span>搜索</span>
            <kbd>⌘ K</kbd>
          </button>
          <button className="icon-button" type="button" aria-label="设置" disabled>
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
            <FolderOpen aria-hidden="true" size={15} />
          </div>
          {tree.length > 0 ? (
            <TreeNodes
              activePath={openFile?.path ?? null}
              nodes={tree}
              onOpenFile={(node) => void openMarkdown(node)}
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
          ) : openFile ? (
            <article className="document">
              <header className="document-header">
                <span>{openFile.path}</span>
                <button className="read-only-label" type="button" disabled>
                  只读
                </button>
              </header>
              <div className="markdown-body">
                <ReactMarkdown remarkPlugins={[remarkGfm]}>
                  {openFile.content}
                </ReactMarkdown>
              </div>
            </article>
          ) : workspace ? (
            <div className="empty-document">
              <h1>{workspace.name}</h1>
              <p>从左侧资料树选择一个 Markdown 页面。</p>
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
    </main>
  );
}
