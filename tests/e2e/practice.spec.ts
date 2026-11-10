import { expect, test } from "@playwright/test";
import type { Page } from "@playwright/test";
import { spawn, type ChildProcess } from "node:child_process";
import { createServer } from "node:http";
import type { IncomingMessage, ServerResponse } from "node:http";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { createServer as createNetServer } from "node:net";
import { tmpdir } from "node:os";
import path from "node:path";

type RunningApp = {
  stop: () => Promise<void>;
  webUrl: string;
};

type ModelRequest = {
  body: Record<string, unknown>;
};

type MockModel = {
  baseUrl: string;
  close: () => Promise<void>;
  requests: ModelRequest[];
};

type ModelResponder = (
  body: Record<string, unknown>,
  requestIndex: number,
  response: ServerResponse
) => Promise<void> | void;

type PracticeQuestion = {
  itemType?: "single_choice" | "short_answer";
  stem: string;
  options: string[];
  correctIndex: number;
  explanation: string;
  referenceAnswer?: string | null;
  citation: {
    sourceId: string;
    path: string;
    blockId: string;
    blockIndex: number;
    headingPath: string[];
    quote: string;
  };
};

type PracticeFeedback = {
  score: number;
  referencePoints: string[];
  scoringBasis: string;
  matchedPoints: string[];
  missingPoints: string[];
  citations: PracticeQuestion["citation"][];
};

function reservePort(): Promise<number> {
  return new Promise((resolve, reject) => {
    const server = createNetServer();
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      if (address === null || typeof address === "string") {
        server.close();
        reject(new Error("Failed to reserve a test port."));
        return;
      }
      server.close((error) => (error ? reject(error) : resolve(address.port)));
    });
  });
}

async function readRequestBody(request: IncomingMessage): Promise<string> {
  const chunks: Buffer[] = [];
  for await (const chunk of request) {
    chunks.push(Buffer.from(chunk));
  }
  return Buffer.concat(chunks).toString("utf8");
}

function sendChatCompletion(response: ServerResponse, content: string) {
  response.writeHead(200, { "Content-Type": "application/json" });
  response.end(
    JSON.stringify({
      id: "chatcmpl-test",
      object: "chat.completion",
      choices: [
        {
          index: 0,
          message: { role: "assistant", content },
          finish_reason: "stop"
        }
      ]
    })
  );
}

async function sendStreamingCompletion(
  response: ServerResponse,
  content: string
) {
  response.writeHead(200, {
    "Cache-Control": "no-store",
    "Content-Type": "text/event-stream"
  });
  for (let index = 0; index < content.length; index += 18) {
    response.write(
      `data: ${JSON.stringify({
        choices: [{ delta: { content: content.slice(index, index + 18) } }]
      })}\n\n`
    );
  }
  response.write("data: [DONE]\n\n");
  response.end();
}

function practicePayload(questionCount: number) {
  const stems = [
    "注意力对学习的主要作用是什么？",
    "为什么注意力控制会影响理解？",
    "资料把注意力和什么联系起来？"
  ];
  const options = [
    ["筛选任务相关信息", "永久存储所有信息", "替代工作记忆", "消除理解差异"],
    ["工作记忆容量有限", "资料数量无限", "注意力不需要资源", "理解与注意力无关"],
    ["当前任务相关信息", "睡眠时长", "文件格式", "设备性能"]
  ];
  return {
    questions: Array.from({ length: questionCount }, (_, index) => ({
      stem: stems[index % stems.length] + (index >= stems.length ? `（${index + 1}）` : ""),
      options: options[index % options.length],
      correct_index: 0,
      explanation:
        "资料指出注意力会筛选任务相关信息，而工作记忆容量有限，所以注意力控制会影响理解。",
      citation: {
        source_id: "S1",
        quote: "注意力帮助学习者筛选当前任务相关的信息。"
      }
    }))
  };
}

function shortAnswerPracticePayload() {
  return {
    questions: [
      {
        type: "short_answer",
        stem: "用自己的话解释注意力如何影响学习。",
        reference_answer:
          "注意力帮助学习者筛选当前任务相关的信息，并因为工作记忆容量有限而影响理解。",
        citation: {
          source_id: "S1",
          quote: "注意力帮助学习者筛选当前任务相关的信息。"
        }
      }
    ]
  };
}

