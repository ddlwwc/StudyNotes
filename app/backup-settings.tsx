"use client";

import {
  Archive,
  CheckCircle2,
  LoaderCircle,
  RotateCcw,
  ShieldAlert,
  ShieldCheck,
  Upload
} from "lucide-react";
import { useRef, useState } from "react";
import type { ChangeEvent } from "react";

type ExportResult = {
  createdAt: string;
  filename: string;
  path: string;
  size: number;
};

type RestoreCounts = {
  documentDrafts: number;
  gapRecords: number;
  learningSessions: number;
  practiceAttempts: number;
  practiceItems: number;
  reviewResults: number;
  sessionMessages: number;
  sourceCitations: number;
};

type SidecarIssue = {
  message: string;
  path: string;
  status: string;
};

type PreviewResponse = {
  packageSha256: string;
  preview: {
    canRestore: boolean;
    counts: RestoreCounts;
    createdAt: string;
    requiresSecretReconfiguration: boolean;
    secretMessage: string;
    settings: {
      model: {
        baseUrl: string;
        embeddingEnabled: boolean;
        embeddingModel: string;
        model: string;
      };
      qiniu: {
        bucket: string;
        domain: string;
      };
    };
    sidecars: {
      canRestore: boolean;
      issues: SidecarIssue[];
      matched: number;
      total: number;
    };
    sourceWorkspace: {
      name: string;
      path: string;
    };
    targetWorkspace: {
      name: string;
      path: string;
    };
  };
  previewId: string;
  rollback: {
    path: string;
  };
};

type RestoreResult = {
  counts: RestoreCounts;
  indexesWillRebuild: boolean;
  rollback: {
    path: string;
  };
  secretMessage: string;
};

const countLabels: Array<[keyof RestoreCounts, string]> = [
  ["learningSessions", "学习会话"],
  ["sessionMessages", "会话消息"],
  ["sourceCitations", "资料引用"],
  ["practiceItems", "练习项"],
  ["practiceAttempts", "练习作答"],
  ["gapRecords", "知识缺口"],
  ["reviewResults", "复习结果"],
  ["documentDrafts", "编辑草稿"]
];

