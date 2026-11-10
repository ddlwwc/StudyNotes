"use client";

import {
  BookOpenCheck,
  Check,
  ChevronRight,
  LoaderCircle,
  RotateCcw
} from "lucide-react";
import { useEffect, useRef, useState } from "react";
import type { TutorCitation } from "./tutor-panel";

type PracticeItem = {
  id: string;
  ordinal: number;
  stem: string;
  options: string[];
  correctIndex: number;
  explanation: string;
  citation: TutorCitation;
};

type PracticeAttempt = {
  id: string;
  practiceItemId: string;
  selectedIndex: number;
  correct: boolean;
  answeredAt: string;
};

type Practice = {
  id: string;
  sessionId: string;
  questionCount: number;
  createdAt: string;
  questions: PracticeItem[];
};

type PracticeResponse = {
  attempts: PracticeAttempt[];
  practice: Practice | null;
};

async function readError(response: Response): Promise<string> {
  try {
    const payload = (await response.json()) as { detail?: string };
    return payload.detail ?? "练习题请求失败。";
  } catch {
    return "练习题请求失败。";
  }
}

function attemptMap(attempts: PracticeAttempt[]) {
  return Object.fromEntries(
    attempts.map((attempt) => [attempt.practiceItemId, attempt])
  );
}