function shortAnswerFeedbackPayload() {
  return {
    score: 80,
    reference_points: [
      "注意力帮助筛选当前任务相关的信息。",
      "工作记忆容量有限，因此注意力控制会影响理解。"
    ],
    scoring_basis:
      "回答解释了注意力对相关信息筛选的作用；没有说明工作记忆容量限制。",
    matched_points: ["注意力帮助筛选当前任务相关的信息。"],
    missing_points: ["工作记忆容量有限，因此注意力控制会影响理解。"],
    citations: [
      {
        source_id: "S1",
        quote: "注意力帮助学习者筛选当前任务相关的信息。"
      }
    ]
  };
}

async function startMockModel(responder?: ModelResponder): Promise<MockModel> {
  const requests: ModelRequest[] = [];
  const server = createServer(async (request, response) => {
    if (request.method !== "POST" || request.url !== "/v1/chat/completions") {
      response.writeHead(404);
      response.end();
      return;
    }

    const raw = await readRequestBody(request);
    const body = JSON.parse(raw) as Record<string, unknown>;
    requests.push({ body });
    if (responder) {
      await responder(body, requests.length - 1, response);
      return;
    }

    const metadata = (body.metadata ?? {}) as Record<string, unknown>;
    if (metadata.study_notes_mode === "practice") {
      sendChatCompletion(
        response,
        JSON.stringify(
          practicePayload(Number(metadata.practice_count ?? 3))
        )
      );
      return;
    }
    if (body.stream === true) {
      await sendStreamingCompletion(
        response,
        JSON.stringify({
          type: "grounded",
          answer:
            "注意力会帮助学习者筛选当前任务相关信息。[S1]",
          citations: [
            {
              source_id: "S1",
              quote: "注意力帮助学习者筛选当前任务相关的信息。"
            }
          ],
          missing: []
        })
      );
      return;
    }
    sendChatCompletion(response, "OK");
  });

  await new Promise<void>((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => resolve());
  });
  const address = server.address();
  if (address === null || typeof address === "string") {
    throw new Error("Mock model failed to bind a TCP port.");
  }

  return {
    baseUrl: `http://127.0.0.1:${address.port}/v1`,
    close: () =>
      new Promise<void>((resolve, reject) => {
        server.close((error) => (error ? reject(error) : resolve()));
      }),
    requests
  };
}

async function waitForHttp(
  url: string,
  child: ChildProcess,
  output: () => string
) {
  const deadline = Date.now() + 90_000;

  while (Date.now() < deadline) {
    if (child.exitCode !== null) {
      throw new Error(`StudyNotes development services exited early.\n${output()}`);
    }
    try {
      const response = await fetch(url);
      if (response.ok) {
        return;
      }
    } catch {
      // Services are still starting.
    }
    await new Promise((resolve) => setTimeout(resolve, 200));
  }

  throw new Error(`Timed out waiting for ${url}.\n${output()}`);
}

async function startApp(): Promise<RunningApp> {
  const dataDir = await mkdtemp(path.join(tmpdir(), "studynotes-data-"));
  const backendPort = await reservePort();
  const webPort = await reservePort();
  const webUrl = `http://127.0.0.1:${webPort}`;
  let logs = "";
  const child = spawn("npm", ["run", "dev"], {
    cwd: path.resolve(import.meta.dirname, "../.."),
    detached: true,
    env: {
      ...process.env,
      STUDY_NOTES_BACKEND_PORT: String(backendPort),
      STUDY_NOTES_DATA_DIR: dataDir,
      STUDY_NOTES_SECRET_BACKEND: "memory",
      STUDY_NOTES_WEB_PORT: String(webPort)
    },
    stdio: ["ignore", "pipe", "pipe"]
  });
  child.stdout?.on("data", (chunk) => {
    logs += chunk.toString();
  });
  child.stderr?.on("data", (chunk) => {
    logs += chunk.toString();
  });

  try {
    await waitForHttp(
      `http://127.0.0.1:${backendPort}/api/health`,
      child,
      () => logs
    );
    await waitForHttp(webUrl, child, () => logs);
  } catch (error) {
    if (child.exitCode === null && child.pid) {
      try {
        process.kill(-child.pid, "SIGTERM");
      } catch {
        child.kill("SIGTERM");
      }
    }
    await rm(dataDir, { recursive: true, force: true });
    throw error;
  }

  return {
    webUrl,
    stop: async () => {
      if (child.exitCode === null && child.pid) {
        try {
          process.kill(-child.pid, "SIGTERM");
        } catch {
          child.kill("SIGTERM");
        }
      }
      await Promise.race([
        new Promise<void>((resolve) => child.once("exit", () => resolve())),
        new Promise<void>((resolve) => setTimeout(resolve, 5_000))
      ]);
      await rm(dataDir, { recursive: true, force: true });
    }
  };
}