export function BackupSettings({ disabled }: { disabled: boolean }) {
  const [exporting, setExporting] = useState(false);
  const [exportResult, setExportResult] = useState<ExportResult | null>(null);
  const [previewing, setPreviewing] = useState(false);
  const [preview, setPreview] = useState<PreviewResponse | null>(null);
  const [restoreFile, setRestoreFile] = useState<File | null>(null);
  const [restoring, setRestoring] = useState(false);
  const [restoreResult, setRestoreResult] = useState<RestoreResult | null>(
    null
  );
  const [error, setError] = useState<string | null>(null);
  const fileInput = useRef<HTMLInputElement>(null);

  async function exportBackup() {
    setExporting(true);
    setExportResult(null);
    setError(null);
    try {
      const response = await fetch("/api/backups/export", {
        method: "POST"
      });
      const data = (await response.json()) as ExportResult & {
        detail?: string;
      };
      if (!response.ok) {
        throw new Error(data.detail ?? "无法导出备份。");
      }
      setExportResult(data);
    } catch (exportError) {
      setError(
        exportError instanceof Error ? exportError.message : "无法导出备份。"
      );
    } finally {
      setExporting(false);
    }
  }

  async function chooseBackup(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    if (!file) {
      return;
    }
    setRestoreFile(file);
    setPreviewing(true);
    setPreview(null);
    setRestoreResult(null);
    setError(null);
    try {
      const body = new FormData();
      body.append("file", file);
      const response = await fetch("/api/backups/preview", {
        method: "POST",
        body
      });
      const data = (await response.json()) as PreviewResponse & {
        detail?: string;
      };
      if (!response.ok) {
        throw new Error(data.detail ?? "无法读取备份包。");
      }
      setPreview(data);
    } catch (previewError) {
      setRestoreFile(null);
      setError(
        previewError instanceof Error
          ? previewError.message
          : "无法读取备份包。"
      );
    } finally {
      setPreviewing(false);
      event.target.value = "";
    }
  }

  async function restoreBackup() {
    if (!restoreFile || !preview) {
      return;
    }
    setRestoring(true);
    setRestoreResult(null);
    setError(null);
    try {
      const body = new FormData();
      body.append("preview_id", preview.previewId);
      body.append("file", restoreFile);
      const response = await fetch("/api/backups/restore", {
        method: "POST",
        body
      });
      const data = (await response.json()) as RestoreResult & {
        detail?: string;
      };
      if (!response.ok) {
        throw new Error(data.detail ?? "无法恢复备份。");
      }
      setRestoreResult(data);
      setPreview(null);
      setRestoreFile(null);
    } catch (restoreError) {
      setError(
        restoreError instanceof Error
          ? restoreError.message
          : "无法恢复备份。"
      );
    } finally {
      setRestoring(false);
    }
  }

  return (
    <section
      aria-labelledby="backup-settings-title"
      className="settings-section backup-settings"
    >
      <div className="backup-heading">
        <span className="backup-heading-icon" aria-hidden="true">
          <Archive size={18} />
        </span>
        <div>
          <h2 id="backup-settings-title">学习数据备份</h2>
          <p className="dialog-copy">
            导出一个本地备份包，包含学习记录和非秘密设置；模型与七牛密钥不会进入备份。
          </p>
        </div>
      </div>

      <div className="backup-actions">
        <button
          className="primary-button backup-export-button"
          disabled={disabled || exporting}
          type="button"
          onClick={() => void exportBackup()}
        >
          {exporting ? (
            <LoaderCircle className="spin" aria-hidden="true" size={16} />
          ) : (
            <Archive aria-hidden="true" size={16} />
          )}
          {exporting ? "正在导出…" : "导出备份"}
        </button>
        <p className="backup-safety-note">
          <ShieldCheck aria-hidden="true" size={15} />
          API Key、Access Key、Secret Key 和 Authorization 始终留在系统安全存储中。
        </p>
      </div>

      <div className="backup-restore-block">
        <div className="backup-restore-heading">
          <Upload aria-hidden="true" size={16} />
          <h3>从备份恢复</h3>
        </div>
        <p>
          先预览来源、数据范围与文件校验，再写入当前工作区。预览时会自动创建回滚副本。
        </p>
        <button
          className="secondary-text-button backup-choose-button"
          disabled={disabled || previewing || restoring}
          type="button"
          onClick={() => fileInput.current?.click()}
        >
          {previewing ? (
            <LoaderCircle className="spin" aria-hidden="true" size={16} />
          ) : (
            <Upload aria-hidden="true" size={16} />
          )}
          {previewing ? "正在读取备份…" : "选择备份包"}
        </button>
        <input
          ref={fileInput}
          aria-label="选择备份包"
          accept=".gz,.studynotes,.studynotes-backup"
          className="backup-file-input"
          type="file"
          onChange={(event) => void chooseBackup(event)}
        />
      </div>

      {disabled ? (
        <p className="backup-hint">打开笔记本工作区后可以导出当前学习数据。</p>
      ) : null}
      {error ? (
        <p className="settings-result is-error" role="alert">
          {error}
        </p>
      ) : null}
      {exportResult ? (
        <div
          className="backup-result"
          data-backup-path={exportResult.path}
          role="status"
        >
          <strong>备份已创建</strong>
          <code>{exportResult.path}</code>
          <span>{exportResult.filename}</span>
        </div>
      ) : null}

      {preview ? (
        <div className="backup-preview">
          <div className="backup-preview-heading">
            <div>
              <span className="backup-preview-eyebrow">备份包已校验</span>
              <h3>恢复范围</h3>
            </div>
            <span
              className={`backup-readiness ${
                preview.preview.canRestore ? "is-ready" : "is-blocked"
              }`}
            >
              {preview.preview.canRestore ? "可以恢复" : "需要先修复校验"}
            </span>
          </div>

          <div className="backup-workspace-swap">
            <div>
              <span>备份来源</span>
              <strong>{preview.preview.sourceWorkspace.name}</strong>
              <code>{preview.preview.sourceWorkspace.path}</code>
            </div>
            <span aria-hidden="true">→</span>
            <div>
              <span>当前工作区</span>
              <strong>{preview.preview.targetWorkspace.name}</strong>
              <code>{preview.preview.targetWorkspace.path}</code>
            </div>
          </div>

          <div className="backup-count-grid">
            {countLabels.map(([key, label]) => (
              <div key={key}>
                <strong>{preview.preview.counts[key]}</strong>
                <span>{label}</span>
              </div>
            ))}
          </div>

          <div className="backup-check-summary">
            <ShieldCheck aria-hidden="true" size={16} />
            <span>
              页面结构与源文件校验：
              {preview.preview.sidecars.matched} /{" "}
              {preview.preview.sidecars.total} 匹配
            </span>
          </div>

          {preview.preview.sidecars.issues.length > 0 ? (
            <div className="backup-issues" role="alert">
              <ShieldAlert aria-hidden="true" size={16} />
              <div>
                <strong>当前工作区文件与备份不一致</strong>
                {preview.preview.sidecars.issues.slice(0, 5).map((issue) => (
                  <p key={`${issue.path}-${issue.status}`}>
                    {issue.path}：{issue.message}
                  </p>
                ))}
              </div>
            </div>
          ) : null}

          <div
            className="backup-rollback"
            data-rollback-path={preview.rollback.path}
          >
            <RotateCcw aria-hidden="true" size={16} />
            <div>
              <strong>回滚副本已创建</strong>
              <code>{preview.rollback.path}</code>
            </div>
          </div>

          <p className="backup-secret-notice">
            <ShieldAlert aria-hidden="true" size={15} />
            {preview.preview.secretMessage}
          </p>

          <div className="backup-preview-actions">
            <button
              className="secondary-text-button"
              disabled={restoring}
              type="button"
              onClick={() => {
                setPreview(null);
                setRestoreFile(null);
                setError(null);
              }}
            >
              取消
            </button>
            <button
              className="primary-button"
              disabled={!preview.preview.canRestore || restoring}
              type="button"
              onClick={() => void restoreBackup()}
            >
              {restoring ? (
                <LoaderCircle className="spin" aria-hidden="true" size={16} />
              ) : (
                <RotateCcw aria-hidden="true" size={16} />
              )}
              {restoring ? "正在恢复…" : "确认恢复"}
            </button>
          </div>
        </div>
      ) : null}

      {restoreResult ? (
        <div
          className="backup-restore-success"
          data-backup-restored="true"
          role="status"
        >
          <CheckCircle2 aria-hidden="true" size={18} />
          <div>
            <strong>恢复完成</strong>
            <p>{restoreResult.secretMessage}</p>
            <code>回滚副本：{restoreResult.rollback.path}</code>
          </div>
        </div>
      ) : null}
    </section>
  );
}
