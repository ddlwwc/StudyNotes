import { expect, test } from "@playwright/test";
import type { Page } from "@playwright/test";
import { spawn, spawnSync, type ChildProcess } from "node:child_process";
import { createHash } from "node:crypto";
import { createServer } from "node:http";
import type { IncomingMessage, ServerResponse } from "node:http";
import {
  access,
  cp,
  copyFile,
  mkdir,
  mkdtemp,
  readFile,
  realpath,
  rm,
  writeFile
} from "node:fs/promises";
import { createServer as createNetServer } from "node:net";
import { tmpdir } from "node:os";
import path from "node:path";
import { gunzipSync, gzipSync } from "node:zlib";

type RunningApp = {
  dataDir: string;
  stop: () => Promise<void>;
  webUrl: string;
};

type MockModel = {
  baseUrl: string;
  close: () => Promise<void>;
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
  const keychainDir = await mkdtemp(path.join(tmpdir(), "studynotes-keychain-"));
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
      STUDY_NOTES_TEST_KEYCHAIN_DIR: keychainDir,
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
    await rm(keychainDir, { recursive: true, force: true });
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
      await rm(keychainDir, { recursive: true, force: true });
    }
  };
}

async function openStudyPage(page: Page, webUrl: string) {
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

  await page.goto(webUrl);
  await page.getByLabel("学习工作区路径").fill(workspaceDir);
  await page.getByRole("button", { name: "打开工作区" }).click();
  return workspaceDir;
}

async function configureData(
  page: Page,
  webUrl: string,
  workspaceDir: string,
  baseUrl = "https://model.example.test/v1"
) {
  const markdownPath = path.join(workspaceDir, "课程", "注意力机制.md");
  const markdown = await readFile(markdownPath, "utf8");
  const revision = createHash("sha256").update(markdown).digest("hex");
  const saveResponse = await page.request.post(`${webUrl}/api/file`, {
    data: {
      path: "课程/注意力机制.md",
      content: markdown,
      blocks: [
        {
          id: "attention-heading",
          type: "heading",
          props: { level: 1 },
          children: []
        },
        {
          id: "attention-block",
          type: "paragraph",
          props: {},
          children: []
        },
        {
          id: "attention-detail",
          type: "paragraph",
          props: {},
          children: []
        }
      ],
      expected_revision: revision
    }
  });
  expect(saveResponse.ok()).toBe(true);

  const modelResponse = await page.request.put(`${webUrl}/api/model-settings`, {
    data: {
      base_url: baseUrl,
      model: "mock-chat",
      api_key: "model-secret-must-not-leak",
      embedding_model: "mock-embedding",
      embedding_enabled: true
    }
  });
  expect(modelResponse.ok()).toBe(true);

  const qiniuResponse = await page.request.put(
    `${webUrl}/api/settings/qiniu`,
    {
      data: {
        bucket: "study-notes-images",
        domain: "https://images.example.test",
        access_key: "qiniu-access-must-not-leak",
        secret_key: "qiniu-secret-must-not-leak"
      }
    }
  );
  expect(qiniuResponse.ok()).toBe(true);

  const sessionResponse = await page.request.post(
    `${webUrl}/api/tutor/sessions`,
    {
      data: {
        path: "课程/注意力机制.md",
        block_id: "attention-block",
        quote: "注意力帮助学习者筛选当前任务相关的信息。"
      }
    }
  );
  if (!sessionResponse.ok()) {
    throw new Error(await sessionResponse.text());
  }
  const session = (await sessionResponse.json()) as { id: string };
  return { sessionId: session.id };
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
      id: "chatcmpl-backup-test",
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
  for (let index = 0; index < content.length; index += 24) {
    response.write(
      `data: ${JSON.stringify({
        choices: [{ delta: { content: content.slice(index, index + 24) } }]
      })}\n\n`
    );
  }
  response.write("data: [DONE]\n\n");
  response.end();
}