async function openStudyPage(page: Page): Promise<string> {
  const workspaceDir = await mkdtemp(
    path.join(tmpdir(), "studynotes-workspace-")
  );
  await mkdir(path.join(workspaceDir, "课程"), { recursive: true });
  await writeFile(
    path.join(workspaceDir, "课程", "注意力机制.md"),
    [
      "# 注意力机制",
      "",
      "注意力帮助学习者筛选当前任务相关的信息。",
      "",
      "工作记忆容量有限，因此注意力控制会影响理解。"
    ].join("\n"),
    "utf8"
  );
  return workspaceDir;
}

async function configureModel(page: Page, baseUrl: string) {
  await page.getByRole("button", { name: "设置" }).click();
  await page.getByLabel("Base URL").fill(baseUrl);
  await page.getByLabel("API Key").fill("test-key");
  await page.getByLabel("聊天模型").fill("mock-model");
  await page.getByRole("button", { name: "保存设置" }).click();
  await expect(page.getByRole("dialog", { name: "模型设置" })).toBeHidden();
}

async function prepareTutor(
  page: Page,
  webUrl: string,
  workspaceDir: string,
  baseUrl: string
) {
  await page.goto(webUrl);
  await page.getByLabel("Notebook workspace 路径").fill(workspaceDir);
  await page.getByRole("button", { name: "打开工作区" }).click();
  await configureModel(page, baseUrl);
  await page
    .getByRole("button", { name: "注意力机制.md", exact: true })
    .click();
  await page
    .getByText("注意力帮助学习者筛选当前任务相关的信息。", { exact: true })
    .click();
  return page.getByRole("complementary", { name: "Grounded tutor" });
}

