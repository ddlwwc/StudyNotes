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
  url: string | undefined;
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

type EmbeddingResponder = (
  inputs: string[],
  requestIndex: number,
  response: ServerResponse
) => Promise<void> | void;

type TutorSentContext = {
  chunks: Array<{
    blockId: string | null;
    blockIndex: number | null;
    page: number | null;
    path: string;
    sourceId: string;
    text: string;
  }>;
};

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

function sendEmbedding(
  response: ServerResponse,
  inputs: string[]
) {
  response.writeHead(200, { "Content-Type": "application/json" });
  response.end(
    JSON.stringify({
      object: "list",
      data: inputs.map((input, index) => ({
        object: "embedding",
        index,
        embedding: input.includes("短时记忆")
          ? [1, 0, 0]
          : input.includes("工作记忆容量")
            ? [0.98, 0.18, 0]
            : [0, 1, 0]
      })),
      model: "mock-embedding"
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

async function startMockModel(
  responder?: ModelResponder,
  embeddingResponder?: EmbeddingResponder
): Promise<MockModel> {
  const requests: ModelRequest[] = [];
  const server = createServer(async (request, response) => {
    if (
      request.method !== "POST" ||
      !["/v1/chat/completions", "/v1/embeddings"].includes(
        request.url ?? ""
      )
    ) {
      response.writeHead(404);
      response.end();
      return;
    }

    const raw = await readRequestBody(request);
    const body = JSON.parse(raw) as Record<string, unknown>;
    requests.push({
      authorization: request.headers.authorization,
      body,
      url: request.url
    });
    if (request.url === "/v1/embeddings") {
      const inputs = Array.isArray(body.input)
        ? body.input.map(String)
        : [String(body.input ?? "")];
      if (embeddingResponder) {
        await embeddingResponder(inputs, requests.length - 1, response);
        return;
      }
      sendEmbedding(response, inputs);
      return;
    }
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

function createTextLayerPdf(): Buffer {
  const firstPageStream =
    "BT /F1 16 Tf 72 700 Td (PDF attention evidence.) Tj " +
    "0 -26 Td (Attention allocation shapes comprehension.) Tj ET";
  const objects = [
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    `<< /Length ${Buffer.byteLength(firstPageStream, "ascii")} >>\nstream\n${firstPageStream}\nendstream`
  ];
  let pdf = "%PDF-1.4\n";
  const offsets = [0];

  objects.forEach((object, index) => {
    offsets.push(Buffer.byteLength(pdf, "ascii"));
    pdf += `${index + 1} 0 obj\n${object}\nendobj\n`;
  });

  const xrefOffset = Buffer.byteLength(pdf, "ascii");
  pdf += `xref\n0 ${objects.length + 1}\n`;
  pdf += "0000000000 65535 f \n";
  offsets.slice(1).forEach((offset) => {
    pdf += `${offset.toString().padStart(10, "0")} 00000 n \n`;
  });
  pdf += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n`;
  pdf += `startxref\n${xrefOffset}\n%%EOF\n`;

  return Buffer.from(pdf, "ascii");
}

async function selectPdfText(page: Page, text: string) {
  const textLine = page.getByLabel("PDF 文本层").getByText(text, {
    exact: true
  });
  await expect(textLine).toBeVisible();
  await textLine.evaluate((element) => {
    const range = document.createRange();
    range.selectNodeContents(element);
    const selection = window.getSelection();
    selection?.removeAllRanges();
    selection?.addRange(range);
    document.dispatchEvent(new Event("selectionchange"));
  });
  await expect(
    page.getByRole("region", { name: "选中片段" })
  ).toContainText(text);
}

async function selectMarkdownText(
  page: Page,
  fullText: string,
  selectedText: string
) {
  const blockText = page.getByText(fullText, { exact: true });
  await expect(blockText).toBeVisible();
  await blockText.evaluate((element, fragment) => {
    const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT);
    let textNode: Text | null = null;
    while (walker.nextNode()) {
      const candidate = walker.currentNode as Text;
      if (candidate.data.includes(fragment)) {
        textNode = candidate;
        break;
      }
    }
    if (!textNode) {
      throw new Error("Markdown fragment was not found.");
    }
    const start = textNode.data.indexOf(fragment);
    const range = document.createRange();
    range.setStart(textNode, start);
    range.setEnd(textNode, start + fragment.length);
    const selection = window.getSelection();
    selection?.removeAllRanges();
    selection?.addRange(range);
    element.dispatchEvent(new MouseEvent("mouseup", { bubbles: true }));
  }, selectedText);
}

function parseTutorContext(body: Record<string, unknown>): TutorSentContext {
  const messages = body.messages as
    | Array<{ content?: string }>
    | undefined;
  const contextMessage = messages?.find((message) =>
    message.content?.startsWith("Learning source 上下文：")
  )?.content;
  if (!contextMessage) {
    throw new Error("Tutor context was not sent to the model.");
  }
  const prefix = "Learning source 上下文：\n";
  const start = contextMessage.indexOf(prefix);
  const end = contextMessage.lastIndexOf("\n\n问题：");
  if (start < 0 || end < start) {
    throw new Error("Tutor context message was malformed.");
  }
  return JSON.parse(
    contextMessage.slice(start + prefix.length, end)
  ) as TutorSentContext;
}

async function configureModel(
  page: Page,
  baseUrl: string,
  embeddingModel?: string
) {
  await page.getByRole("button", { name: "设置" }).click();
  await page.getByLabel("Base URL").fill(baseUrl);
  await page.getByLabel("API Key").fill("test-key");
  await page.getByLabel("聊天模型").fill("mock-model");
  if (embeddingModel) {
    await page.getByLabel("Embedding 模型").fill(embeddingModel);
    await page.getByLabel("启用语义检索").check();
  }
  await page.getByRole("button", { name: "保存设置" }).click();
  await expect(page.getByRole("dialog", { name: "模型设置" })).toBeHidden();
}

async function prepareTutor(
  page: Page,
  webUrl: string,
  workspaceDir: string,
  baseUrl: string,
  embeddingModel?: string
) {
  await page.goto(webUrl);
  await page.getByLabel("Notebook workspace 路径").fill(workspaceDir);
  await page.getByRole("button", { name: "打开工作区" }).click();
  await configureModel(page, baseUrl, embeddingModel);
  await page
    .getByRole("button", { name: "注意力机制.md", exact: true })
    .click();
  await page
    .getByText("注意力帮助学习者筛选当前任务相关的信息。", { exact: true })
    .click();
  const tutor = page.getByRole("complementary", { name: "Grounded tutor" });
  await expect(tutor).toContainText("已绑定 Markdown 选区");
  return tutor;
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

test("embedding settings can be configured, tested, and disabled", async ({
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
    await page.getByLabel("Embedding 模型").fill("mock-embedding");
    await page.getByLabel("启用语义检索").check();
    await page.getByRole("button", { name: "测试 Embedding" }).click();

    await expect(page.getByText("Embedding 连接成功")).toBeVisible();
    const embeddingTest = model.requests.find(
      (request) => request.url === "/v1/embeddings"
    );
    expect(embeddingTest?.authorization).toBe("Bearer test-key");
    expect(embeddingTest?.body).toMatchObject({
      input: expect.any(Array),
      model: "mock-embedding"
    });

    await page.getByRole("button", { name: "保存设置" }).click();
    await expect(page.getByRole("dialog", { name: "模型设置" })).toBeHidden();
    const enabledSettings = await page.evaluate(async () => {
      const response = await fetch("/api/model-settings");
      return response.json();
    });
    expect(enabledSettings).toMatchObject({
      embeddingEnabled: true,
      embeddingModel: "mock-embedding"
    });

    await page.getByRole("button", { name: "设置" }).click();
    await page.getByLabel("启用语义检索").uncheck();
    await page.getByRole("button", { name: "保存设置" }).click();
    const disabledSettings = await page.evaluate(async () => {
      const response = await fetch("/api/model-settings");
      return response.json();
    });
    expect(disabledSettings).toMatchObject({
      embeddingEnabled: false,
      embeddingModel: "mock-embedding"
    });

    const embeddingRequestCount = model.requests.filter(
      (request) => request.url === "/v1/embeddings"
    ).length;
    await page
      .getByRole("button", { name: "注意力机制.md", exact: true })
      .click();
    await page
      .getByText("注意力帮助学习者筛选当前任务相关的信息。", { exact: true })
      .click();
    const tutor = page.getByRole("complementary", { name: "Grounded tutor" });
    await page
      .getByLabel("向当前资料提问")
      .fill("注意力帮助学习者筛选当前任务相关的信息。");
    await tutor.getByRole("button", { name: "发送" }).click();
    await expect(tutor.getByText("已完成")).toBeVisible();
    await expect(tutor.getByText("检索模式：全文检索")).toBeVisible();
    expect(
      model.requests.filter((request) => request.url === "/v1/embeddings")
    ).toHaveLength(embeddingRequestCount);
  } finally {
    await model.close();
    await app.stop();
    await rm(workspaceDir, { recursive: true, force: true });
  }
});

test("semantic retrieval finds a lexically different passage with a Source citation", async ({
  page
}) => {
  const app = await startApp();
  const model = await startMockModel(async (body, _requestIndex, response) => {
    expect(JSON.stringify(body.messages)).toContain("工作记忆容量有限");
    await sendStreamingCompletion(
      response,
      JSON.stringify({
        type: "grounded",
        answer: "工作记忆容量有限，会限制同时处理的信息量。[S2]",
        citations: [
          {
            source_id: "S2",
            quote: "工作记忆容量有限，因此注意力控制会影响理解。"
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
      model.baseUrl,
      "mock-embedding"
    );
    await page.getByLabel("向当前资料提问").fill("短时记忆有什么限制？");
    await tutor.getByRole("button", { name: "发送" }).click();

    await expect(tutor.getByText("已完成")).toBeVisible();
    const citation = tutor.getByRole("button", {
      name: /Source citation.*工作记忆容量有限/
    });
    await expect(citation).toBeVisible();
    await citation.click();
    await expect(page.locator('[aria-current="citation"]')).toContainText(
      "工作记忆容量有限"
    );

    await tutor.getByRole("button", { name: "查看上下文" }).click();
    const contextDrawer = page.getByRole("region", { name: "上下文" });
    await expect(contextDrawer).toContainText("检索模式：语义检索");
    await expect(contextDrawer).toContainText("工作记忆容量有限");
    expect(
      model.requests.some((request) => request.url === "/v1/embeddings")
    ).toBe(true);
  } finally {
    await model.close();
    await app.stop();
    await rm(workspaceDir, { recursive: true, force: true });
  }
});

test("embedding failure automatically falls back to full-text retrieval", async ({
  page
}) => {
  const app = await startApp();
  const model = await startMockModel(
    async (body, _requestIndex, response) => {
      expect(JSON.stringify(body.messages)).toContain("工作记忆容量有限");
      await sendStreamingCompletion(
        response,
        JSON.stringify({
          type: "grounded",
          answer: "工作记忆的容量限制会影响理解。[S2]",
          citations: [
            {
              source_id: "S2",
              quote: "工作记忆容量有限，因此注意力控制会影响理解。"
            }
          ],
          missing: []
        })
      );
    },
    (_inputs, _requestIndex, response) => {
      response.writeHead(500, { "Content-Type": "application/json" });
      response.end(JSON.stringify({ error: { message: "embedding failed" } }));
    }
  );
  const workspaceDir = await openStudyPage(page);

  try {
    const tutor = await prepareTutor(
      page,
      app.webUrl,
      workspaceDir,
      model.baseUrl,
      "mock-embedding"
    );
    await page.getByLabel("向当前资料提问").fill("工作记忆容量有限");
    await tutor.getByRole("button", { name: "发送" }).click();

    await expect(tutor.getByText("已完成")).toBeVisible();
    await expect(tutor.getByText("检索模式：全文检索（已降级）")).toBeVisible();
    const citation = tutor.getByRole("button", {
      name: /Source citation.*工作记忆容量有限/
    });
    await expect(citation).toBeVisible();
    await citation.click();
    await expect(page.locator('[aria-current="citation"]')).toContainText(
      "工作记忆容量有限"
    );
    expect(
      model.requests.some((request) => request.url === "/v1/embeddings")
    ).toBe(true);
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

test("a selected Markdown fragment is not duplicated by matching retrieval", async ({
  page
}) => {
  const app = await startApp();
  const model = await startMockModel();
  const workspaceDir = await openStudyPage(page);
  const paragraph =
    "注意力帮助学习者筛选当前任务相关的信息。工作记忆容量有限，因此注意力控制会影响理解。";
  await writeFile(
    path.join(workspaceDir, "课程", "注意力机制.md"),
    ["# 注意力机制", "", paragraph].join("\n"),
    "utf8"
  );

  try {
    await page.goto(app.webUrl);
    await page.getByLabel("Notebook workspace 路径").fill(workspaceDir);
    await page.getByRole("button", { name: "打开工作区" }).click();
    await configureModel(page, model.baseUrl);
    await page
      .getByRole("button", { name: "注意力机制.md", exact: true })
      .click();
    await selectMarkdownText(
      page,
      paragraph,
      "注意力帮助学习者筛选当前任务相关的信息。"
    );

    const tutor = page.getByRole("complementary", { name: "Grounded tutor" });
    await expect(tutor).toContainText(
      "注意力帮助学习者筛选当前任务相关的信息。"
    );
    await page
      .getByLabel("向当前资料提问")
      .fill("注意力如何帮助筛选信息？");
    await tutor.getByRole("button", { name: "发送" }).click();
    await expect(tutor.getByText("已完成")).toBeVisible();

    const context = parseTutorContext(model.requests[0]?.body ?? {});
    const matchingChunks = context.chunks.filter((chunk) =>
      chunk.path.endsWith("注意力机制.md")
    );
    expect(matchingChunks).toHaveLength(1);
    const identities = context.chunks.map((chunk) =>
      [
        chunk.path,
        chunk.blockId ?? "",
        chunk.blockIndex ?? "",
        chunk.page ?? ""
      ].join(":")
    );
    expect(new Set(identities).size).toBe(identities.length);
  } finally {
    await model.close();
    await app.stop();
    await rm(workspaceDir, { recursive: true, force: true });
  }
});

test("a PDF selection can start a grounded Learning session directly", async ({
  page
}) => {
  const app = await startApp();
  const model = await startMockModel(async (body, requestIndex, response) => {
    expect(requestIndex).toBe(0);
    expect(JSON.stringify(body.messages)).toContain("PDF attention evidence.");
    await sendStreamingCompletion(
      response,
      JSON.stringify({
        type: "grounded",
        answer: "PDF 资料说明注意力分配会影响理解。[S1]",
        citations: [
          {
            source_id: "S1",
            quote: "PDF attention evidence."
          }
        ],
        missing: []
      })
    );
  });
  const workspaceDir = await openStudyPage(page);
  const pdfPath = path.join(workspaceDir, "课程", "注意力研究.pdf");
  await writeFile(pdfPath, createTextLayerPdf());

  try {
    await page.goto(app.webUrl);
    await page.getByLabel("Notebook workspace 路径").fill(workspaceDir);
    await page.getByRole("button", { name: "打开工作区" }).click();
    await configureModel(page, model.baseUrl);
    await page
      .getByRole("button", { name: "注意力研究.pdf", exact: true })
      .click();

    await expect(page.getByText("第 1 / 1 页", { exact: true })).toBeVisible();
    await selectPdfText(page, "PDF attention evidence.");
    await page.getByRole("button", { name: "用此片段发起提问" }).click();

    const tutor = page.getByRole("complementary", { name: "Grounded tutor" });
    await expect(tutor).toContainText("PDF 第 1 页");
    await expect(tutor).toContainText("PDF attention evidence.");
    await page.getByLabel("向当前资料提问").fill("这段资料说明了什么？");
    await tutor.getByRole("button", { name: "发送" }).click();

    await expect(tutor.getByText("已完成")).toBeVisible();
    await expect(tutor.getByText("PDF 资料说明注意力分配会影响理解。")).toBeVisible();
  } finally {
    await model.close();
    await app.stop();
    await rm(workspaceDir, { recursive: true, force: true });
  }
});

test("a Learning session answers across pinned Markdown and PDF sources with exact citation jumps", async ({
  page
}) => {
  const app = await startApp();
  const model = await startMockModel(async (body, requestIndex, response) => {
    expect(requestIndex).toBe(0);
    const context = parseTutorContext(body);
    const markdownChunk = context.chunks.find((chunk) =>
      chunk.path.endsWith("注意力机制.md")
    );
    const pdfChunk = context.chunks.find((chunk) =>
      chunk.path.endsWith("注意力研究.pdf")
    );
    if (!markdownChunk || !pdfChunk) {
      throw new Error("Mixed Markdown and PDF context was not sent.");
    }

    await sendStreamingCompletion(
      response,
      JSON.stringify({
        type: "grounded",
        answer:
          `Markdown 解释注意力筛选信息。[${markdownChunk.sourceId}] ` +
          `PDF 资料补充注意力分配与理解的关系。[${pdfChunk.sourceId}]`,
        citations: [
          {
            source_id: markdownChunk.sourceId,
            quote: "注意力帮助学习者筛选当前任务相关的信息。"
          },
          {
            source_id: pdfChunk.sourceId,
            quote: "PDF attention evidence."
          }
        ],
        missing: []
      })
    );
  });
  const workspaceDir = await openStudyPage(page);
  await writeFile(
    path.join(workspaceDir, "课程", "注意力研究.pdf"),
    createTextLayerPdf()
  );
  await mkdir(path.join(workspaceDir, "补充"), { recursive: true });
  await Promise.all(
    Array.from({ length: 8 }, (_, index) =>
      writeFile(
        path.join(workspaceDir, "补充", `证据-${index + 1}.md`),
        `# 证据 ${index + 1}\n\n注意力证据帮助理解任务与工作记忆。`,
        "utf8"
      )
    )
  );

  try {
    const tutor = await prepareTutor(
      page,
      app.webUrl,
      workspaceDir,
      model.baseUrl
    );
    await page
      .getByLabel("选择其他 Learning source")
      .selectOption("课程/注意力研究.pdf");
    await tutor.getByRole("button", { name: "固定来源" }).click();
    await expect(tutor.locator(".tutor-source-status")).toContainText("已固定");
    await expect(tutor).toContainText("2 个来源");

    await tutor
      .getByRole("button", { name: "移除 课程/注意力研究.pdf" })
      .click();
    await expect(tutor.locator(".tutor-source-status")).toContainText("已移除");
    await expect(tutor).toContainText("1 个来源");

    await page
      .getByLabel("选择其他 Learning source")
      .selectOption("课程/注意力研究.pdf");
    await tutor.getByRole("button", { name: "固定来源" }).click();
    await expect(tutor).toContainText("2 个来源");

    await page
      .getByText("工作记忆容量有限，因此注意力控制会影响理解。", {
        exact: true
      })
      .click();
    await expect(tutor).toContainText(
      "工作记忆容量有限，因此注意力控制会影响理解。"
    );
    await tutor.getByRole("button", { name: "固定当前选区" }).click();
    await expect(tutor).toContainText("3 个来源");
    await tutor.getByRole("button", { name: "固定当前选区" }).click();
    await expect(tutor.locator(".tutor-source-status")).toContainText("已经固定");
    await expect(tutor).toContainText("3 个来源");
    await tutor
      .getByRole("button", { name: "移除 课程/注意力机制.md" })
      .click();
    await expect(tutor).toContainText("2 个来源");

    await page
      .getByLabel("选择其他 Learning source")
      .selectOption("课程/注意力研究.pdf");
    await tutor.getByRole("button", { name: "固定来源" }).click();
    await expect(tutor.locator(".tutor-source-status")).toContainText("已固定");
    await expect(tutor).toContainText("2 个来源");

    await page
      .getByLabel("向当前资料提问")
      .fill("注意力证据帮助理解任务与工作记忆");
    await tutor.getByRole("button", { name: "发送" }).click();
    await expect(tutor.getByText("已完成")).toBeVisible();

    const markdownCitation = tutor.getByRole("button", {
      name: /Source citation 课程\/注意力机制\.md/
    });
    const pdfCitation = tutor.getByRole("button", {
      name: /Source citation 课程\/注意力研究\.pdf/
    });
    await expect(markdownCitation).toBeVisible();
    await expect(pdfCitation).toContainText("第 1 页");

    await tutor.getByRole("button", { name: "查看上下文" }).click();
    const contextDrawer = page.getByRole("region", { name: "上下文" });
    await expect(contextDrawer).toContainText("上下文限额");
    await expect(contextDrawer).toContainText("已省略");

    await markdownCitation.click();
    await expect(page.locator('[aria-current="citation"]')).toContainText(
      "注意力帮助学习者筛选当前任务相关的信息。"
    );

    await pdfCitation.click();
    await expect(page.getByText("第 1 / 1 页", { exact: true })).toBeVisible();
    await expect(page.locator('[aria-current="citation"]')).toContainText(
      "PDF attention evidence."
    );
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