async function startMockModel(): Promise<MockModel> {
  const server = createServer(async (request, response) => {
    if (request.method !== "POST" || request.url !== "/v1/chat/completions") {
      response.writeHead(404);
      response.end();
      return;
    }

    const raw = await readRequestBody(request);
    const body = JSON.parse(raw) as Record<string, unknown>;
    const metadata = (body.metadata ?? {}) as Record<string, unknown>;
    if (metadata.study_notes_mode === "practice") {
      sendChatCompletion(
        response,
        JSON.stringify({
          questions: [
            {
              stem: "注意力帮助学习者完成什么？",
              options: [
                "筛选当前任务相关信息",
                "永久保存全部信息",
                "消除工作记忆限制",
                "替代理解过程"
              ],
              correct_index: 0,
              explanation: "资料说明注意力会筛选当前任务相关的信息。",
              citation: {
                source_id: "S1",
                quote: "注意力帮助学习者筛选当前任务相关的信息。"
              }
            }
          ]
        })
      );
      return;
    }
    if (body.stream === true) {
      await sendStreamingCompletion(
        response,
        JSON.stringify({
          type: "grounded",
          answer: "注意力帮助筛选当前任务相关信息。[S1]",
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
      })
  };
}

function createTextLayerPdf(): Buffer {
  const firstPageStream =
    "BT /F1 16 Tf 72 700 Td (PDF attention evidence.) Tj ET";
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

async function seedRestorableData(
  page: Page,
  webUrl: string,
  workspaceDir: string,
  modelBaseUrl: string
) {
  const { sessionId } = await configureData(
    page,
    webUrl,
    workspaceDir,
    modelBaseUrl
  );
  await writeFile(
    path.join(workspaceDir, "课程", "注意力研究.pdf"),
    createTextLayerPdf()
  );
  const citationResponse = await page.request.post(
    `${webUrl}/api/citations`,
    {
      data: {
        path: "课程/注意力研究.pdf",
        page: 1,
        quote: "PDF attention evidence."
      }
    }
  );
  expect(citationResponse.ok()).toBe(true);

  const turnResponse = await page.request.post(
    `${webUrl}/api/tutor/sessions/${sessionId}/turns`,
    {
      data: {
        question: "注意力有什么作用？",
        mode: "guided"
      }
    }
  );
  expect(turnResponse.ok()).toBe(true);
  await turnResponse.text();

  const practiceResponse = await page.request.post(
    `${webUrl}/api/tutor/sessions/${sessionId}/practice`,
    { data: { question_count: 1 } }
  );
  if (!practiceResponse.ok()) {
    throw new Error(await practiceResponse.text());
  }
  const practice = (await practiceResponse.json()) as {
    practice: { questions: Array<{ id: string }> };
  };
  const practiceItemId = practice.practice.questions[0].id;
  const attemptResponse = await page.request.post(
    `${webUrl}/api/tutor/sessions/${sessionId}/practice/attempts`,
    {
      data: {
        practice_item_id: practiceItemId,
        selected_index: 0
      }
    }
  );
  expect(attemptResponse.ok()).toBe(true);

  const gapResponse = await page.request.post(
    `${webUrl}/api/tutor/sessions/${sessionId}/gaps`,
    {
      data: {
        title: "注意力筛选机制",
        practice_item_id: practiceItemId
      }
    }
  );
  expect(gapResponse.ok()).toBe(true);
  const gap = (await gapResponse.json()) as { id: string };
  const reviewResponse = await page.request.post(
    `${webUrl}/api/review/gaps/${gap.id}/results`,
    {
      data: {
        answer: "注意力帮助筛选当前任务相关信息。",
        feedback: "回答抓住资料要点。",
        result: "pass"
      }
    }
  );
  expect(reviewResponse.ok()).toBe(true);
  return { gapId: gap.id, practiceItemId, sessionId };
}

test("Settings exports one backup package without credentials", async ({
  page
}) => {
  const app = await startApp();
  const workspaceDir = await openStudyPage(page, app.webUrl);

  try {
    await configureData(page, app.webUrl, workspaceDir);
    await page.getByRole("button", { name: "设置", exact: true }).click();
    const backupSection = page.getByRole("region", { name: "学习数据备份" });
    await expect(backupSection).toBeVisible();
    await backupSection.getByRole("button", { name: "导出备份" }).click();

    const result = backupSection.locator("[data-backup-path]");
    await expect(result).toContainText("备份已创建");
    const backupPath = await result.getAttribute("data-backup-path");
    expect(backupPath).toBeTruthy();

    const packageBytes = await readFile(backupPath!);
    const packageText = gunzipSync(packageBytes).toString("utf8");
    const payload = JSON.parse(packageText) as {
      data: {
        learningSessions: Array<{ path: string }>;
        practiceItems: unknown[];
        gapRecords: unknown[];
        reviewResults: unknown[];
      };
      format: string;
      schemaVersion: number;
      settings: {
        model: {
          baseUrl: string;
          embeddingEnabled: boolean;
          embeddingModel: string;
          model: string;
        };
        qiniu: { bucket: string; domain: string };
      };
      sidecars: Array<{
        kind: string;
        path: string;
        sourceFileSha256: string;
        sidecarSha256: string | null;
      }>;
      sourceWorkspace: {
        name: string;
        path: string;
      };
    };

    expect(payload.format).toBe("studynotes-backup");
    expect(payload.schemaVersion).toBe(1);
    expect(payload.sourceWorkspace.path).toBeTruthy();
    expect(payload.sourceWorkspace.name).toBe(
      path.basename(workspaceDir)
    );
    expect(payload.settings.model).toMatchObject({
      baseUrl: "https://model.example.test/v1",
      embeddingEnabled: true,
      embeddingModel: "mock-embedding",
      model: "mock-chat"
    });
    expect(payload.settings.qiniu).toEqual({
      bucket: "study-notes-images",
      domain: "https://images.example.test"
    });
    expect(payload.data.learningSessions).toHaveLength(1);
    expect(payload.data.learningSessions[0].path).toBe(
      "课程/注意力机制.md"
    );
    expect(payload.sidecars).toContainEqual(
      expect.objectContaining({
        kind: "markdown",
        path: "课程/注意力机制.md",
        sourceFileSha256: expect.stringMatching(/^[a-f0-9]{64}$/),
        sidecarSha256: expect.stringMatching(/^[a-f0-9]{64}$/)
      })
    );
    expect(packageText).not.toContain("model-secret-must-not-leak");
    expect(packageText).not.toContain("qiniu-access-must-not-leak");
    expect(packageText).not.toContain("qiniu-secret-must-not-leak");
  } finally {
    await app.stop();
    await rm(workspaceDir, { recursive: true, force: true });
  }
});

test("a backup restores the current workspace learning relationships and keeps secrets out", async ({
  page
}) => {
  const sourceApp = await startApp();
  const sourceWorkspace = await openStudyPage(page, sourceApp.webUrl);
  const model = await startMockModel();
  const archiveDir = await mkdtemp(
    path.join(tmpdir(), "studynotes-backup-copy-")
  );
  let sourceStopped = false;
  let targetApp: RunningApp | null = null;
  let targetWorkspace: string | null = null;
  let occupiedWorkspace: string | null = null;

  try {
    const seeded = await seedRestorableData(
      page,
      sourceApp.webUrl,
      sourceWorkspace,
      model.baseUrl
    );
    await page.getByRole("button", { name: "设置", exact: true }).click();
    const sourceBackupSection = page.getByRole("region", {
      name: "学习数据备份"
    });
    await sourceBackupSection
      .getByRole("button", { name: "导出备份" })
      .click();
    const sourceResult = sourceBackupSection.locator("[data-backup-path]");
    await expect(sourceResult).toContainText("备份已创建");
    const sourceBackupPath =
      (await sourceResult.getAttribute("data-backup-path")) ?? "";
    expect(sourceBackupPath).toBeTruthy();

    const backupCopy = path.join(archiveDir, "restore-source.studynotes.gz");
    await copyFile(sourceBackupPath, backupCopy);
    const exported = JSON.parse(
      gunzipSync(await readFile(backupCopy)).toString("utf8")
    ) as {
      data: {
        gapRecords: Array<{ id: string }>;
        practiceAttempts: Array<{ practice_item_id: string }>;
        practiceItems: Array<{ id: string }>;
        reviewResults: Array<{ gap_id: string }>;
        sessionMessages: Array<{ session_id: string }>;
      };
    };
    expect(exported.data.sessionMessages.length).toBeGreaterThanOrEqual(2);
    expect(exported.data.practiceItems).toContainEqual(
      expect.objectContaining({ id: seeded.practiceItemId })
    );
    expect(exported.data.practiceAttempts).toContainEqual(
      expect.objectContaining({ practice_item_id: seeded.practiceItemId })
    );
    expect(exported.data.gapRecords).toContainEqual(
      expect.objectContaining({ id: seeded.gapId })
    );
    expect(exported.data.reviewResults).toContainEqual(
      expect.objectContaining({ gap_id: seeded.gapId })
    );

    targetWorkspace = await mkdtemp(
      path.join(tmpdir(), "studynotes-restore-workspace-")
    );
    await cp(sourceWorkspace, targetWorkspace, { recursive: true });
    await sourceApp.stop();
    sourceStopped = true;

    targetApp = await startApp();
    occupiedWorkspace = await mkdtemp(
      path.join(tmpdir(), "studynotes-occupied-workspace-")
    );
    await mkdir(path.join(occupiedWorkspace, "课程"), { recursive: true });
    await writeFile(
      path.join(occupiedWorkspace, "课程", "占位研究.pdf"),
      createTextLayerPdf()
    );
    const occupiedOpenResponse = await page.request.post(
      `${targetApp.webUrl}/api/workspace`,
      { data: { path: occupiedWorkspace } }
    );
    expect(occupiedOpenResponse.ok()).toBe(true);
    const occupiedSessionResponse = await page.request.post(
      `${targetApp.webUrl}/api/tutor/sessions`,
      {
        data: {
          path: "课程/占位研究.pdf",
          page: 1,
          quote: "PDF attention evidence."
        }
      }
    );
    expect(occupiedSessionResponse.ok()).toBe(true);
    const occupiedSession = (await occupiedSessionResponse.json()) as {
      id: string;
    };
    const backendDirectory = path.resolve(import.meta.dirname, "../../backend");
    const backendPython = path.join(
      backendDirectory,
      ".venv",
      process.platform === "win32" ? "Scripts/python.exe" : "bin/python"
    );
    const occupiedMessage = spawnSync(
      backendPython,
      [
        "-c",
        [
          "from pathlib import Path",
          "import sys",
          "from storage import save_session_message",
          "save_session_message(Path(sys.argv[1]), sys.argv[2], 'user', '占位会话消息')"
        ].join("; "),
        occupiedWorkspace,
        occupiedSession.id
      ],
      {
        cwd: backendDirectory,
        encoding: "utf8",
        env: {
          ...process.env,
          STUDY_NOTES_DATA_DIR: targetApp.dataDir
        }
      }
    );
    expect(
      occupiedMessage.status,
      occupiedMessage.stderr || occupiedMessage.stdout
    ).toBe(0);
    const occupiedCitationResponse = await page.request.post(
      `${targetApp.webUrl}/api/citations`,
      {
        data: {
          path: "课程/占位研究.pdf",
          page: 1,
          quote: "PDF attention evidence."
        }
      }
    );
    expect(occupiedCitationResponse.ok()).toBe(true);
    const targetOpenResponse = await page.request.post(
      `${targetApp.webUrl}/api/workspace`,
      { data: { path: targetWorkspace } }
    );
    expect(targetOpenResponse.ok()).toBe(true);
    await page.goto(targetApp.webUrl);

    const targetSessionResponse = await page.request.post(
      `${targetApp.webUrl}/api/tutor/sessions`,
      {
        data: {
          path: "课程/注意力机制.md",
          block_id: "attention-block",
          quote: "注意力帮助学习者筛选当前任务相关的信息。"
        }
      }
    );
    expect(targetSessionResponse.ok()).toBe(true);

    await page.getByRole("button", { name: "设置", exact: true }).click();
    const targetBackupSection = page.getByRole("region", {
      name: "学习数据备份"
    });
    await targetBackupSection
      .getByLabel("选择备份包")
      .setInputFiles(backupCopy);
    await expect(
      targetBackupSection.getByText("恢复范围")
    ).toBeVisible();
    await expect(
      targetBackupSection.getByText("回滚副本已创建")
    ).toBeVisible();
    const rollbackPath =
      (await targetBackupSection
        .locator("[data-rollback-path]")
        .getAttribute("data-rollback-path")) ?? "";
    expect(rollbackPath).toBeTruthy();
    await expect(access(rollbackPath)).resolves.toBeUndefined();

    await targetBackupSection
      .getByRole("button", { name: "确认恢复" })
      .click();
    await expect(
      targetBackupSection.getByText("恢复完成")
    ).toBeVisible();
    await expect(
      targetBackupSection.getByText(
        "密钥未包含在备份中，请重新配置或读取 Keychain。"
      )
    ).toBeVisible();

    const restoredModelResponse = await page.request.get(
      `${targetApp.webUrl}/api/model-settings`
    );
    expect(restoredModelResponse.ok()).toBe(true);
    expect(await restoredModelResponse.json()).toMatchObject({
      baseUrl: model.baseUrl,
      embeddingEnabled: true,
      embeddingModel: "mock-embedding",
      hasApiKey: false,
      model: "mock-chat"
    });

    const restoredQiniuResponse = await page.request.get(
      `${targetApp.webUrl}/api/settings/qiniu`
    );
    expect(restoredQiniuResponse.ok()).toBe(true);
    expect(await restoredQiniuResponse.json()).toMatchObject({
      bucket: "study-notes-images",
      domain: "https://images.example.test",
      hasAccessKey: false,
      hasSecretKey: false
    });

    const practiceResponse = await page.request.get(
      `${targetApp.webUrl}/api/tutor/sessions/${seeded.sessionId}/practice`
    );
    expect(practiceResponse.ok()).toBe(true);
    const restoredPractice = (await practiceResponse.json()) as {
      attempts: Array<{ correct: boolean; practiceItemId: string }>;
      practice: { questions: Array<{ id: string }> };
    };
    expect(restoredPractice.practice.questions).toContainEqual(
      expect.objectContaining({ id: seeded.practiceItemId })
    );
    expect(restoredPractice.attempts).toContainEqual(
      expect.objectContaining({
        correct: true,
        practiceItemId: seeded.practiceItemId
      })
    );

    const gapResponse = await page.request.get(
      `${targetApp.webUrl}/api/review/gaps/${seeded.gapId}`
    );
    expect(gapResponse.ok()).toBe(true);
    expect(await gapResponse.json()).toMatchObject({
      id: seeded.gapId,
      practiceItem: { id: seeded.practiceItemId },
      reviews: [
        {
          answer: "注意力帮助筛选当前任务相关信息。",
          feedback: "回答抓住资料要点。",
          result: "pass"
        }
      ]
    });

    const citationsResponse = await page.request.get(
      `${targetApp.webUrl}/api/citations?path=${encodeURIComponent(
        "课程/注意力研究.pdf"
      )}`
    );
    expect(citationsResponse.ok()).toBe(true);
    expect(await citationsResponse.json()).toContainEqual(
      expect.objectContaining({
        page: 1,
        path: "课程/注意力研究.pdf",
        quote: "PDF attention evidence."
      })
    );

    const markdownResponse = await page.request.get(
      `${targetApp.webUrl}/api/file?path=${encodeURIComponent(
        "课程/注意力机制.md"
      )}`
    );
    expect(markdownResponse.ok()).toBe(true);
    expect(await markdownResponse.json()).toMatchObject({
      path: "课程/注意力机制.md",
      sidecarStatus: "valid"
    });

    const workspaceResponse = await page.request.get(
      `${targetApp.webUrl}/api/workspace`
    );
    expect(workspaceResponse.ok()).toBe(true);
    const canonicalTargetWorkspace = await realpath(targetWorkspace);
    expect(await workspaceResponse.json()).toMatchObject({
      workspace: {
        name: path.basename(targetWorkspace),
        path: canonicalTargetWorkspace
      }
    });
  } finally {
    await model.close();
    if (!sourceStopped) {
      await sourceApp.stop();
    }
    if (targetApp) {
      await targetApp.stop();
    }
    await rm(sourceWorkspace, { recursive: true, force: true });
    if (targetWorkspace) {
      await rm(targetWorkspace, { recursive: true, force: true });
    }
    if (occupiedWorkspace) {
      await rm(occupiedWorkspace, { recursive: true, force: true });
    }
    await rm(archiveDir, { recursive: true, force: true });
  }
});

test("a corrupt or path-traversing package leaves current data intact and keeps rollback usable", async ({
  page
}) => {
  const app = await startApp();
  const workspaceDir = await openStudyPage(page, app.webUrl);
  const archiveDir = await mkdtemp(
    path.join(tmpdir(), "studynotes-backup-invalid-")
  );

  try {
    const { sessionId } = await configureData(
      page,
      app.webUrl,
      workspaceDir
    );
    await page.getByRole("button", { name: "设置", exact: true }).click();
    const backupSection = page.getByRole("region", { name: "学习数据备份" });
    await backupSection.getByRole("button", { name: "导出备份" }).click();
    const exportResult = backupSection.locator("[data-backup-path]");
    await expect(exportResult).toContainText("备份已创建");
    const sourceBackupPath =
      (await exportResult.getAttribute("data-backup-path")) ?? "";
    const validCopy = path.join(archiveDir, "valid.studynotes.gz");
    await copyFile(sourceBackupPath, validCopy);

    await backupSection.getByLabel("选择备份包").setInputFiles(validCopy);
    await expect(backupSection.getByText("恢复范围")).toBeVisible();
    const rollbackPath =
      (await backupSection
        .locator("[data-rollback-path]")
        .getAttribute("data-rollback-path")) ?? "";
    expect(rollbackPath).toBeTruthy();
    await backupSection.getByRole("button", { name: "取消" }).click();

    const corruptPath = path.join(archiveDir, "corrupt.studynotes.gz");
    await writeFile(corruptPath, Buffer.from("not-a-gzip-package"));
    await backupSection.getByLabel("选择备份包").setInputFiles(corruptPath);
    await expect(backupSection.getByRole("alert")).toContainText(
      "备份包损坏"
    );

    const afterCorrupt = await page.request.get(
      `${app.webUrl}/api/tutor/sessions/${sessionId}/practice`
    );
    expect(afterCorrupt.ok()).toBe(true);

    const malicious = JSON.parse(
      gunzipSync(await readFile(validCopy)).toString("utf8")
    ) as {
      data: {
        learningSessions: Array<{ path: string }>;
      };
    };
    malicious.data.learningSessions[0].path = "../outside-workspace.md";
    const maliciousPath = path.join(
      archiveDir,
      "path-traversal.studynotes.gz"
    );
    await writeFile(
      maliciousPath,
      gzipSync(JSON.stringify(malicious))
    );
    await backupSection.getByLabel("选择备份包").setInputFiles(maliciousPath);
    await expect(backupSection.getByRole("alert")).toContainText(
      "安全的相对路径"
    );

    const afterTraversal = await page.request.get(
      `${app.webUrl}/api/tutor/sessions/${sessionId}/practice`
    );
    expect(afterTraversal.ok()).toBe(true);

    await backupSection.getByLabel("选择备份包").setInputFiles(rollbackPath);
    await expect(backupSection.getByText("恢复范围")).toBeVisible();
    await expect(backupSection.getByText("可以恢复")).toBeVisible();
    await backupSection.getByRole("button", { name: "确认恢复" }).click();
    await expect(backupSection.getByText("恢复完成")).toBeVisible();

    const afterRollback = await page.request.get(
      `${app.webUrl}/api/tutor/sessions/${sessionId}/practice`
    );
    expect(afterRollback.ok()).toBe(true);
  } finally {
    await app.stop();
    await rm(workspaceDir, { recursive: true, force: true });
    await rm(archiveDir, { recursive: true, force: true });
  }
});

test("a failed restore transaction rolls back to the current learning data", async ({
  page
}) => {
  const app = await startApp();
  const model = await startMockModel();
  const workspaceDir = await openStudyPage(page, app.webUrl);
  const archiveDir = await mkdtemp(
    path.join(tmpdir(), "studynotes-backup-rollback-")
  );

  try {
    const seeded = await seedRestorableData(
      page,
      app.webUrl,
      workspaceDir,
      model.baseUrl
    );
    await page.getByRole("button", { name: "设置", exact: true }).click();
    const backupSection = page.getByRole("region", { name: "学习数据备份" });
    await backupSection.getByRole("button", { name: "导出备份" }).click();
    const exportResult = backupSection.locator("[data-backup-path]");
    await expect(exportResult).toContainText("备份已创建");
    const exportedPath =
      (await exportResult.getAttribute("data-backup-path")) ?? "";

    const tampered = JSON.parse(
      gunzipSync(await readFile(exportedPath)).toString("utf8")
    ) as {
      data: {
        practiceSets: Array<{ session_id: string }>;
        reviewResults: Array<{ result: string }>;
      };
    };
    const relationalTamper = structuredClone(tampered);
    relationalTamper.data.practiceSets[0].session_id = "missing-session";
    const relationalTamperPath = path.join(
      archiveDir,
      "relationship-failure.studynotes.gz"
    );
    await writeFile(
      relationalTamperPath,
      gzipSync(JSON.stringify(relationalTamper))
    );
    await backupSection
      .getByLabel("选择备份包")
      .setInputFiles(relationalTamperPath);
    await expect(backupSection.getByRole("alert")).toContainText(
      "备份包练习集合会话关系无效。"
    );

    tampered.data.reviewResults[0].result = "invalid-transaction-value";
    const tamperedPath = path.join(
      archiveDir,
      "transaction-failure.studynotes.gz"
    );
    await writeFile(tamperedPath, gzipSync(JSON.stringify(tampered)));

    await backupSection.getByLabel("选择备份包").setInputFiles(tamperedPath);
    await expect(backupSection.getByText("恢复范围")).toBeVisible();
    const rollbackPath =
      (await backupSection
        .locator("[data-rollback-path]")
        .getAttribute("data-rollback-path")) ?? "";
    expect(rollbackPath).toBeTruthy();

    await backupSection.getByRole("button", { name: "确认恢复" }).click();
    await expect(backupSection.getByRole("alert")).toContainText(
      "恢复失败，当前学习数据已保持不变。"
    );

    const currentGapResponse = await page.request.get(
      `${app.webUrl}/api/review/gaps/${seeded.gapId}`
    );
    expect(currentGapResponse.ok()).toBe(true);
    expect(await currentGapResponse.json()).toMatchObject({
      id: seeded.gapId,
      reviews: [
        {
          answer: "注意力帮助筛选当前任务相关信息。",
          result: "pass"
        }
      ]
    });

    await backupSection.getByLabel("选择备份包").setInputFiles(rollbackPath);
    await expect(backupSection.getByText("恢复范围")).toBeVisible();
    await expect(backupSection.getByText("可以恢复")).toBeVisible();
  } finally {
    await model.close();
    await app.stop();
    await rm(workspaceDir, { recursive: true, force: true });
    await rm(archiveDir, { recursive: true, force: true });
  }
});