test("a Learning session generates, answers, cites, and persists single-choice Practice items", async ({
  page
}) => {
  const app = await startApp();
  const model = await startMockModel();
  const workspaceDir = await openStudyPage(page);

  try {
    const tutor = await prepareTutor(
      page,
      app.webUrl,
      workspaceDir,
      model.baseUrl
    );
    await tutor.getByRole("button", { name: "记为知识缺口" }).click();
    const sessionGapDialog = page.getByRole("dialog", { name: "记录知识缺口" });
    await expect(sessionGapDialog.getByLabel("缺口标题")).toHaveValue(
      "注意力帮助学习者筛选当前任务相关的信息。"
    );
    await sessionGapDialog.getByLabel("缺口标题").fill("注意力筛选机制");
    await sessionGapDialog.getByRole("button", { name: "加入复习" }).click();
    await expect(tutor.getByText("已记录为知识缺口")).toBeVisible();

    await page.getByLabel("向当前资料提问").fill("注意力为什么重要？");
    await tutor.getByRole("button", { name: "发送" }).click();
    await expect(tutor.getByText("已完成")).toBeVisible();

    const requestCountBeforePractice = model.requests.length;
    const practice = page.getByRole("region", { name: "练习题" });
    const questionCount = practice.getByLabel("练习题数量");
    await expect(questionCount).toHaveValue("3");
    await expect(questionCount.locator("option")).toHaveCount(10);
    expect(
      model.requests.filter(
        (request) =>
          (request.body.metadata as Record<string, unknown> | undefined)
            ?.study_notes_mode === "practice"
      )
    ).toHaveLength(0);
    expect(model.requests).toHaveLength(requestCountBeforePractice);

    await practice.getByRole("button", { name: "考考我" }).click();
    await expect(practice.getByText("第 1 / 3 题")).toBeVisible();
    await expect(
      practice.getByText("注意力对学习的主要作用是什么？")
    ).toBeVisible();

    const practiceRequest = model.requests.filter(
      (request) =>
        (request.body.metadata as Record<string, unknown> | undefined)
          ?.study_notes_mode === "practice"
    )[0];
    expect(practiceRequest?.body).toMatchObject({
      metadata: {
        practice_count: 3,
        study_notes_mode: "practice"
      },
      stream: false
    });
    const practicePrompt = JSON.stringify(practiceRequest?.body.messages);
    expect(practicePrompt).toContain(
      "注意力帮助学习者筛选当前任务相关的信息。"
    );
    expect(practicePrompt).toContain("注意力会帮助学习者筛选当前任务相关信息。");

    await practice.getByLabel("A. 筛选任务相关信息").check();
    await practice.getByRole("button", { name: "提交答案" }).click();
    await expect(practice.getByText("回答正确")).toBeVisible();
    await expect(practice.getByText("资料指出注意力会筛选任务相关信息")).toBeVisible();
    const citation = practice.getByRole("button", { name: /资料引用/ });
    await expect(citation).toContainText(
      "注意力帮助学习者筛选当前任务相关的信息。"
    );
    await citation.click();
    await expect(page.locator('[aria-current="citation"]')).toContainText(
      "注意力帮助学习者筛选当前任务相关的信息。"
    );
    await practice.getByRole("button", { name: "下一题" }).click();

    await expect(practice.getByText("第 2 / 3 题")).toBeVisible();
    await practice.getByLabel("B. 资料数量无限").check();
    await practice.getByRole("button", { name: "提交答案" }).click();
    await expect(practice.getByText("回答错误")).toBeVisible();
    await expect(practice.getByText("正确答案：A. 工作记忆容量有限")).toBeVisible();
    await practice.getByRole("button", { name: "下一题" }).click();

    await expect(practice.getByText("第 3 / 3 题")).toBeVisible();
    await practice.getByLabel("A. 当前任务相关信息").check();
    await practice.getByRole("button", { name: "提交答案" }).click();
    await practice.getByRole("button", { name: "完成练习" }).click();
    await expect(practice.getByText("练习完成 · 3 / 3")).toBeVisible();

    const sessionId = await practice.getAttribute("data-session-id");
    expect(sessionId).toBeTruthy();
    const savedResponse = await page.request.get(
      `${app.webUrl}/api/tutor/sessions/${sessionId}/practice`
    );
    expect(savedResponse.ok()).toBe(true);
    const saved = (await savedResponse.json()) as {
      attempts: Array<{
        correct: boolean;
        selectedIndex: number;
      }>;
      practice: {
        questionCount: number;
        questions: PracticeQuestion[];
      };
    };
    expect(saved.practice.questionCount).toBe(3);
    expect(saved.practice.questions).toHaveLength(3);
    expect(saved.attempts).toHaveLength(3);
    expect(saved.attempts.map((attempt) => attempt.correct)).toEqual([
      true,
      false,
      true
    ]);
    for (const question of saved.practice.questions) {
      expect(question.citation.quote).toBe(
        "注意力帮助学习者筛选当前任务相关的信息。"
      );
      expect(question.correctIndex).toBeGreaterThanOrEqual(0);
      expect(question.correctIndex).toBeLessThan(question.options.length);
    }

    await practice.getByRole("button", { name: "再练一组" }).click();
    await questionCount.selectOption("1");
    await practice.getByRole("button", { name: "考考我" }).click();
    await expect(practice.getByText("第 1 / 1 题")).toBeVisible();
    expect(
      model.requests.at(-1)?.body.metadata as Record<string, unknown>
    ).toMatchObject({
      practice_count: 1,
      study_notes_mode: "practice"
    });
  } finally {
    await model.close();
    await app.stop();
    await rm(workspaceDir, { recursive: true, force: true });
  }
});

