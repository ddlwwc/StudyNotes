"use client";

import { CalendarPlus, LoaderCircle, X } from "lucide-react";
import { useEffect, useState } from "react";
import type { FormEvent } from "react";

export type GapRecord = {
  id: string;
  title: string;
  nextReviewAt: string | null;
};

async function readError(response: Response): Promise<string> {
  try {
    const payload = (await response.json()) as { detail?: string };
    return payload.detail ?? "无法记录知识缺口。";
  } catch {
    return "无法记录知识缺口。";
  }
}

export function GapDialog({
  defaultTitle,
  onClose,
  onCreated,
  practiceItemId,
  sessionId
}: {
  defaultTitle: string;
  onClose: () => void;
  onCreated: (gap: GapRecord) => void;
  practiceItemId?: string;
  sessionId: string;
}) {
  const [title, setTitle] = useState(defaultTitle);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    setTitle(defaultTitle);
  }, [defaultTitle]);

  async function createGap(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!title.trim()) {
      return;
    }
    setSaving(true);
    setError(null);
    try {
      const response = await fetch(`/api/tutor/sessions/${sessionId}/gaps`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          practice_item_id: practiceItemId ?? null,
          title
        })
      });
      if (!response.ok) {
        throw new Error(await readError(response));
      }
      onCreated((await response.json()) as GapRecord);
    } catch (createError) {
      setError(
        createError instanceof Error
          ? createError.message
          : "无法记录知识缺口。"
      );
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="modal-backdrop">
      <div
        aria-labelledby="gap-dialog-title"
        aria-modal="true"
        className="dialog gap-dialog"
        role="dialog"
      >
        <div className="dialog-title-row">
          <div>
            <span className="field-label">复习记录</span>
            <h2 id="gap-dialog-title">记录知识缺口</h2>
          </div>
          <button
            aria-label="关闭知识缺口表单"
            className="icon-button"
            disabled={saving}
            type="button"
            onClick={onClose}
          >
            <X aria-hidden="true" size={16} />
          </button>
        </div>
        <p className="dialog-copy">
          这条记录会保存资料引用和关联会话，并加入今天的复习队列。
        </p>
        <form onSubmit={createGap}>
          <label htmlFor="gap-title">缺口标题</label>
          <input
            autoFocus
            id="gap-title"
            maxLength={300}
            value={title}
            onChange={(event) => setTitle(event.target.value)}
          />
          {error ? (
            <p className="error-message" role="alert">
              {error}
            </p>
          ) : null}
          <div className="dialog-actions">
            <button
              className="secondary-text-button"
              disabled={saving}
              type="button"
              onClick={onClose}
            >
              取消
            </button>
            <button
              className="primary-button gap-create-button"
              disabled={saving || !title.trim()}
              type="submit"
            >
              {saving ? (
                <LoaderCircle className="spin" aria-hidden="true" size={14} />
              ) : (
                <CalendarPlus aria-hidden="true" size={14} />
              )}
              {saving ? "正在加入…" : "加入复习"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
