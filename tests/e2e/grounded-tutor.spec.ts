import { expect, test } from "@playwright/test";
import type { Page } from "@playwright/test";
import { spawn, type ChildProcess } from "node:child_process";
import { createServer } from "node:http";
import type { IncomingMessage, ServerResponse } from "node:http";
import {
  mkdir,
  mkdtemp,
  readdir,
  readFile,
  rename,
  rm,
  symlink,
  writeFile
} from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { gunzipSync } from "node:zlib";

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
    quote: string;
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

async function startApp(
  options: { dataDir?: string } = {}
): Promise<RunningApp & { dataDir: string }> {
  const dataDir =
    options.dataDir ?? (await mkdtemp(path.join(tmpdir(), "studynotes-data-")));
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
    if (options.dataDir === undefined) {
      await rm(dataDir, { recursive: true, force: true });
    }
    throw error;
  }

  return {
    dataDir,
    webUrl,
    stop: async () => {
      if (child.exitCode !== null) {
        if (options.dataDir === undefined) {
          await rm(dataDir, { recursive: true, force: true });
        }
        return;
      }
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
      if (options.dataDir === undefined) {
        await rm(dataDir, { recursive: true, force: true });
      }
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
    message.content?.startsWith("学习资料 上下文：")
  )?.content;
  if (!contextMessage) {
    throw new Error("Tutor context was not sent to the model.");
  }
  const prefix = "学习资料 上下文：\n";
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
  await page.getByRole("button", { name: "设置", exact: true }).click();
  await page.getByLabel("资料发送边界确认").check();
  await page.getByLabel("Base URL").fill(baseUrl);
  await page.getByLabel("API Key").fill("test-key");
  await page.getByLabel("聊天模型").fill("mock-model");
  if (embeddingModel) {
    await page.getByLabel("向量模型").fill(embeddingModel);
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
  await page.getByLabel("学习工作区路径").fill(workspaceDir);
  await page.getByRole("button", { name: "打开工作区" }).click();
  await configureModel(page, baseUrl, embeddingModel);
  await page
    .getByRole("button", { name: "注意力机制.md", exact: true })
    .click();
  await page
    .getByText("注意力帮助学习者筛选当前任务相关的信息。", { exact: true })
    .click();
  const tutor = page.getByRole("complementary", { name: "资料型私教" });
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
      .getByLabel("学习工作区路径")
      .fill(workspaceDir);
    await page.getByRole("button", { name: "打开工作区" }).click();
    await page.getByRole("button", { name: "设置", exact: true }).click();
    await page.getByLabel("资料发送边界确认").check();

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
      .getByLabel("学习工作区路径")
      .fill(workspaceDir);
    await page.getByRole("button", { name: "打开工作区" }).click();
    await page.getByRole("button", { name: "设置", exact: true }).click();
    await page.getByLabel("资料发送边界确认").check();
    await page.getByLabel("Base URL").fill(model.baseUrl);
    await page.getByLabel("API Key").fill("test-key");
    await page.getByLabel("聊天模型").fill("mock-model");
    await page.getByLabel("向量模型").fill("mock-embedding");
    await page.getByLabel("启用语义检索").check();
    await page.getByRole("button", { name: "测试向量模型" }).click();

    await expect(page.getByText("向量模型连接成功")).toBeVisible();
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

    await page.getByRole("button", { name: "设置", exact: true }).click();
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
    const tutor = page.getByRole("complementary", { name: "资料型私教" });
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

test("semantic retrieval finds a lexically different passage with a 资料引用", async ({
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
      name: /资料引用.*工作记忆容量有限/
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
      name: /资料引用.*工作记忆容量有限/
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
    await page.getByLabel("学习工作区路径").fill(workspaceDir);
    await page.getByRole("button", { name: "打开工作区" }).click();
    await configureModel(page, model.baseUrl);
    await page
      .getByRole("button", { name: "注意力机制.md", exact: true })
      .click();
    await page
      .getByText("注意力帮助学习者筛选当前任务相关的信息。", { exact: true })
      .click();

    const tutor = page.getByRole("complementary", { name: "资料型私教" });
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
      name: /资料引用/
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
    await page.getByLabel("学习工作区路径").fill(workspaceDir);
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

    const tutor = page.getByRole("complementary", { name: "资料型私教" });
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

test("switching Markdown blocks in the same page starts a new anchored 学习会话", async ({
  page
}) => {
  const app = await startApp();
  const sentContexts: TutorSentContext[] = [];
  const model = await startMockModel(async (body, _requestIndex, response) => {
    sentContexts.push(parseTutorContext(body));
    await sendStreamingCompletion(
      response,
      JSON.stringify({
        type: "grounded",
        answer: "资料支持这个结论。[S1]",
        citations: [
          {
            source_id: "S1",
            quote:
              sentContexts.length === 1
                ? "注意力帮助学习者筛选当前任务相关的信息。"
                : "工作记忆容量有限，因此注意力控制会影响理解。"
          }
        ],
        missing: []
      })
    );
  });
  const workspaceDir = await openStudyPage(page);

  try {
    await page.goto(app.webUrl);
    await page.getByLabel("学习工作区路径").fill(workspaceDir);
    await page.getByRole("button", { name: "打开工作区" }).click();
    await configureModel(page, model.baseUrl);
    await page
      .getByRole("button", { name: "注意力机制.md", exact: true })
      .click();

    const firstBlock = page.getByText(
      "注意力帮助学习者筛选当前任务相关的信息。",
      { exact: true }
    );
    const secondBlock = page.getByText(
      "工作记忆容量有限，因此注意力控制会影响理解。",
      { exact: true }
    );
    const tutor = page.getByRole("complementary", { name: "资料型私教" });

    await firstBlock.click();
    await page.getByLabel("向当前资料提问").fill("第一个锚点说明了什么？");
    await tutor.getByRole("button", { name: "发送" }).click();
    await expect(tutor.getByText("已完成")).toBeVisible();

    await secondBlock.click();
    await expect(tutor).toContainText(
      "工作记忆容量有限，因此注意力控制会影响理解。"
    );
    await page.getByLabel("向当前资料提问").fill("第二个锚点说明了什么？");
    await tutor.getByRole("button", { name: "发送" }).click();
    await expect(tutor.getByText("已完成")).toBeVisible();

    expect(sentContexts).toHaveLength(2);
    expect(sentContexts[1].chunks[0].text).toContain(
      "工作记忆容量有限，因此注意力控制会影响理解。"
    );

    const sessions = await page.evaluate(async () => {
      const response = await fetch("/api/tutor/sessions");
      return {
        body: await response.json(),
        ok: response.ok
      };
    });
    expect(sessions.ok).toBe(true);
    expect(
      (sessions.body as { sessions: Array<{ quote: string }> }).sessions
    ).toHaveLength(2);
    expect(
      (sessions.body as { sessions: Array<{ quote: string }> }).sessions.map(
        (session) => session.quote
      )
    ).toEqual([
      expect.stringContaining("注意力帮助学习者筛选"),
      expect.stringContaining("工作记忆容量有限")
    ]);
  } finally {
    await model.close();
    await app.stop();
    await rm(workspaceDir, { recursive: true, force: true });
  }
});

test("a PDF selection can start a grounded 学习会话 directly", async ({
  page
}) => {
  const app = await startApp();
  const model = await startMockModel(async (body, _requestIndex, response) => {
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
    await page.getByLabel("学习工作区路径").fill(workspaceDir);
    await page.getByRole("button", { name: "打开工作区" }).click();
    await configureModel(page, model.baseUrl);
    await page
      .getByRole("button", { name: "注意力研究.pdf", exact: true })
      .click();

    await expect(page.getByText("第 1 / 1 页", { exact: true })).toBeVisible();
    await selectPdfText(page, "PDF attention evidence.");
    await page.getByRole("button", { name: "用此片段发起提问" }).click();

    const tutor = page.getByRole("complementary", { name: "资料型私教" });
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

test("a 学习会话 answers across pinned Markdown and PDF sources with exact citation jumps", async ({
  page
}) => {
  const app = await startApp();
  const model = await startMockModel(async (body, _requestIndex, response) => {
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
            quote: markdownChunk.quote
          },
          {
            source_id: pdfChunk.sourceId,
            quote: pdfChunk.quote
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
      .getByLabel("选择其他 学习资料")
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
      .getByLabel("选择其他 学习资料")
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
    await expect(tutor).toContainText("0 个来源");
    await page
      .getByLabel("选择其他 学习资料")
      .selectOption("课程/注意力研究.pdf");
    await tutor.getByRole("button", { name: "固定来源" }).click();
    await expect(tutor).toContainText("2 个来源");
    await page
      .getByLabel("选择其他 学习资料")
      .selectOption("补充/证据-1.md");
    await tutor.getByRole("button", { name: "固定来源" }).click();
    await expect(tutor).toContainText("3 个来源");
    await tutor
      .getByRole("button", { name: "移除 补充/证据-1.md" })
      .click();
    await expect(tutor).toContainText("2 个来源");

    await page
      .getByLabel("选择其他 学习资料")
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
      name: /资料引用 课程\/注意力机制\.md/
    });
    const pdfCitation = tutor.getByRole("button", {
      name: /资料引用 课程\/注意力研究\.pdf/
    });
    await expect(markdownCitation).toBeVisible();
    await expect(pdfCitation).toContainText("第 1 页");

    await tutor.getByRole("button", { name: "查看上下文" }).click();
    const contextDrawer = page.getByRole("region", { name: "上下文" });
    await expect(contextDrawer).toContainText("上下文限额");
    await expect(contextDrawer).toContainText("已省略");

    await markdownCitation.click();
    await expect(page.locator('[aria-current="citation"]')).toContainText(
      "工作记忆容量有限"
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

test("an invalid 资料引用 is retried before a grounded answer is shown", async ({
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

test("a grounded answer missing a conclusion citation is retried and then degrades", async ({
  page
}) => {
  const app = await startApp();
  const model = await startMockModel(async (_body, requestIndex, response) => {
    const answer = `第 ${requestIndex + 1} 次回答的第一项结论有引用。[S1] 第二项结论没有引用。`;
    await sendStreamingCompletion(
      response,
      JSON.stringify({
        type: "grounded",
        answer,
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
    await page.getByLabel("向当前资料提问").fill("请分别说明两项结论。");
    await tutor.getByRole("button", { name: "发送" }).click();

    await expect(tutor.getByText("已完成")).toBeVisible();
    await expect(tutor.getByText("证据不足")).toBeVisible();
    await expect(
      tutor.getByText("当前资料不足以形成可验证的回答，模型也未能返回有效引用。")
    ).toBeVisible();
    await expect(tutor.getByText("第二项结论没有引用。")).toHaveCount(0);
    expect(
      model.requests.filter((request) => request.body.stream === true)
    ).toHaveLength(2);
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
    await expect(tutor.getByText("非资料补充")).toHaveCount(0);

    await tutor.getByRole("button", { name: "请求模型补充" }).click();
    await expect(tutor.getByText("非资料补充")).toBeVisible();
    await expect(tutor.getByText("不来自学习资料")).toBeVisible();
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

test("stopping a stream closes the upstream model response and does not persist an unfinished answer", async ({
  page
}) => {
  const app = await startApp();
  let upstreamClosedAfterStop = false;
  const model = await startMockModel(async (_body, _requestIndex, response) => {
    let finished = false;
    response.on("close", () => {
      upstreamClosedAfterStop = !finished;
    });
    response.writeHead(200, {
      "Cache-Control": "no-store",
      "Content-Type": "text/event-stream"
    });
    const payload = JSON.stringify({
      type: "grounded",
      answer: "这是一段很长的真实流式回答。[S1]",
      citations: [
        {
          source_id: "S1",
          quote: "注意力帮助学习者筛选当前任务相关的信息。"
        }
      ],
      missing: []
    });
    for (let index = 0; index < payload.length; index += 4) {
      if (response.destroyed) {
        return;
      }
      response.write(
        `data: ${JSON.stringify({
          choices: [{ delta: { content: payload.slice(index, index + 4) } }]
        })}\n\n`
      );
      await new Promise((resolve) => setTimeout(resolve, 45));
    }
    finished = true;
    response.end("data: [DONE]\n\n");
  });
  const workspaceDir = await openStudyPage(page);

  try {
    const tutor = await prepareTutor(
      page,
      app.webUrl,
      workspaceDir,
      model.baseUrl
    );
    await page.getByLabel("向当前资料提问").fill("请慢慢解释。");
    await tutor.getByRole("button", { name: "发送" }).click();
    await expect(tutor.getByText(/已接收 \d+ 字/)).toBeVisible({
      timeout: 5_000
    });
    await tutor.getByRole("button", { name: "停止" }).click();
    await expect(tutor.getByText("已停止")).toBeVisible();

    await expect
      .poll(() => upstreamClosedAfterStop, { timeout: 3_000 })
      .toBe(true);

    const sessionMessages = await page.evaluate(async () => {
      const sessionsResponse = await fetch("/api/tutor/sessions");
      const sessions = (await sessionsResponse.json()) as {
        sessions: Array<{ id: string }>;
      };
      const sessionId = sessions.sessions.at(-1)?.id ?? "";
      const response = await fetch(`/api/tutor/sessions/${sessionId}`);
      return {
        body: await response.json(),
        ok: response.ok
      };
    });
    expect(sessionMessages.ok).toBe(true);
    expect(
      (
        sessionMessages.body as {
          messages: Array<{ role: string; content: string }>;
        }
      ).messages.map((message) => message.role)
    ).toEqual(["user"]);
  } finally {
    await model.close();
    await app.stop();
    await rm(workspaceDir, { recursive: true, force: true });
  }
});

test("moving a page and its directory keeps session and Gap citation paths usable", async ({
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
    await page.getByLabel("向当前资料提问").fill("移动后还能打开吗？");
    await tutor.getByRole("button", { name: "发送" }).click();
    await expect(tutor.getByText("已完成")).toBeVisible();

    const sessionId = await page.evaluate(async () => {
      const response = await fetch("/api/tutor/sessions");
      const payload = (await response.json()) as {
        sessions: Array<{ id: string }>;
      };
      return payload.sessions[0].id;
    });
    await page.evaluate(async (activeSessionId) => {
      const response = await fetch(
        `/api/tutor/sessions/${activeSessionId}/gaps`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ title: "移动后仍需保存的缺口" })
        }
      );
      if (!response.ok) {
        throw new Error(await response.text());
      }
    }, sessionId);

    await mkdir(path.join(workspaceDir, "归档"), { recursive: true });
    for (const [oldPath, newPath] of [
      ["课程/注意力机制.md", "归档/注意力机制.md"],
      ["归档", "课程归档"]
    ]) {
      const moved = await page.evaluate(
        async ({ oldPathValue, newPathValue }) => {
          const response = await fetch("/api/entries", {
            method: "PATCH",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              path: oldPathValue,
              new_path: newPathValue
            })
          });
          return {
            body: await response.json(),
            ok: response.ok
          };
        },
        { oldPathValue: oldPath, newPathValue: newPath }
      );
      expect(moved.ok).toBe(true);
    }

    const remapped = await page.evaluate(async (activeSessionId) => {
      const [sessionsResponse, detailResponse, reviewResponse] =
        await Promise.all([
          fetch("/api/tutor/sessions"),
          fetch(`/api/tutor/sessions/${activeSessionId}`),
          fetch("/api/review")
        ]);
      return {
        detail: await detailResponse.json(),
        review: await reviewResponse.json(),
        sessions: await sessionsResponse.json()
      };
    }, sessionId);

    expect(
      (remapped.sessions as { sessions: Array<{ path: string }> }).sessions[0]
        .path
    ).toBe("课程归档/注意力机制.md");
    expect(
      (remapped.detail as { sources: Array<{ path: string }> }).sources[0].path
    ).toBe("课程归档/注意力机制.md");
    expect(
      (remapped.review as { records: Array<{ citation: { path: string } }> })
        .records[0].citation.path
    ).toBe("课程归档/注意力机制.md");

    await page.getByRole("button", { name: "复习" }).click();
    await page
      .getByRole("button", {
        name: /资料引用 课程归档\/注意力机制\.md/
      })
      .click();
    await expect(
      page.getByRole("article").getByText("课程归档/注意力机制.md", {
        exact: true
      })
    )
      .toBeVisible();
  } finally {
    await model.close();
    await app.stop();
    await rm(workspaceDir, { recursive: true, force: true });
  }
});

test("relocating a workspace migrates its sessions, citations and Gap records", async ({
  page
}) => {
  const dataDir = await mkdtemp(path.join(tmpdir(), "studynotes-data-"));
  const originalWorkspace = await openStudyPage(page);
  const relocatedWorkspace = `${originalWorkspace}-relocated`;
  const app = await startApp({ dataDir });
  const model = await startMockModel();

  try {
    const tutor = await prepareTutor(
      page,
      app.webUrl,
      originalWorkspace,
      model.baseUrl
    );
    await page.getByLabel("向当前资料提问").fill("重定位后仍保留记录吗？");
    await tutor.getByRole("button", { name: "发送" }).click();
    await expect(tutor.getByText("已完成")).toBeVisible();

    const sessionId = await page.evaluate(async () => {
      const response = await fetch("/api/tutor/sessions");
      const payload = (await response.json()) as {
        sessions: Array<{ id: string }>;
      };
      return payload.sessions[0].id;
    });
    await page.evaluate(async (activeSessionId) => {
      const response = await fetch(
        `/api/tutor/sessions/${activeSessionId}/gaps`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ title: "重定位后的缺口" })
        }
      );
      if (!response.ok) {
        throw new Error(await response.text());
      }
    }, sessionId);
    await app.stop();
    await rename(originalWorkspace, relocatedWorkspace);

    const restarted = await startApp({ dataDir });
    try {
      await page.goto(restarted.webUrl);
      await expect(
        page.getByRole("heading", { name: "学习工作区需要重新定位" })
      ).toBeVisible();
      await page
        .getByLabel("新的学习工作区路径")
        .fill(relocatedWorkspace);
      await page.getByRole("button", { name: "重新定位工作区" }).click();

      const migrated = await page.evaluate(async (activeSessionId) => {
        const [sessionsResponse, detailResponse, reviewResponse] =
          await Promise.all([
            fetch("/api/tutor/sessions"),
            fetch(`/api/tutor/sessions/${activeSessionId}`),
            fetch("/api/review")
          ]);
        return {
          detail: await detailResponse.json(),
          review: await reviewResponse.json(),
          sessions: await sessionsResponse.json()
        };
      }, sessionId);
      expect(
        (migrated.sessions as { sessions: Array<{ path: string }> }).sessions[0]
          .path
      ).toBe("课程/注意力机制.md");
      expect(
        (migrated.detail as { sources: Array<{ path: string }> }).sources[0]
          .path
      ).toBe("课程/注意力机制.md");
      expect(
        (migrated.review as { records: Array<{ citation: { path: string } }> })
          .records[0].citation.path
      ).toBe("课程/注意力机制.md");
    } finally {
      await restarted.stop();
    }
  } finally {
    await model.close();
    await app.stop();
    await rm(dataDir, { recursive: true, force: true });
    await rm(originalWorkspace, { recursive: true, force: true });
    await rm(relocatedWorkspace, { recursive: true, force: true });
  }
});

test("a workspace symlink cannot expose an external Markdown file to search, model context, or backup", async ({
  page
}) => {
  const app = await startApp();
  const model = await startMockModel();
  const workspaceDir = await openStudyPage(page);
  const externalDirectory = await mkdtemp(
    path.join(tmpdir(), "studynotes-external-")
  );
  const secretMarker = "外部机密-7f3c9b";
  await writeFile(
    path.join(externalDirectory, "secret.md"),
    `# 外部机密\n\n${secretMarker}`,
    "utf8"
  );
  await symlink(
    path.join(externalDirectory, "secret.md"),
    path.join(workspaceDir, "课程", "外部链接.md")
  );

  try {
    const tutor = await prepareTutor(
      page,
      app.webUrl,
      workspaceDir,
      model.baseUrl
    );
    await page.getByLabel("向当前资料提问").fill("外部机密的独特内容是什么？");
    await tutor.getByRole("button", { name: "发送" }).click();
    await expect(tutor.getByText("已完成")).toBeVisible();

    expect(JSON.stringify(model.requests)).not.toContain(secretMarker);
    const searchResults = await page.evaluate(async (marker) => {
      const response = await fetch(`/api/search?q=${encodeURIComponent(marker)}`);
      return response.json();
    }, secretMarker);
    expect(
      (searchResults as { results: Array<{ path: string }> }).results
    ).toEqual([]);
    await expect(
      page.getByRole("button", { name: "外部链接.md", exact: true })
    ).toHaveCount(0);

    const backupResponse = await page.request.post(
      `${app.webUrl}/api/backups/export`
    );
    expect(backupResponse.ok()).toBe(true);
    const backupResult = (await backupResponse.json()) as { path: string };
    const backupPayload = gunzipSync(
      await readFile(backupResult.path)
    ).toString("utf8");
    expect(backupPayload).not.toContain(secretMarker);
    expect(backupPayload).not.toContain("外部链接.md");
  } finally {
    await model.close();
    await app.stop();
    await rm(workspaceDir, { recursive: true, force: true });
    await rm(externalDirectory, { recursive: true, force: true });
  }
});

test("a Markdown notebook supports text sources, tags, templates, daily notes, and backlinks", async ({
  page
}) => {
  const app = await startApp();
  const model = await startMockModel(async (_body, _requestIndex, response) => {
    await sendStreamingCompletion(
      response,
      JSON.stringify({
        type: "grounded",
        answer: "纯文本资料也给出了可验证结论。[S1]",
        citations: [
          {
            source_id: "S1",
            quote: "纯文本资料保留课程摘要。"
          }
        ],
        missing: []
      })
    );
  });
  const workspaceDir = await openStudyPage(page);
  await mkdir(path.join(workspaceDir, ".templates"), { recursive: true });
  await mkdir(path.join(workspaceDir, "笔记"), { recursive: true });
  await writeFile(
    path.join(workspaceDir, ".templates", "概念.md"),
    "# 概念模板\n\n模板正文 #学习\n",
    "utf8"
  );
  await writeFile(
    path.join(workspaceDir, "课程", "课程摘要.txt"),
    "纯文本资料保留课程摘要。\n第二行用于只读阅读。\n",
    "utf8"
  );
  await writeFile(
    path.join(workspaceDir, "笔记", "目标.md"),
    [
      "---",
      "tags: [学习]",
      "---",
      "# 目标页面",
      "",
      "这是被其他页面链接的目标。"
    ].join("\n"),
    "utf8"
  );
  await writeFile(
    path.join(workspaceDir, "笔记", "来源.md"),
    [
      "# 来源页面",
      "",
      "标准链接指向[目标](目标.md)。",
      "",
      "Wiki 链接指向 [[目标]]。"
    ].join("\n"),
    "utf8"
  );

  try {
    await page.goto(app.webUrl);
    await page.getByLabel("学习工作区路径").fill(workspaceDir);
    await page.getByRole("button", { name: "打开工作区" }).click();
    await configureModel(page, model.baseUrl);

    await expect(page.getByRole("button", { name: "学习", exact: true }))
      .toBeVisible();
    await page.getByRole("button", { name: "学习", exact: true }).click();
    await expect(
      page.getByRole("button", { name: "目标.md", exact: true })
    ).toBeVisible();
    await expect(
      page.getByRole("button", { name: "来源.md", exact: true })
    ).toHaveCount(0);
    await page.getByRole("button", { name: "目标.md", exact: true }).click();

    await page.getByRole("button", { name: "反向链接" }).click();
    await expect(page.getByRole("region", { name: "反向链接" })).toContainText(
      "笔记/来源.md"
    );
    await expect(page.getByRole("region", { name: "反向链接" })).toContainText(
      "Wiki 链接"
    );
    await page.getByRole("button", { name: "清除" }).click();

    await page.getByRole("button", { name: "新建页面" }).click();
    await page.getByLabel("页面模板").selectOption(".templates/概念.md");
    await page.getByLabel("页面名称").fill("模板页面");
    await page.getByRole("button", { name: "创建页面" }).click();
    await expect(
      page.getByRole("dialog", { name: "新建 Markdown 页面" })
    ).toBeHidden();
    expect(
      await readFile(path.join(workspaceDir, "笔记", "模板页面.md"), "utf8")
    ).toContain("模板正文");

    await page.getByRole("button", { name: "今日笔记" }).click();
    await expect(page.getByText("今日笔记已创建")).toBeVisible();
    const dailyFiles = (await readdir(path.join(workspaceDir, "Daily"))).filter(
      (name) => name.endsWith(".md")
    );
    expect(dailyFiles).toHaveLength(1);

    await page
      .getByRole("button", { name: "课程摘要.txt", exact: true })
      .click();
    await expect(page.getByText("纯文本资料为只读")).toBeVisible();
    await page.getByText("纯文本资料保留课程摘要。", { exact: true }).click();
    const tutor = page.getByRole("complementary", { name: "资料型私教" });
    await expect(tutor).toContainText("已绑定纯文本位置");
    await page.getByLabel("向当前资料提问").fill("这段摘要说明了什么？");
    await tutor.getByRole("button", { name: "发送" }).click();
    await expect(tutor.getByText("已完成")).toBeVisible();
    await expect(
      tutor.getByRole("button", {
        name: /资料引用 课程\/课程摘要\.txt/
      })
    ).toBeVisible();
  } finally {
    await model.close();
    await app.stop();
    await rm(workspaceDir, { recursive: true, force: true });
  }
});

test("multiple workspaces can be registered, renamed, switched, and removed without deleting files", async ({
  page
}) => {
  const app = await startApp();
  const firstWorkspace = await openStudyPage(page);
  const secondWorkspace = await openStudyPage(page);

  try {
    await page.goto(app.webUrl);
    await page.getByLabel("学习工作区路径").fill(firstWorkspace);
    await page.getByRole("button", { name: "打开工作区" }).click();
    await page.getByRole("button", { name: "设置", exact: true }).click();
    await expect(page.getByRole("heading", { name: "工作区" })).toBeVisible();

    await page.getByLabel("添加本地工作区").fill(secondWorkspace);
    await page.getByRole("button", { name: "添加并切换" }).click();
    await expect(page.getByText("工作区已切换")).toBeVisible();

    const firstRow = page.locator(".workspace-management-row").filter({
      hasText: firstWorkspace
    });
    await firstRow.getByRole("textbox").fill("第一学习区");
    await firstRow.getByRole("button", { name: "保存名称" }).click();
    await expect(page.getByText("工作区名称已保存")).toBeVisible();
    await firstRow.getByRole("button", { name: "切换" }).click();
    await expect(page.getByText("工作区已切换")).toBeVisible();

    await firstRow.getByRole("button", { name: "移除注册" }).click();
    await expect(
      page.getByText("已移除注册记录，磁盘文件未删除")
    ).toBeVisible();
    expect(
      await readFile(
        path.join(firstWorkspace, "课程", "注意力机制.md"),
        "utf8"
      )
    ).toContain("注意力帮助学习者");

    const workspaces = await page.evaluate(async () => {
      const response = await fetch("/api/workspaces");
      return response.json();
    });
    const workspacePaths = (
      workspaces as { workspaces: Array<{ path: string }> }
    ).workspaces.map((item) => item.path);
    expect(workspacePaths).toHaveLength(1);
    expect(path.basename(workspacePaths[0])).toBe(path.basename(secondWorkspace));
  } finally {
    await app.stop();
    await rm(firstWorkspace, { recursive: true, force: true });
    await rm(secondWorkspace, { recursive: true, force: true });
  }
});