test("a short-answer Practice item shows grounded feedback and saves a corrected self-assessment", async ({
  page
}) => {
  const app = await startApp();
  const model = await startMockModel(async (body, _requestIndex, response) => {
    const metadata = (body.metadata ?? {}) as Record<string, unknown>;
    if (metadata.study_notes_mode === "practice") {
      sendChatCompletion(response, JSON.stringify(shortAnswerPracticePayload()));
      return;
    }
    if (metadata.study_notes_mode === "practice_grade") {
      sendChatCompletion(
        response,
        JSON.stringify(shortAnswerFeedbackPayload())
      );
      return;
    }
    if (body.stream === true) {
      await sendStreamingCompletion(
        response,
        JSON.stringify({
          type: "grounded",
          answer: "注意力会帮助学习者筛选当前任务相关信息。[S1]",
          citations: [
            {
              source_id: "S1",
              quote: "注意力帮助学习者筛选当前任务相关的信息。"
            }
          ],
          missing: []
        })
      );
      return;
    }
    sendChatCompletion(response, "OK");
  });
  const workspaceDir = await openStudyPage(page);

  try {
    const tutor = await prepareTutor(
      page,
      app.webUrl,
      workspaceDir,
      model.baseUrl
    );
    await page.getByLabel("向当前资料提问").fill("注意力为什么重要？");
    await tutor.getByRole("button", { name: "发送" }).click();
    await expect(tutor.getByText("已完成")).toBeVisible();

    const practice = page.getByRole("region", { name: "练习题" });
    await practice.getByLabel("练习题数量").selectOption("1");
    await practice.getByRole("button", { name: "考考我" }).click();
    await expect(practice.getByText("短答题", { exact: true })).toBeVisible();
    await expect(
      practice.getByText("用自己的话解释注意力如何影响学习。")
    ).toBeVisible();

    const answer = "注意力帮助我选择当前任务需要的信息。";
    await practice.getByLabel("短答题答案").fill(answer);
    await practice.getByRole("button", { name: "提交回答" }).click();

    await expect(practice.getByText("参考要点")).toBeVisible();
    await expect(practice.getByText("评分依据")).toBeVisible();
    await expect(practice.getByText("已命中")).toBeVisible();
    await expect(practice.getByText("遗漏项")).toBeVisible();
    await expect(
      practice.getByText("AI 初评 · 80 分")
    ).toBeVisible();
    const citation = practice.getByRole("button", { name: /资料引用/ });
    await expect(citation).toContainText(
      "注意力帮助学习者筛选当前任务相关的信息。"
    );
    await citation.click();
    await expect(page.locator('[aria-current="citation"]')).toContainText(
      "注意力帮助学习者筛选当前任务相关的信息。"
    );

    const gradeRequest = model.requests.find(
      (request) =>
        (request.body.metadata as Record<string, unknown> | undefined)
          ?.study_notes_mode === "practice_grade"
    );
    expect(gradeRequest?.body.metadata).toMatchObject({
      study_notes_mode: "practice_grade"
    });
    const gradePrompt = JSON.stringify(gradeRequest?.body.messages);
    expect(gradePrompt).toContain(answer);
    expect(gradePrompt).toContain(
      "注意力帮助学习者筛选当前任务相关的信息。"
    );

    const selfAssessment = practice.getByLabel("最终自评");
    await expect(selfAssessment).toHaveValue("80");
    await selfAssessment.fill("60");
    await practice.getByRole("button", { name: "保存自评" }).click();
    await expect(
      practice.getByText("AI 初评 · 80 分 · 最终自评 · 60 分")
    ).toBeVisible();
    await expect(
      practice.getByRole("button", { name: "完成练习" })
    ).toBeVisible();

    const sessionId = await practice.getAttribute("data-session-id");
    const savedResponse = await page.request.get(
      `${app.webUrl}/api/tutor/sessions/${sessionId}/practice`
    );
    expect(savedResponse.ok()).toBe(true);
    const saved = (await savedResponse.json()) as {
      attempts: Array<{
        aiScore: number | null;
        answerText: string | null;
        feedback: PracticeFeedback | null;
        feedbackStatus: string;
        finalScore: number | null;
      }>;
      practice: {
        questions: PracticeQuestion[];
      };
    };
    expect(saved.practice.questions[0]).toMatchObject({
      itemType: "short_answer",
      stem: "用自己的话解释注意力如何影响学习。",
      referenceAnswer:
        "注意力帮助学习者筛选当前任务相关的信息，并因为工作记忆容量有限而影响理解。"
    });
    expect(saved.attempts[0]).toMatchObject({
      aiScore: 80,
      answerText: answer,
      feedbackStatus: "graded",
      finalScore: 60
    });
    expect(saved.attempts[0].feedback).toMatchObject({
      score: 80,
      scoringBasis:
        "回答解释了注意力对相关信息筛选的作用；没有说明工作记忆容量限制。",
      matchedPoints: ["注意力帮助筛选当前任务相关的信息。"],
      missingPoints: ["工作记忆容量有限，因此注意力控制会影响理解。"]
    });
    expect(saved.attempts[0].feedback?.citations).toHaveLength(1);
  } finally {
    await model.close();
    await app.stop();
    await rm(workspaceDir, { recursive: true, force: true });
  }
});

