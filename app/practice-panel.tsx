"use client";

import {
  BookOpenCheck,
  BookmarkPlus,
  Check,
  ChevronRight,
  LoaderCircle,
  RotateCcw,
  Save,
  Trash2
} from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { GapDialog } from "./gap-dialog";
import type { TutorCitation } from "./tutor-panel";

type PracticeItem = {
  id: string;
  ordinal: number;
  itemType: "single_choice" | "short_answer";
  stem: string;
  options: string[];
  correctIndex: number | null;
  explanation: string;
  referenceAnswer: string | null;
  citation: TutorCitation;
};

type ShortAnswerFeedback = {
  score: number;
  referencePoints: string[];
  scoringBasis: string;
  matchedPoints: string[];
  missingPoints: string[];
  citations: TutorCitation[];
};

type PracticeAttempt = {
  id: string;
  practiceItemId: string;
  selectedIndex: number | null;
  answerText: string | null;
  correct: boolean;
  feedback: ShortAnswerFeedback | null;
  aiScore: number | null;
  finalScore: number | null;
  feedbackStatus: "pending" | "graded" | "failed";
  feedbackError: string | null;
  answeredAt: string;
  feedbackUpdatedAt: string | null;
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
  const [shortAnswer, setShortAnswer] = useState("");
  const [selfAssessmentScore, setSelfAssessmentScore] = useState(0);
  const [generating, setGenerating] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [savingAssessment, setSavingAssessment] = useState(false);
  const [retryingFeedback, setRetryingFeedback] = useState(false);
  const [loadingSaved, setLoadingSaved] = useState(false);
  const [finished, setFinished] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [gapDialogOpen, setGapDialogOpen] = useState(false);
  const [gapCreatedItems, setGapCreatedItems] = useState<Record<string, true>>(
    {}
  );
  const [deleteConfirmItemId, setDeleteConfirmItemId] = useState<string | null>(
    null
  );
  const ownsSessionRef = useRef(false);

  const byItem = attemptMap(attempts);
  const currentItem = practice?.questions[currentIndex] ?? null;
  const currentAttempt = currentItem ? byItem[currentItem.id] : undefined;
  const currentItemHasGap = currentItem
    ? Boolean(gapCreatedItems[currentItem.id])
    : false;

  function replaceAttempt(attempt: PracticeAttempt) {
    setAttempts((current) => [
      ...current.filter(
        (candidate) => candidate.practiceItemId !== attempt.practiceItemId
      ),
      attempt
    ]);
  }

  useEffect(() => {
    setSelfAssessmentScore(
      currentAttempt?.finalScore ?? currentAttempt?.aiScore ?? 0
    );
  }, [
    currentItem?.id,
    currentAttempt?.aiScore,
    currentAttempt?.finalScore
  ]);

  function applyResponse(payload: PracticeResponse) {
    setAttempts(payload.attempts);
    setPractice(payload.practice);
    if (!payload.practice) {
      setCurrentIndex(0);
      setSelectedIndex(null);
      setShortAnswer("");
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
    setShortAnswer("");
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
      setShortAnswer("");
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
      replaceAttempt(attempt);
    } catch (submitError) {
      setError(
        submitError instanceof Error ? submitError.message : "无法保存答案。"
      );
    } finally {
      setSubmitting(false);
    }
  }

  async function submitShortAnswer() {
    if (!activeSessionId || !currentItem || !shortAnswer.trim()) {
      return;
    }
    setSubmitting(true);
    setError(null);
    try {
      const response = await fetch(
        `/api/tutor/sessions/${activeSessionId}/practice/short-answer-attempts`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            practice_item_id: currentItem.id,
            answer_text: shortAnswer
          })
        }
      );
      if (!response.ok) {
        throw new Error(await readError(response));
      }
      replaceAttempt((await response.json()) as PracticeAttempt);
    } catch (submitError) {
      setError(
        submitError instanceof Error
          ? submitError.message
          : "无法评分短答题。"
      );
    } finally {
      setSubmitting(false);
    }
  }

  async function retryShortAnswerFeedback() {
    if (!activeSessionId || !currentItem) {
      return;
    }
    setRetryingFeedback(true);
    setError(null);
    try {
      const response = await fetch(
        `/api/tutor/sessions/${activeSessionId}/practice/items/${currentItem.id}/retry-feedback`,
        { method: "POST" }
      );
      if (!response.ok) {
        throw new Error(await readError(response));
      }
      replaceAttempt((await response.json()) as PracticeAttempt);
    } catch (retryError) {
      setError(
        retryError instanceof Error ? retryError.message : "无法重试评分。"
      );
    } finally {
      setRetryingFeedback(false);
    }
  }

  async function saveSelfAssessment() {
    if (!activeSessionId || !currentItem || !currentAttempt) {
      return;
    }
    setSavingAssessment(true);
    setError(null);
    try {
      const response = await fetch(
        `/api/tutor/sessions/${activeSessionId}/practice/items/${currentItem.id}/self-assessment`,
        {
          method: "PATCH",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ final_score: selfAssessmentScore })
        }
      );
      if (!response.ok) {
        throw new Error(await readError(response));
      }
      replaceAttempt((await response.json()) as PracticeAttempt);
    } catch (assessmentError) {
      setError(
        assessmentError instanceof Error
          ? assessmentError.message
          : "无法保存自评。"
      );
    } finally {
      setSavingAssessment(false);
    }
  }

  async function deleteCurrentItem() {
    if (!activeSessionId || !currentItem) {
      return;
    }
    setSubmitting(true);
    setError(null);
    try {
      const response = await fetch(
        `/api/tutor/sessions/${activeSessionId}/practice/items/${currentItem.id}`,
        { method: "DELETE" }
      );
      if (!response.ok) {
        throw new Error(await readError(response));
      }
      applyResponse((await response.json()) as PracticeResponse);
      setDeleteConfirmItemId(null);
    } catch (deleteError) {
      setError(
        deleteError instanceof Error
          ? deleteError.message
          : "无法删除练习项。"
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
    setShortAnswer("");
  }

  function resetPractice() {
    setPractice(null);
    setAttempts([]);
    setCurrentIndex(0);
    setSelectedIndex(null);
    setShortAnswer("");
    setSelfAssessmentScore(0);
    setFinished(false);
    setError(null);
    setQuestionCount(3);
  }

  const optionLetter = (index: number) => String.fromCharCode(65 + index);
  const correctOption = currentItem
    ? currentItem.correctIndex === null
      ? null
      : currentItem.options[currentItem.correctIndex]
    : null;
  const isShortAnswer = currentItem?.itemType === "short_answer";

  return (
    <section
      aria-label="练习题"
      className="practice-panel"
      data-session-id={activeSessionId ?? undefined}
    >
      <header className="practice-heading">
        <div>
          <span className="field-label">练习题</span>
          <h3>练习题</h3>
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
            题。作答结果已保存到当前学习会话。
          </p>
        </div>
      ) : currentItem ? (
        <div className="practice-question">
          <div className="practice-progress">
            <span>
              第 {currentIndex + 1} / {practice?.questionCount} 题
            </span>
            <span>
              {isShortAnswer ? "短答题" : "单选题"}
              <button
                aria-label="删除当前练习项"
                className="practice-delete-item"
                type="button"
                onClick={() => setDeleteConfirmItemId(currentItem.id)}
              >
                <Trash2 aria-hidden="true" size={12} />
              </button>
            </span>
          </div>
          {deleteConfirmItemId === currentItem.id ? (
            <div className="practice-delete-confirm" role="alert">
              <span>删除后作答记录也会移除，但知识缺口仍会保留。</span>
              <button
                type="button"
                onClick={() => setDeleteConfirmItemId(null)}
              >
                取消
              </button>
              <button
                className="danger-text-button"
                disabled={submitting}
                type="button"
                onClick={() => void deleteCurrentItem()}
              >
                {submitting ? "正在删除…" : "确认删除"}
              </button>
            </div>
          ) : null}
          <h4>{currentItem.stem}</h4>

          {isShortAnswer ? (
            <div className="practice-short-answer">
              <label htmlFor={`short-answer-${currentItem.id}`}>
                短答题答案
              </label>
              <textarea
                aria-label="短答题答案"
                disabled={Boolean(currentAttempt) || submitting}
                id={`short-answer-${currentItem.id}`}
                rows={4}
                value={currentAttempt?.answerText ?? shortAnswer}
                onChange={(event) => setShortAnswer(event.target.value)}
              />
            </div>
          ) : (
            <fieldset
              className="practice-options"
              disabled={Boolean(currentAttempt) || submitting}
            >
              <legend className="sr-only">选择答案</legend>
              {currentItem.options.map((option, index) => (
                <label
                  className="practice-option"
                  key={`${currentItem.id}:${index}`}
                >
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
          )}

          {currentAttempt && !isShortAnswer ? (
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
                正确答案：
                {optionLetter(currentItem.correctIndex ?? 0)}.{" "}
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
              <div className="practice-gap-capture">
                {currentItemHasGap ? (
                  <span role="status">已加入复习队列</span>
                ) : (
                  <button
                    type="button"
                    onClick={() => setGapDialogOpen(true)}
                  >
                    <BookmarkPlus aria-hidden="true" size={13} />
                    记为知识缺口
                  </button>
                )}
              </div>
            </div>
          ) : null}

          {isShortAnswer && currentAttempt?.feedback ? (
            <div
              className={`practice-feedback practice-feedback-detail ${
                currentAttempt.finalScore !== null &&
                currentAttempt.finalScore >= 60
                  ? "is-correct"
                  : "is-incorrect"
              }`}
              role="status"
            >
              <p className="practice-score-summary">
                AI 初评 · <strong>{currentAttempt.aiScore} 分</strong>
                <span aria-hidden="true"> · </span>
                最终自评 ·{" "}
                <strong>
                  {currentAttempt.finalScore === null
                    ? "未保存"
                    : `${currentAttempt.finalScore} 分`}
                </strong>
              </p>
              <section className="practice-feedback-section">
                <h5>参考要点</h5>
                <ul>
                  {currentAttempt.feedback.referencePoints.map((point) => (
                    <li key={point}>{point}</li>
                  ))}
                </ul>
              </section>
              <section className="practice-feedback-section">
                <h5>评分依据</h5>
                <p>{currentAttempt.feedback.scoringBasis}</p>
              </section>
              <section className="practice-feedback-section">
                <h5>已命中</h5>
                {currentAttempt.feedback.matchedPoints.length ? (
                  <ul>
                    {currentAttempt.feedback.matchedPoints.map((point) => (
                      <li key={point}>{point}</li>
                    ))}
                  </ul>
                ) : (
                  <p>暂未命中明确要点。</p>
                )}
              </section>
              <section className="practice-feedback-section">
                <h5>遗漏项</h5>
                {currentAttempt.feedback.missingPoints.length ? (
                  <ul>
                    {currentAttempt.feedback.missingPoints.map((point) => (
                      <li key={point}>{point}</li>
                    ))}
                  </ul>
                ) : (
                  <p>没有明显遗漏。</p>
                )}
              </section>
              {currentAttempt.feedback.citations.map((citation) => (
                <button
                  aria-label={`资料引用 ${citation.path}: ${citation.quote}`}
                  className="practice-citation"
                  key={`${citation.sourceId}:${citation.blockId}:${citation.quote}`}
                  type="button"
                  onClick={() => onCitationSelect(citation)}
                >
                  <span>
                    资料引用 · {citation.path}
                    {citation.headingPath.length > 0
                      ? ` / ${citation.headingPath.at(-1)}`
                      : ""}
                  </span>
                  <q>{citation.quote}</q>
                </button>
              ))}
              {currentAttempt.finalScore !== null &&
              currentAttempt.finalScore < 60 ? (
                <div className="practice-gap-capture">
                  {currentItemHasGap ? (
                    <span role="status">已加入复习队列</span>
                  ) : (
                    <button
                      type="button"
                      onClick={() => setGapDialogOpen(true)}
                    >
                      <BookmarkPlus aria-hidden="true" size={13} />
                      记为知识缺口
                    </button>
                  )}
                </div>
              ) : null}
            </div>
          ) : null}

          {isShortAnswer && currentAttempt?.feedbackStatus === "failed" ? (
            <div className="practice-feedback is-incorrect" role="status">
              <strong>AI 评分暂不可用，答案已保存</strong>
              <p>{currentAttempt.feedbackError}</p>
              <p className="practice-score-summary">
                AI 初评 · 未完成 · 最终自评 ·{" "}
                {currentAttempt.finalScore === null
                  ? "未保存"
                  : `${currentAttempt.finalScore} 分`}
              </p>
              <button
                className="practice-retry-feedback"
                disabled={retryingFeedback}
                type="button"
                onClick={() => void retryShortAnswerFeedback()}
              >
                <RotateCcw aria-hidden="true" size={12} />
                {retryingFeedback ? "正在重试…" : "重试评分"}
              </button>
            </div>
          ) : null}

          {isShortAnswer && currentAttempt ? (
            <div className="practice-self-assessment">
              <label htmlFor={`self-assessment-${currentItem.id}`}>
                最终自评
              </label>
              <div>
                <input
                  aria-label="最终自评"
                  id={`self-assessment-${currentItem.id}`}
                  max="100"
                  min="0"
                  step="10"
                  type="range"
                  value={selfAssessmentScore}
                  onChange={(event) =>
                    setSelfAssessmentScore(Number(event.target.value))
                  }
                />
                <output>{selfAssessmentScore} 分</output>
                <button
                  disabled={savingAssessment}
                  type="button"
                  onClick={() => void saveSelfAssessment()}
                >
                  <Save aria-hidden="true" size={12} />
                  {savingAssessment ? "正在保存…" : "保存自评"}
                </button>
              </div>
            </div>
          ) : null}

          {!currentAttempt && !isShortAnswer ? (
            <button
              className="practice-submit"
              disabled={selectedIndex === null || submitting}
              type="button"
              onClick={() => void submitAttempt()}
            >
              {submitting ? "正在保存…" : "提交答案"}
            </button>
          ) : null}

          {!currentAttempt && isShortAnswer ? (
            <button
              className="practice-submit"
              disabled={!shortAnswer.trim() || submitting}
              type="button"
              onClick={() => void submitShortAnswer()}
            >
              {submitting ? "正在评分…" : "提交回答"}
            </button>
          ) : null}

          {currentAttempt &&
          (isShortAnswer ? currentAttempt.finalScore !== null : true) ? (
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

      {gapDialogOpen && activeSessionId && currentItem ? (
        <GapDialog
          defaultTitle={currentItem.stem}
          onClose={() => setGapDialogOpen(false)}
          onCreated={() => {
            setGapCreatedItems((current) => ({
              ...current,
              [currentItem.id]: true
            }));
            setGapDialogOpen(false);
          }}
          practiceItemId={currentItem.id}
          sessionId={activeSessionId}
        />
      ) : null}
    </section>
  );
}