export function PracticePanel({
  onCitationSelect,
  onEnsureSession,
  sessionId
}: {
  onCitationSelect: (citation: TutorCitation) => void;
  onEnsureSession: () => Promise<string>;
  sessionId: string | null;
}) {
  const [questionCount, setQuestionCount] = useState(3);
  const [activeSessionId, setActiveSessionId] = useState<string | null>(
    sessionId
  );
  const [practice, setPractice] = useState<Practice | null>(null);
  const [attempts, setAttempts] = useState<PracticeAttempt[]>([]);
  const [currentIndex, setCurrentIndex] = useState(0);
  const [selectedIndex, setSelectedIndex] = useState<number | null>(null);
  const [generating, setGenerating] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [loadingSaved, setLoadingSaved] = useState(false);
  const [finished, setFinished] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const ownsSessionRef = useRef(false);

  const byItem = attemptMap(attempts);
  const currentItem = practice?.questions[currentIndex] ?? null;
  const currentAttempt = currentItem ? byItem[currentItem.id] : undefined;

  function applyResponse(payload: PracticeResponse) {
    setAttempts(payload.attempts);
    setPractice(payload.practice);
    if (!payload.practice) {
      setCurrentIndex(0);
      setSelectedIndex(null);
      setFinished(false);
      return;
    }

    const answered = attemptMap(payload.attempts);
    const firstUnanswered = payload.practice.questions.findIndex(
      (question) => !answered[question.id]
    );
    if (firstUnanswered < 0) {
      setCurrentIndex(Math.max(0, payload.practice.questions.length - 1));
      setFinished(true);
    } else {
      setCurrentIndex(firstUnanswered);
      setFinished(false);
    }
    setSelectedIndex(null);
  }

  async function loadSavedPractice(activeId: string) {
    setLoadingSaved(true);
    setError(null);
    try {
      const response = await fetch(
        `/api/tutor/sessions/${activeId}/practice`,
        { cache: "no-store" }
      );
      if (!response.ok) {
        throw new Error(await readError(response));
      }
      applyResponse((await response.json()) as PracticeResponse);
    } catch (loadError) {
      setError(
        loadError instanceof Error ? loadError.message : "无法读取练习题。"
      );
    } finally {
      setLoadingSaved(false);
    }
  }

  useEffect(() => {
    if (!sessionId) {
      return;
    }
    setActiveSessionId(sessionId);
    if (!ownsSessionRef.current) {
      void loadSavedPractice(sessionId);
    }
  }, [sessionId]);

  async function createPractice() {
    setGenerating(true);
    setError(null);
    setFinished(false);
    try {
      ownsSessionRef.current = true;
      const activeId = activeSessionId ?? (await onEnsureSession());
      setActiveSessionId(activeId);
      const response = await fetch(
        `/api/tutor/sessions/${activeId}/practice`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ question_count: questionCount })
        }
      );
      if (!response.ok) {
        throw new Error(await readError(response));
      }
      const payload = (await response.json()) as PracticeResponse;
      if (!payload.practice) {
        throw new Error("模型没有生成练习题。");
      }
      applyResponse(payload);
      setCurrentIndex(0);
      setSelectedIndex(null);
    } catch (generateError) {
      setError(
        generateError instanceof Error
          ? generateError.message
          : "无法生成练习题。"
      );
    } finally {
      ownsSessionRef.current = false;
      setGenerating(false);
    }
  }

  async function submitAttempt() {
    if (!activeSessionId || !currentItem || selectedIndex === null) {
      return;
    }
    setSubmitting(true);
    setError(null);
    try {
      const response = await fetch(
        `/api/tutor/sessions/${activeSessionId}/practice/attempts`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            practice_item_id: currentItem.id,
            selected_index: selectedIndex
          })
        }
      );
      if (!response.ok) {
        throw new Error(await readError(response));
      }
      const attempt = (await response.json()) as PracticeAttempt;
      setAttempts((current) => [
        ...current.filter(
          (candidate) => candidate.practiceItemId !== attempt.practiceItemId
        ),
        attempt
      ]);
    } catch (submitError) {
      setError(
        submitError instanceof Error ? submitError.message : "无法保存答案。"
      );
    } finally {
      setSubmitting(false);
    }
  }

  function moveNext() {
    if (!practice) {
      return;
    }
    if (currentIndex >= practice.questions.length - 1) {
      setFinished(true);
      return;
    }
    setCurrentIndex((index) => index + 1);
    setSelectedIndex(null);
  }

  function resetPractice() {
    setPractice(null);
    setAttempts([]);
    setCurrentIndex(0);
    setSelectedIndex(null);
    setFinished(false);
    setError(null);
    setQuestionCount(3);
  }

  const optionLetter = (index: number) => String.fromCharCode(65 + index);
  const selectedOption = currentItem?.options[selectedIndex ?? -1];
  const correctOption = currentItem
    ? currentItem.options[currentItem.correctIndex]
    : null;

  return (
    <section
      aria-label="单选题练习"
      className="practice-panel"
      data-session-id={activeSessionId ?? undefined}
    >
      <header className="practice-heading">
        <div>
          <span className="field-label">练习题</span>
          <h3>单选题练习</h3>
        </div>
        <BookOpenCheck aria-hidden="true" size={17} />
      </header>

      <div className="practice-toolbar">
        <label htmlFor="practice-question-count">练习题数量</label>
        <select
          disabled={generating || Boolean(practice && !finished)}
          id="practice-question-count"
          value={questionCount}
          onChange={(event) => setQuestionCount(Number(event.target.value))}
        >
          {Array.from({ length: 10 }, (_, index) => index + 1).map((count) => (
            <option key={count} value={count}>
              {count} 题
            </option>
          ))}
        </select>
        {practice && !finished ? null : (
          <button
            className="practice-generate"
            disabled={generating || loadingSaved}
            type="button"
            onClick={() =>
              practice ? resetPractice() : void createPractice()
            }
          >
            {generating ? (
              <>
                <LoaderCircle className="spin" aria-hidden="true" size={13} />
                正在出题…
              </>
            ) : practice ? (
              "再练一组"
            ) : (
              "考考我"
            )}
          </button>
        )}
      </div>

      {loadingSaved ? (
        <p className="practice-loading" role="status">
          <LoaderCircle className="spin" aria-hidden="true" size={13} />
          正在读取练习记录…
        </p>
      ) : null}

      {error ? (
        <div className="practice-error" role="alert">
          <span>{error}</span>
          {!practice ? (
            <button type="button" onClick={() => void createPractice()}>
              <RotateCcw aria-hidden="true" size={12} />
              重试
            </button>
          ) : null}
        </div>
      ) : null}

      {finished && practice ? (
        <div className="practice-complete">
          <Check aria-hidden="true" size={18} />
          <strong>
            练习完成 ·{" "}
            {practice.questions.filter((question) => byItem[question.id]).length}{" "}
            / {practice.questionCount}
          </strong>
          <p>
            答对{" "}
            {
              practice.questions.filter(
                (question) => byItem[question.id]?.correct
              ).length
            }{" "}
            题。作答结果已保存到当前 Learning session。
          </p>
        </div>
      ) : currentItem ? (
        <div className="practice-question">
          <div className="practice-progress">
            <span>
              第 {currentIndex + 1} / {practice?.questionCount} 题
            </span>
            <span>单选题</span>
          </div>
          <h4>{currentItem.stem}</h4>

          <fieldset
            className="practice-options"
            disabled={Boolean(currentAttempt) || submitting}
          >
            <legend className="sr-only">选择答案</legend>
            {currentItem.options.map((option, index) => (
              <label className="practice-option" key={`${currentItem.id}:${index}`}>
                <input
                  checked={selectedIndex === index}
                  name={`practice-${currentItem.id}`}
                  type="radio"
                  value={index}
                  onChange={() => setSelectedIndex(index)}
                />
                <span aria-hidden="true">{optionLetter(index)}</span>
                <p>
                  {optionLetter(index)}. {option}
                </p>
              </label>
            ))}
          </fieldset>

          {currentAttempt ? (
            <div
              className={`practice-feedback ${
                currentAttempt.correct ? "is-correct" : "is-incorrect"
              }`}
              role="status"
            >
              <strong>
                {currentAttempt.correct ? "回答正确" : "回答错误"}
              </strong>
              <p>
                正确答案：{optionLetter(currentItem.correctIndex)}.{" "}
                {correctOption}
              </p>
              <p>{currentItem.explanation}</p>
              <button
                aria-label={`资料引用 ${currentItem.citation.path}: ${currentItem.citation.quote}`}
                className="practice-citation"
                type="button"
                onClick={() => onCitationSelect(currentItem.citation)}
              >
                <span>
                  资料引用 · {currentItem.citation.path}
                  {currentItem.citation.headingPath.length > 0
                    ? ` / ${currentItem.citation.headingPath.at(-1)}`
                    : ""}
                </span>
                <q>{currentItem.citation.quote}</q>
              </button>
            </div>
          ) : (
            <button
              className="practice-submit"
              disabled={selectedIndex === null || submitting}
              type="button"
              onClick={() => void submitAttempt()}
            >
              {submitting ? "正在保存…" : "提交答案"}
            </button>
          )}

          {currentAttempt ? (
            <button
              className="practice-next"
              type="button"
              onClick={moveNext}
            >
              {currentIndex >= (practice?.questionCount ?? 1) - 1
                ? "完成练习"
                : "下一题"}
              <ChevronRight aria-hidden="true" size={14} />
            </button>
          ) : null}
        </div>
      ) : null}

      {!practice && !loadingSaved ? (
        <p className="practice-empty">
          需要检验当前资料的掌握情况时，再按所选数量生成习题。
        </p>
      ) : null}
    </section>
  );
}