test("a failed short-answer grading keeps the answer and supports manual assessment plus retry", async ({
  page
}) => {
  const app = await startApp();
  let gradingRequests = 0;
  const model = await startMockModel(async (body, _requestIndex, response) => {
    const metadata = (body.metadata ?? {}) as Record<string, unknown>;
    if (metadata.study_notes_mode === "practice") {
      sendChatCompletion(response, JSON.stringify(shortAnswerPracticePayload()));
      return;
    }
    if (metadata.study_notes_mode === "practice_grade") {
      gradingRequests += 1;
      if (gradingRequests === 1) {
        response.writeHead(500, { "Content-Type": "application/json" });
        response.end(JSON.stringify({ error: "temporary grading failure" }));
        return;
      }
      sendChatCompletion(
        response,
        JSON.stringify(shortAnswerFeedbackPayload())
      );
      return;
    }
    if (body.stream === true) {
      await sendStreamingCompletion(
        response,
        JSON.stringify({
          type: "grounded",
          answer: "注意力会帮助学习者筛选当前任务相关信息。[S1]",
          citations: [
            {
              source_id: "S1",
              quote: "注意力帮助学习者筛选当前任务相关的信息。"
            }
          ],
          missing: []
        })
      );
      return;
    }
    sendChatCompletion(response, "OK");
  });
  const workspaceDir = await openStudyPage(page);

  try {
    const tutor = await prepareTutor(
      page,
      app.webUrl,
      workspaceDir,
      model.baseUrl
    );
    await page.getByLabel("向当前资料提问").fill("注意力为什么重要？");
    await tutor.getByRole("button", { name: "发送" }).click();
    await expect(tutor.getByText("已完成")).toBeVisible();

    const practice = page.getByRole("region", { name: "练习题" });
    await practice.getByLabel("练习题数量").selectOption("1");
    await practice.getByRole("button", { name: "考考我" }).click();
    const answer = "注意力帮助我筛选任务需要的信息。";
    await practice.getByLabel("短答题答案").fill(answer);
    await practice.getByRole("button", { name: "提交回答" }).click();

    await expect(
      practice.getByText("AI 评分暂不可用，答案已保存")
    ).toBeVisible();
    await expect(practice.getByLabel("短答题答案")).toHaveValue(answer);
    await expect(
      practice.getByRole("button", { name: "重试评分" })
    ).toBeVisible();
    await expect(
      practice.getByRole("button", { name: "保存自评" })
    ).toBeVisible();
    await expect(
      practice.getByRole("button", { name: "完成练习" })
    ).toBeHidden();

    await practice.getByLabel("最终自评").fill("40");
    await practice.getByRole("button", { name: "保存自评" }).click();
    await expect(
      practice.getByText("AI 初评 · 未完成 · 最终自评 · 40 分")
    ).toBeVisible();
    await expect(
      practice.getByRole("button", { name: "完成练习" })
    ).toBeVisible();

    await practice.getByRole("button", { name: "重试评分" }).click();
    await expect(practice.getByText("参考要点")).toBeVisible();
    await expect(
      practice.getByText("AI 初评 · 80 分 · 最终自评 · 40 分")
    ).toBeVisible();

    const sessionId = await practice.getAttribute("data-session-id");
    const savedResponse = await page.request.get(
      `${app.webUrl}/api/tutor/sessions/${sessionId}/practice`
    );
    expect(savedResponse.ok()).toBe(true);
    const saved = (await savedResponse.json()) as {
      attempts: Array<{
        aiScore: number | null;
        answerText: string | null;
        feedbackStatus: string;
        finalScore: number | null;
      }>;
    };
    expect(saved.attempts[0]).toMatchObject({
      aiScore: 80,
      answerText: answer,
      feedbackStatus: "graded",
      finalScore: 40
    });
  } finally {
    await model.close();
    await app.stop();
    await rm(workspaceDir, { recursive: true, force: true });
  }
});

