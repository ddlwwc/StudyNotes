import { expect, test } from "@playwright/test";
import type { Page } from "@playwright/test";
import { spawn, type ChildProcess } from "node:child_process";
import { createServer } from "node:http";
import type { IncomingMessage, ServerResponse } from "node:http";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";

type RunningApp = {
  stop: () => Promise<void>;
  webUrl: string;
};

type ModelRequest = {
  authorization: string | undefined;
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

function reservePort(): number {
  return 45_000 + Math.floor(Math.random() * 10_000);
}

async function readRequestBody(request: IncomingMessage): Promise<string> {
  const chunks: Buffer[] = [];
  for await (const chunk of request) {
    chunks.push(Buffer.from(chunk));
  }
  return Buffer.concat(chunks).toString("utf8");
}

function sendChatCompletion(
  response: ServerResponse,
  content: string
) {
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
  const chunkSize = 18;
  for (let index = 0; index < content.length; index += chunkSize) {
    response.write(
      `data: ${JSON.stringify({
        choices: [{ delta: { content: content.slice(index, index + chunkSize) } }]
      })}\n\n`
    );
    await new Promise((resolve) => setTimeout(resolve, 12));
  }
  response.write("data: [DONE]\n\n");
  response.end();
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
    requests.push({
      authorization: request.headers.authorization,
      body
    });
    if (responder) {
      await responder(body, requests.length - 1, response);
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

async function waitForHttp(url: string, child: ChildProcess, output: () => string) {
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

async function startApp(): Promise<RunningApp & { dataDir: string }> {
  const dataDir = await mkdtemp(path.join(tmpdir(), "studynotes-data-"));
  const backendPort = reservePort();
  const webPort = reservePort();
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
    dataDir,
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

async function openStudyPage(page: Page) {
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

test("a user can configure and test an OpenAI-compatible model", async ({
  page
}) => {
  const app = await startApp();
  const model = await startMockModel();
  const workspaceDir = await openStudyPage(page);

  try {
    await page.goto(app.webUrl);
    await page
      .getByLabel("Notebook workspace 路径")
      .fill(workspaceDir);
    await page.getByRole("button", { name: "打开工作区" }).click();
    await page.getByRole("button", { name: "设置" }).click();

    await page.getByLabel("Base URL").fill(model.baseUrl);
    await page.getByLabel("API Key").fill("test-key");
    await page.getByLabel("聊天模型").fill("mock-model");
    await page.getByRole("button", { name: "测试连接" }).click();

    await expect(page.getByText("连接成功")).toBeVisible();
    expect(model.requests).toHaveLength(1);
    expect(model.requests[0].authorization).toBe("Bearer test-key");
    expect(model.requests[0].body).toMatchObject({
      messages: expect.any(Array),
      model: "mock-model"
    });

    await page.getByRole("button", { name: "保存设置" }).click();
    await expect(page.getByRole("dialog", { name: "模型设置" })).toBeHidden();
  } finally {
    await model.close();
    await app.stop();
    await rm(workspaceDir, { recursive: true, force: true });
  }
});

test("asking from a Markdown block streams a grounded answer with auditable context", async ({
  page
}) => {
  const app = await startApp();
  const model = await startMockModel();
  const workspaceDir = await openStudyPage(page);

  try {
    await page.goto(app.webUrl);
    await page.getByLabel("Notebook workspace 路径").fill(workspaceDir);
    await page.getByRole("button", { name: "打开工作区" }).click();
    await configureModel(page, model.baseUrl);
    await page
      .getByRole("button", { name: "注意力机制.md", exact: true })
      .click();
    await page
      .getByText("注意力帮助学习者筛选当前任务相关的信息。", { exact: true })
      .click();

    const tutor = page.getByRole("complementary", { name: "Grounded tutor" });
    await expect(tutor).toContainText("注意力帮助学习者筛选当前任务相关的信息。");
    await expect(
      tutor.getByRole("button", { name: "引导式" })
    ).toHaveAttribute("aria-pressed", "true");
    await expect(
      tutor.getByRole("button", { name: "直接解释" })
    ).toHaveAttribute("aria-pressed", "false");

    await page
      .getByLabel("向当前资料提问")
      .fill("为什么注意力会影响理解？");
    await tutor.getByRole("button", { name: "发送" }).click();

    await expect(tutor.getByText("正在生成…")).toBeVisible();
    await expect(
      tutor.getByText("注意力会帮助学习者筛选当前任务相关信息。", {
        exact: false
      })
    ).toBeVisible();
    await expect(tutor.getByText("已完成")).toBeVisible();
    const citation = tutor.getByRole("button", {
      name: /Source citation/
    });
    await expect(citation).toContainText(
      "注意力帮助学习者筛选当前任务相关的信息。"
    );
    await citation.click();
    await expect(page.locator('[aria-current="citation"]')).toContainText(
      "注意力帮助学习者筛选当前任务相关的信息。"
    );

    await tutor.getByRole("button", { name: "查看上下文" }).click();
    const contextDrawer = page.getByRole("region", { name: "上下文" });
    await expect(contextDrawer).toContainText("选中资料");
    await expect(contextDrawer).toContainText(
      "注意力帮助学习者筛选当前任务相关的信息。"
    );
    await expect(contextDrawer).toContainText("实际发送范围");
    await expect(contextDrawer).toContainText("课程/注意力机制.md");

    const guidedRequest = model.requests.at(-1);
    expect(guidedRequest?.body).toMatchObject({
      metadata: {
        study_notes_mode: "guided",
        supplement_requested: false
      },
      stream: true
    });
    expect(JSON.stringify(guidedRequest?.body.messages)).toContain(
      "注意力帮助学习者筛选当前任务相关的信息。"
    );

    await tutor.getByRole("button", { name: "直接解释" }).click();
    await page.getByLabel("向当前资料提问").fill("请直接解释这个结论。");
    await tutor.getByRole("button", { name: "发送" }).click();
    await expect(
      tutor.getByText("注意力会帮助学习者筛选当前任务相关信息。", {
        exact: false
      })
    ).toBeVisible();
    expect(model.requests.at(-1)?.body).toMatchObject({
      metadata: {
        study_notes_mode: "direct",
        supplement_requested: false
      }
    });
  } finally {
    await model.close();
    await app.stop();
    await rm(workspaceDir, { recursive: true, force: true });
  }
});

test("an invalid Source citation is retried before a grounded answer is shown", async ({
  page
}) => {
  const app = await startApp();
  const model = await startMockModel(async (body, requestIndex, response) => {
    const valid = requestIndex === 1;
    await sendStreamingCompletion(
      response,
      JSON.stringify({
        type: "grounded",
        answer: valid ? "检索到的资料支持这个结论。[S1]" : "错误引用。[S1]",
        citations: [
          {
            source_id: "S1",
            quote: valid
              ? "注意力帮助学习者筛选当前任务相关的信息。"
              : "这是一段不存在于资料中的原文。"
          }
        ],
        missing: []
      })
    );
  });
  const workspaceDir = await openStudyPage(page);

  try {
    const tutor = await prepareTutor(
      page,
      app.webUrl,
      workspaceDir,
      model.baseUrl
    );
    await page.getByLabel("向当前资料提问").fill("这个结论有资料支持吗？");
    await tutor.getByRole("button", { name: "发送" }).click();

    await expect(tutor.getByText("已完成")).toBeVisible();
    await expect(tutor.getByText("检索到的资料支持这个结论。")).toBeVisible();
    await expect(tutor.getByText("错误引用。")).toHaveCount(0);
    expect(model.requests).toHaveLength(2);
    expect(JSON.stringify(model.requests[1].body.messages)).toContain(
      "未通过引用验证"
    );
  } finally {
    await model.close();
    await app.stop();
    await rm(workspaceDir, { recursive: true, force: true });
  }
});

test("insufficient evidence exposes a clearly marked supplement only after explicit request", async ({
  page
}) => {
  const app = await startApp();
  const model = await startMockModel(async (body, requestIndex, response) => {
    const supplementRequested =
      (body.metadata as Record<string, unknown> | undefined)
        ?.supplement_requested === true;
    await sendStreamingCompletion(
      response,
      JSON.stringify(
        supplementRequested
          ? {
              type: "unsupported_supplement",
              answer: "从一般认知科学看，注意力资源竞争会降低理解效率。",
              citations: [],
              missing: []
            }
          : {
              type: "insufficient_evidence",
              answer: "当前资料没有说明注意力影响理解的具体机制。",
              citations: [],
              missing: ["缺少注意力与理解机制之间的证据。"]
            }
      )
    );
    expect(requestIndex).toBe(supplementRequested ? 1 : 0);
  });
  const workspaceDir = await openStudyPage(page);

  try {
    const tutor = await prepareTutor(
      page,
      app.webUrl,
      workspaceDir,
      model.baseUrl
    );
    await page.getByLabel("向当前资料提问").fill("具体机制是什么？");
    await tutor.getByRole("button", { name: "发送" }).click();

    await expect(tutor.getByText("证据不足")).toBeVisible();
    await expect(tutor.getByText("当前资料没有说明注意力影响理解的具体机制。"))
      .toBeVisible();
    await expect(tutor.getByText("Unsupported supplement")).toHaveCount(0);

    await tutor.getByRole("button", { name: "请求模型补充" }).click();
    await expect(tutor.getByText("Unsupported supplement")).toBeVisible();
    await expect(tutor.getByText("不来自 Learning source")).toBeVisible();
    await expect(
      tutor.getByText("从一般认知科学看，注意力资源竞争会降低理解效率。")
    ).toBeVisible();
    expect(model.requests.at(-1)?.body).toMatchObject({
      metadata: {
        supplement_requested: true
      }
    });
  } finally {
    await model.close();
    await app.stop();
    await rm(workspaceDir, { recursive: true, force: true });
  }
});

test("a streaming answer can be stopped and recovers from a model error by retrying", async ({
  page
}) => {
  const app = await startApp();
  const model = await startMockModel(async (body, requestIndex, response) => {
    if (requestIndex === 0) {
      await new Promise((resolve) => setTimeout(resolve, 500));
    }
    if (requestIndex === 1) {
      response.writeHead(500, { "Content-Type": "application/json" });
      response.end(JSON.stringify({ error: { message: "mock failure" } }));
      return;
    }
    await sendStreamingCompletion(
      response,
      JSON.stringify({
        type: "grounded",
        answer: "重试后的资料回答。[S1]",
        citations: [
          {
            source_id: "S1",
            quote: "注意力帮助学习者筛选当前任务相关的信息。"
          }
        ],
        missing: []
      })
    );
  });
  const workspaceDir = await openStudyPage(page);

  try {
    const tutor = await prepareTutor(
      page,
      app.webUrl,
      workspaceDir,
      model.baseUrl
    );
    await page.getByLabel("向当前资料提问").fill("请解释这个结论。");
    await tutor.getByRole("button", { name: "发送" }).click();
    await expect(tutor.getByText("正在生成…")).toBeVisible();
    await tutor.getByRole("button", { name: "停止" }).click();
    await expect(tutor.getByText("已停止")).toBeVisible();

    await new Promise((resolve) => setTimeout(resolve, 650));
    await tutor.getByRole("button", { name: "重试回答" }).click();
    await expect(tutor.getByText("回答失败")).toBeVisible();
    await expect(tutor.getByText("模型服务返回 HTTP 500。")).toBeVisible();

    await tutor.getByRole("button", { name: "重试", exact: true }).click();
    await expect(tutor.getByText("已完成")).toBeVisible();
    await expect(tutor.getByText("重试后的资料回答。")).toBeVisible();
    expect(model.requests.length).toBeGreaterThanOrEqual(3);
  } finally {
    await model.close();
    await app.stop();
    await rm(workspaceDir, { recursive: true, force: true });
  }
});
