"use client";

import {
  BookOpenCheck,
  CalendarClock,
  CalendarDays,
  Check,
  Clock3,
  LoaderCircle,
  RotateCcw,
  Trash2
} from "lucide-react";
import { useEffect, useState } from "react";
import type { TutorCitation } from "./tutor-panel";

type ReviewResult = {
  id: string;
  answer: string;
  feedback: string;
  result: "again" | "pass";
  reviewedAt: string | null;
  nextReviewAt: string | null;
};

type GapRecord = {
  id: string;
  title: string;
  sessionId: string;
  practiceItemId: string | null;
  citation: TutorCitation;
  scheduleStep: number;
  nextReviewAt: string | null;
  due: boolean;
  reviews: ReviewResult[];
};

type ReviewResponse = {
  queue: GapRecord[];
  records: GapRecord[];
};

function formatDate(value: string | null): string {
  if (!value) {
    return "未安排";
  }
  return new Intl.DateTimeFormat("zh-CN", {
    month: "long",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit"
  }).format(new Date(value));
}

function dateTimeInputValue(value: string | null): string {
  if (!value) {
    return "";
  }
  const date = new Date(value);
  const offset = date.getTimezoneOffset() * 60_000;
  return new Date(date.getTime() - offset).toISOString().slice(0, 16);
}

function mergeGap(records: GapRecord[], updated: GapRecord): GapRecord[] {
  return records.map((record) => (record.id === updated.id ? updated : record));
}

async function readError(response: Response): Promise<string> {
  try {
    const payload = (await response.json()) as { detail?: string };
    return payload.detail ?? "复习请求失败。";
  } catch {
    return "复习请求失败。";
  }
}