test("a failed Practice item becomes a Gap record and advances through Review", async ({
  page
}) => {
  const app = await startApp();
  const model = await startMockModel();
  const workspaceDir = await openStudyPage(page);

  try {
    const tutor = await prepareTutor(
      page,
      app.webUrl,
      workspaceDir,
      model.baseUrl
    );
    await page.getByLabel("向当前资料提问").fill("注意力为什么重要？");
    await tutor.getByRole("button", { name: "发送" }).click();
    await expect(tutor.getByText("已完成")).toBeVisible();

    const practice = page.getByRole("region", { name: "练习题" });
    await practice.getByLabel("练习题数量").selectOption("1");
    await practice.getByRole("button", { name: "考考我" }).click();
    await practice.getByLabel("B. 永久存储所有信息").check();
    await practice.getByRole("button", { name: "提交答案" }).click();
    await expect(practice.getByText("回答错误")).toBeVisible();

    await practice.getByRole("button", { name: "记为知识缺口" }).click();
    const gapDialog = page.getByRole("dialog", { name: "记录知识缺口" });
    await expect(gapDialog.getByLabel("缺口标题")).toHaveValue(
      "注意力对学习的主要作用是什么？"
    );
    await gapDialog.getByRole("button", { name: "加入复习" }).click();
    await expect(gapDialog).toBeHidden();
    await expect(practice.getByText("已加入复习队列")).toBeVisible();

    const sessionId = await practice.getAttribute("data-session-id");
    expect(sessionId).toBeTruthy();

    await page.getByRole("button", { name: "复习" }).click();
    const review = page.getByRole("region", { name: "复习" });
    await expect(review.getByText("注意力对学习的主要作用是什么？")).toBeVisible();
    const practiceGap = review
      .locator("article")
      .filter({ hasText: "注意力对学习的主要作用是什么？" });
    await practiceGap
      .getByLabel("复习答案")
      .fill("注意力帮助筛选当前任务信息。");
    await practiceGap
      .getByLabel("复习反馈")
      .fill("能够说明注意力的筛选作用。");
    await practiceGap.getByRole("button", { name: "通过" }).click();
    await expect(review.getByText(/已通过 · 下次复习/)).toBeVisible();

    const reviewResponse = await page.request.get(`${app.webUrl}/api/review`);
    expect(reviewResponse.ok()).toBe(true);
    const savedReview = (await reviewResponse.json()) as {
      queue: Array<{ id: string; title: string }>;
      records: Array<{
        id: string;
        title: string;
        nextReviewAt: string | null;
        reviews: Array<{
          answer: string;
          feedback: string;
          result: string;
          reviewedAt: string;
          nextReviewAt: string;
        }>;
      }>;
    };
    const gap = savedReview.records.find(
      (record) => record.title === "注意力对学习的主要作用是什么？"
    );
    expect(gap).toBeTruthy();
    expect(gap?.nextReviewAt).toBeTruthy();
    expect(gap?.reviews.at(-1)).toMatchObject({
      answer: "注意力帮助筛选当前任务信息。",
      feedback: "能够说明注意力的筛选作用。",
      result: "pass"
    });
    expect(savedReview.queue.map((record) => record.title)).not.toContain(
      "注意力对学习的主要作用是什么？"
    );

    const deleteSession = await page.request.delete(
      `${app.webUrl}/api/tutor/sessions/${sessionId}`
    );
    expect(deleteSession.ok()).toBe(true);

    const retainedResponse = await page.request.get(
      `${app.webUrl}/api/review/gaps/${gap?.id}`
    );
    expect(retainedResponse.ok()).toBe(true);
    const retained = (await retainedResponse.json()) as {
      id: string;
      practiceItem: { id: string; stem: string } | null;
      reviews: Array<{ result: string }>;
    };
    expect(retained.id).toBe(gap?.id);
    expect(retained.practiceItem).toMatchObject({
      stem: "注意力对学习的主要作用是什么？"
    });
    expect(retained.reviews.at(-1)?.result).toBe("pass");
  } finally {
    await model.close();
    await app.stop();
    await rm(workspaceDir, { recursive: true, force: true });
  }
});

test("Review schedules 1, 3, 7, 14 days, batches 20 items, and supports date controls", async ({
  page
}) => {
  const app = await startApp();
  const workspaceDir = await openStudyPage(page);

  try {
    await page.goto(app.webUrl);
    await page.getByLabel("Notebook workspace 路径").fill(workspaceDir);
    await page.getByRole("button", { name: "打开工作区" }).click();
    await expect(
      page.getByRole("button", { name: "注意力机制.md", exact: true })
    ).toBeVisible();

    const sessionResponse = await page.request.post(
      `${app.webUrl}/api/tutor/sessions`,
      {
        data: {
          path: "课程/注意力机制.md",
          quote: "注意力帮助学习者筛选当前任务相关的信息。"
        }
      }
    );
    expect(sessionResponse.ok()).toBe(true);
    const session = (await sessionResponse.json()) as { id: string };

    const gapIds: string[] = [];
    for (let index = 1; index <= 21; index += 1) {
      const title = `复习调度 ${String(index).padStart(2, "0")}`;
      const gapResponse = await page.request.post(
        `${app.webUrl}/api/tutor/sessions/${session.id}/gaps`,
        { data: { title } }
      );
      expect(gapResponse.ok()).toBe(true);
      const gap = (await gapResponse.json()) as {
        id: string;
        practiceItem: unknown;
      };
      expect(gap.practiceItem).toBeNull();
      gapIds.push(gap.id);
    }

    const initialReview = await page.request.get(`${app.webUrl}/api/review`);
    expect(initialReview.ok()).toBe(true);
    const initial = (await initialReview.json()) as {
      queue: Array<{ id: string }>;
      records: Array<{ id: string }>;
    };
    expect(initial.records).toHaveLength(21);
    expect(initial.queue).toHaveLength(20);
    expect(initial.queue[0].id).toBe(gapIds[0]);

    const targetGapId = gapIds[0];
    const targetTitle = "复习调度 01";
    const intervals = [1, 3, 7, 14];
    for (const expectedDays of intervals) {
      const dueResponse = await page.request.patch(
        `${app.webUrl}/api/review/gaps/${targetGapId}`,
        { data: { next_review_at: new Date().toISOString() } }
      );
      expect(dueResponse.ok()).toBe(true);

      const resultResponse = await page.request.post(
        `${app.webUrl}/api/review/gaps/${targetGapId}/results`,
        {
          data: {
            answer: `第 ${expectedDays} 天阶段答案`,
            feedback: "按通过路径推进",
            result: "pass"
          }
        }
      );
      expect(resultResponse.ok()).toBe(true);
      const result = (await resultResponse.json()) as {
        review: { reviewedAt: string; nextReviewAt: string };
      };
      const difference =
        (new Date(result.review.nextReviewAt).getTime() -
          new Date(result.review.reviewedAt).getTime()) /
        86_400_000;
      expect(difference).toBeCloseTo(expectedDays, 5);
    }

    const retryDue = await page.request.patch(
      `${app.webUrl}/api/review/gaps/${targetGapId}`,
      { data: { next_review_at: new Date().toISOString() } }
    );
    expect(retryDue.ok()).toBe(true);
    const retryResponse = await page.request.post(
      `${app.webUrl}/api/review/gaps/${targetGapId}/results`,
      {
        data: {
          answer: "重来后的答案",
          feedback: "重来应重置到一天",
          result: "again"
        }
      }
    );
    expect(retryResponse.ok()).toBe(true);
    const retry = (await retryResponse.json()) as {
      gap: { scheduleStep: number };
      review: { reviewedAt: string; nextReviewAt: string; result: string };
    };
    expect(retry.review.result).toBe("again");
    expect(retry.gap.scheduleStep).toBe(0);
    expect(
      (new Date(retry.review.nextReviewAt).getTime() -
        new Date(retry.review.reviewedAt).getTime()) /
        86_400_000
    ).toBeCloseTo(1, 5);

    await page.getByRole("button", { name: "复习" }).click();
    const review = page.getByRole("region", { name: "复习" });
    await review.getByRole("tab", { name: "全部记录" }).click();
    const record = review
      .locator("article")
      .filter({ hasText: targetTitle })
      .first();
    await expect(record).toBeVisible();
    const dateInput = record.getByLabel(`下次复习时间 · ${targetTitle}`);
    await dateInput.fill("2027-02-03T10:30");
    await record.getByRole("button", { name: "保存日期" }).click();
    await expect
      .poll(async () => {
        const response = await page.request.get(
          `${app.webUrl}/api/review/gaps/${targetGapId}`
        );
        const gap = (await response.json()) as {
          nextReviewAt: string | null;
          reviews: unknown[];
        };
        return {
          hasDate: Boolean(gap.nextReviewAt),
          reviewCount: gap.reviews.length
        };
      })
      .toEqual({ hasDate: true, reviewCount: 5 });

    await record.getByRole("button", { name: "清除日期" }).click();
    await expect
      .poll(async () => {
        const response = await page.request.get(
          `${app.webUrl}/api/review/gaps/${targetGapId}`
        );
        const gap = (await response.json()) as {
          nextReviewAt: string | null;
        };
        return gap.nextReviewAt;
      })
      .toBeNull();
  } finally {
    await app.stop();
    await rm(workspaceDir, { recursive: true, force: true });
  }
});