export function ReviewPage({
  onCitationSelect,
  workspacePath
}: {
  onCitationSelect: (citation: TutorCitation) => void;
  workspacePath: string;
}) {
  const [data, setData] = useState<ReviewResponse>({ queue: [], records: [] });
  const [view, setView] = useState<"queue" | "records">("queue");
  const [answers, setAnswers] = useState<Record<string, string>>({});
  const [feedback, setFeedback] = useState<Record<string, string>>({});
  const [dates, setDates] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(true);
  const [workingId, setWorkingId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  async function loadReview() {
    setLoading(true);
    setError(null);
    try {
      const response = await fetch("/api/review", { cache: "no-store" });
      if (!response.ok) {
        throw new Error(await readError(response));
      }
      const next = (await response.json()) as ReviewResponse;
      setData(next);
      setDates(
        Object.fromEntries(
          next.records.map((record) => [
            record.id,
            dateTimeInputValue(record.nextReviewAt)
          ])
        )
      );
    } catch (loadError) {
      setError(
        loadError instanceof Error ? loadError.message : "无法读取复习队列。"
      );
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    void loadReview();
  }, [workspacePath]);

  async function submitReview(
    gap: GapRecord,
    result: "again" | "pass"
  ) {
    const answer = answers[gap.id]?.trim() ?? "";
    if (!answer) {
      setError("请先填写复习答案。");
      return;
    }
    setWorkingId(gap.id);
    setError(null);
    setNotice(null);
    try {
      const response = await fetch(`/api/review/gaps/${gap.id}/results`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          answer,
          feedback: feedback[gap.id] ?? "",
          result
        })
      });
      if (!response.ok) {
        throw new Error(await readError(response));
      }
      const payload = (await response.json()) as {
        gap: GapRecord;
        review: ReviewResult;
      };
      setNotice(
        `${result === "pass" ? "已通过" : "已重来"} · 下次复习 ${formatDate(
          payload.review.nextReviewAt
        )}`
      );
      setAnswers((current) => ({ ...current, [gap.id]: "" }));
      setFeedback((current) => ({ ...current, [gap.id]: "" }));
      await loadReview();
    } catch (reviewError) {
      setError(
        reviewError instanceof Error ? reviewError.message : "无法保存复习结果。"
      );
    } finally {
      setWorkingId(null);
    }
  }

  async function saveDate(gap: GapRecord) {
    const value = dates[gap.id];
    setWorkingId(gap.id);
    setError(null);
    try {
      const response = await fetch(`/api/review/gaps/${gap.id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          next_review_at: value ? new Date(value).toISOString() : null
        })
      });
      if (!response.ok) {
        throw new Error(await readError(response));
      }
      const updated = (await response.json()) as GapRecord;
      setData((current) => ({
        queue: updated.due
          ? [
              ...current.queue.filter((record) => record.id !== gap.id),
              updated
            ]
              .sort((left, right) =>
                (left.nextReviewAt ?? "").localeCompare(
                  right.nextReviewAt ?? ""
                )
              )
              .slice(0, 20)
          : current.queue.filter((record) => record.id !== gap.id),
        records: mergeGap(current.records, updated)
      }));
    } catch (dateError) {
      setError(
        dateError instanceof Error ? dateError.message : "无法修改复习日期。"
      );
    } finally {
      setWorkingId(null);
    }
  }

  async function clearDate(gap: GapRecord) {
    setDates((current) => ({ ...current, [gap.id]: "" }));
    setWorkingId(gap.id);
    setError(null);
    try {
      const response = await fetch(`/api/review/gaps/${gap.id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ next_review_at: null })
      });
      if (!response.ok) {
        throw new Error(await readError(response));
      }
      const updated = (await response.json()) as GapRecord;
      setData((current) => ({
        queue: current.queue.filter((record) => record.id !== gap.id),
        records: mergeGap(current.records, updated)
      }));
    } catch (dateError) {
      setError(
        dateError instanceof Error ? dateError.message : "无法清除复习日期。"
      );
    } finally {
      setWorkingId(null);
    }
  }

  async function deleteGap(gap: GapRecord) {
    setWorkingId(gap.id);
    setError(null);
    try {
      const response = await fetch(`/api/review/gaps/${gap.id}`, {
        method: "DELETE"
      });
      if (!response.ok) {
        throw new Error(await readError(response));
      }
      setData((current) => ({
        queue: current.queue.filter((record) => record.id !== gap.id),
        records: current.records.filter((record) => record.id !== gap.id)
      }));
    } catch (deleteError) {
      setError(
        deleteError instanceof Error
          ? deleteError.message
          : "无法删除知识缺口。"
      );
    } finally {
      setWorkingId(null);
    }
  }

  return (
    <section aria-label="复习" className="review-page" role="region">
      <header className="review-header">
        <div>
          <span className="field-label">复习计划</span>
          <h1>复习</h1>
          <p>把未掌握的练习转化为可追踪的知识缺口，按到期时间逐步巩固。</p>
        </div>
        <div className="review-summary">
          <CalendarClock aria-hidden="true" size={20} />
          <strong>{data.queue.length}</strong>
          <span>项待复习</span>
        </div>
      </header>

      <div className="review-tabs" role="tablist" aria-label="复习视图">
        <button
          aria-selected={view === "queue"}
          className={view === "queue" ? "is-active" : ""}
          role="tab"
          type="button"
          onClick={() => setView("queue")}
        >
          <Clock3 aria-hidden="true" size={14} />
          到期队列
        </button>
        <button
          aria-selected={view === "records"}
          className={view === "records" ? "is-active" : ""}
          role="tab"
          type="button"
          onClick={() => setView("records")}
        >
          <CalendarDays aria-hidden="true" size={14} />
          全部记录
        </button>
      </div>

      {notice ? (
        <p className="review-notice" role="status">
          <Check aria-hidden="true" size={15} />
          {notice}
        </p>
      ) : null}
      {error ? (
        <p className="review-error" role="alert">
          {error}
        </p>
      ) : null}

      {loading ? (
        <div className="review-empty" role="status">
          <LoaderCircle className="spin" aria-hidden="true" size={18} />
          正在读取复习队列…
        </div>
      ) : view === "queue" ? (
        data.queue.length > 0 ? (
          <div className="review-list">
            {data.queue.map((gap, index) => (
              <article className="review-item" key={gap.id}>
                <div className="review-item-heading">
                  <span>{String(index + 1).padStart(2, "0")}</span>
                  <div>
                    <h2>{gap.title}</h2>
                    <p>到期：{formatDate(gap.nextReviewAt)}</p>
                  </div>
                </div>
                <button
                  aria-label={`资料引用 ${gap.citation.path}: ${gap.citation.quote}`}
                  className="review-citation"
                  type="button"
                  onClick={() => onCitationSelect(gap.citation)}
                >
                  <span>
                    {gap.citation.path}
                    {gap.citation.headingPath.length > 0
                      ? ` / ${gap.citation.headingPath.at(-1)}`
                      : ""}
                  </span>
                  <q>{gap.citation.quote}</q>
                </button>
                <div className="review-form">
                  <label htmlFor={`review-answer-${gap.id}`}>复习答案</label>
                  <textarea
                    id={`review-answer-${gap.id}`}
                    placeholder="不看答案，用自己的话重述关键内容。"
                    rows={3}
                    value={answers[gap.id] ?? ""}
                    onChange={(event) =>
                      setAnswers((current) => ({
                        ...current,
                        [gap.id]: event.target.value
                      }))
                    }
                  />
                  <label htmlFor={`review-feedback-${gap.id}`}>复习反馈</label>
                  <textarea
                    id={`review-feedback-${gap.id}`}
                    placeholder="可选：记录遗漏、混淆点或下一步线索。"
                    rows={2}
                    value={feedback[gap.id] ?? ""}
                    onChange={(event) =>
                      setFeedback((current) => ({
                        ...current,
                        [gap.id]: event.target.value
                      }))
                    }
                  />
                </div>
                <div className="review-actions">
                  <button
                    className="review-again"
                    disabled={workingId === gap.id}
                    type="button"
                    onClick={() => void submitReview(gap, "again")}
                  >
                    <RotateCcw aria-hidden="true" size={14} />
                    重来
                  </button>
                  <button
                    className="review-pass"
                    disabled={workingId === gap.id}
                    type="button"
                    onClick={() => void submitReview(gap, "pass")}
                  >
                    <Check aria-hidden="true" size={14} />
                    通过
                  </button>
                </div>
              </article>
            ))}
          </div>
        ) : (
          <div className="review-empty">
            <BookOpenCheck aria-hidden="true" size={22} />
            <strong>今天的复习已经完成</strong>
            <p>新的知识缺口会按到期时间出现在这里，单批最多显示 20 项。</p>
          </div>
        )
      ) : data.records.length > 0 ? (
        <div className="review-records">
          {data.records.map((gap) => (
            <article className="review-record" key={gap.id}>
              <div>
                <span className={gap.due ? "is-due" : ""}>
                  {gap.due ? "待复习" : gap.nextReviewAt ? "已安排" : "未安排"}
                </span>
                <h2>{gap.title}</h2>
                <p>
                  下次复习：{formatDate(gap.nextReviewAt)} · 已完成{" "}
                  {gap.reviews.length} 次
                </p>
              </div>
              <div className="review-date-controls">
                <label htmlFor={`review-date-${gap.id}`}>
                  下次复习时间 · {gap.title}
                </label>
                <input
                  id={`review-date-${gap.id}`}
                  type="datetime-local"
                  value={dates[gap.id] ?? ""}
                  onChange={(event) =>
                    setDates((current) => ({
                      ...current,
                      [gap.id]: event.target.value
                    }))
                  }
                />
                <button
                  disabled={workingId === gap.id || !dates[gap.id]}
                  type="button"
                  onClick={() => void saveDate(gap)}
                >
                  保存日期
                </button>
                <button
                  disabled={workingId === gap.id || !gap.nextReviewAt}
                  type="button"
                  onClick={() => void clearDate(gap)}
                >
                  清除日期
                </button>
                <button
                  aria-label={`删除知识缺口 ${gap.title}`}
                  className="review-delete"
                  disabled={workingId === gap.id}
                  type="button"
                  onClick={() => void deleteGap(gap)}
                >
                  <Trash2 aria-hidden="true" size={14} />
                </button>
              </div>
            </article>
          ))}
        </div>
      ) : (
        <div className="review-empty">
          <BookOpenCheck aria-hidden="true" size={22} />
          <strong>还没有知识缺口</strong>
          <p>在练习反馈或 Learning session 中明确记录后，会出现在这里。</p>
        </div>
      )}
    </section>
  );
}
