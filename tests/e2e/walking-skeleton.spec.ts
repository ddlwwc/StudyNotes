import { expect, test } from "@playwright/test";
import type { Page } from "@playwright/test";
import { spawn, type ChildProcess } from "node:child_process";
import {
  mkdir,
  mkdtemp,
  readFile,
  realpath,
  rename,
  rm,
  stat,
  writeFile
} from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { _electron as electron } from "playwright";

type RunningApp = {
  webUrl: string;
  dataDir: string;
  stop: () => Promise<void>;
};

type StartAppOptions = {
  dataDir?: string;
};

function createTextLayerPdf(
  secondPageText: string = "Second page evidence."
): Buffer {
  const firstPageStream =
    "BT /F1 20 Tf 72 700 Td (Attention controls working memory.) Tj " +
    "0 -28 Td (Select this sentence as evidence.) Tj ET";
  const secondPageStream = `BT /F1 20 Tf 72 700 Td (${secondPageText}) Tj ET`;
  const objects = [
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Kids [3 0 R 4 0 R 5 0 R] /Count 3 >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 6 0 R >> >> /Contents 7 0 R >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 6 0 R >> >> /Contents 8 0 R >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << >> >>",
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    `<< /Length ${Buffer.byteLength(firstPageStream, "ascii")} >>\nstream\n${firstPageStream}\nendstream`,
    `<< /Length ${Buffer.byteLength(secondPageStream, "ascii")} >>\nstream\n${secondPageStream}\nendstream`
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

function reservePort(): number {
  return 35_000 + Math.floor(Math.random() * 10_000);
}

async function selectPdfEvidence(page: Page) {
  const evidenceLine = page
    .getByLabel("PDF 文本层")
    .getByText("Attention controls working memory.", { exact: true });
  await expect(evidenceLine).toBeVisible();

  let evidenceBounds: Awaited<ReturnType<typeof evidenceLine.boundingBox>> = null;
  await expect
    .poll(async () => {
      evidenceBounds = await evidenceLine.boundingBox().catch(() => null);
      return evidenceBounds?.width ?? 0;
    })
    .toBeGreaterThan(20);

  await page.mouse.move(
    evidenceBounds!.x + 1,
    evidenceBounds!.y + evidenceBounds!.height / 2
  );
  await page.mouse.down();
  await page.mouse.move(
    evidenceBounds!.x + evidenceBounds!.width - 1,
    evidenceBounds!.y + evidenceBounds!.height / 2,
    { steps: 12 }
  );
  await page.mouse.up();
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

async function startApp(options: StartAppOptions = {}): Promise<RunningApp> {
  const dataDir =
    options.dataDir ?? (await mkdtemp(path.join(tmpdir(), "studynotes-data-")));
  const ownsDataDir = options.dataDir === undefined;
  const backendPort = reservePort();
  const webPort = reservePort();
  const webUrl = `http://127.0.0.1:${webPort}`;
  let logs = "";

  const child = spawn("npm", ["run", "dev"], {
    cwd: path.resolve(import.meta.dirname, "../.."),
    detached: true,
    env: {
      ...process.env,
      STUDY_NOTES_DATA_DIR: dataDir,
      STUDY_NOTES_BACKEND_PORT: String(backendPort),
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
    if (ownsDataDir) {
      await rm(dataDir, { recursive: true, force: true });
    }
    throw error;
  }

  return {
    webUrl,
    dataDir,
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

      if (ownsDataDir) {
        await rm(dataDir, { recursive: true, force: true });
      }
    }
  };
}

test("first launch asks the user to open a Notebook workspace", async ({ page }) => {
  const app = await startApp();

  try {
    await page.goto(app.webUrl);

    await expect(
      page.getByRole("heading", { name: "打开你的学习空间" })
    ).toBeVisible();
    await page
      .getByLabel("Notebook workspace 路径")
      .fill("/tmp/example-workspace");
    await expect(page.getByRole("button", { name: "打开工作区" })).toBeEnabled();
  } finally {
    await app.stop();
  }
});

test("opening a workspace maps its directories and Markdown files", async ({
  page
}) => {
  const workspaceDir = await mkdtemp(path.join(tmpdir(), "studynotes-workspace-"));
  const canonicalWorkspaceDir = await realpath(workspaceDir);
  await mkdir(path.join(workspaceDir, "课程", "第一章"), { recursive: true });
  await writeFile(
    path.join(workspaceDir, "课程", "第一章", "注意力机制.md"),
    "# 注意力机制\n\n注意力帮助我们筛选信息。\n",
    "utf8"
  );

  const app = await startApp();

  try {
    await page.goto(app.webUrl);
    await page.getByLabel("Notebook workspace 路径").fill(workspaceDir);
    await page.getByRole("button", { name: "打开工作区" }).click();

    await expect(
      page.getByRole("button", { name: "课程", exact: true })
    ).toBeVisible();
    await expect(
      page.getByRole("button", { name: "第一章", exact: true })
    ).toBeVisible();
    await expect(
      page.getByRole("button", { name: "注意力机制.md", exact: true })
    ).toBeVisible();
    await expect(
      page.getByText(canonicalWorkspaceDir, { exact: true })
    ).toBeVisible();
  } finally {
    await app.stop();
    await rm(workspaceDir, { recursive: true, force: true });
  }
});

test("opening a Markdown page shows rendered content without changing the file", async ({
  page
}) => {
  const workspaceDir = await mkdtemp(path.join(tmpdir(), "studynotes-workspace-"));
  await mkdir(path.join(workspaceDir, "课程"), { recursive: true });
  const markdownPath = path.join(workspaceDir, "课程", "注意力机制.md");
  const markdown =
    "# 注意力机制\n\n注意力帮助我们**筛选信息**，并保持目标。\n\n- 工作记忆\n- 选择性注意\n";
  await writeFile(markdownPath, markdown, "utf8");

  const app = await startApp();

  try {
    await page.goto(app.webUrl);
    await page.getByLabel("Notebook workspace 路径").fill(workspaceDir);
    await page.getByRole("button", { name: "打开工作区" }).click();
    await page
      .getByRole("button", { name: "注意力机制.md", exact: true })
      .click();

    await expect(
      page.getByRole("heading", { name: "注意力机制", exact: true })
    ).toBeVisible();
    await expect(page.getByText("筛选信息", { exact: true })).toBeVisible();
    await expect(page.getByText("工作记忆", { exact: true })).toBeVisible();
    await expect(page.getByRole("textbox")).toHaveCount(0);
    expect(await readFile(markdownPath, "utf8")).toBe(markdown);
  } finally {
    await app.stop();
    await rm(workspaceDir, { recursive: true, force: true });
  }
});

test("opening a PDF supports page navigation, zoom, text selection, and citation anchors", async ({
  page
}) => {
  const workspaceDir = await mkdtemp(path.join(tmpdir(), "studynotes-workspace-"));
  await mkdir(path.join(workspaceDir, "课程"), { recursive: true });
  const pdfRelativePath = "课程/注意力研究.pdf";
  const pdfPath = path.join(workspaceDir, pdfRelativePath);
  await writeFile(pdfPath, createTextLayerPdf());

  const app = await startApp();

  try {
    await page.goto(app.webUrl);
    await page.getByLabel("Notebook workspace 路径").fill(workspaceDir);
    await page.getByRole("button", { name: "打开工作区" }).click();
    await page
      .getByRole("button", { name: "注意力研究.pdf", exact: true })
      .click();

    await expect(page.getByText("第 1 / 3 页", { exact: true })).toBeVisible();
    await page.getByRole("button", { name: "下一页" }).click();
    await expect(page.getByText("第 2 / 3 页", { exact: true })).toBeVisible();
    await page.getByRole("button", { name: "上一页" }).click();
    await expect(page.getByText("第 1 / 3 页", { exact: true })).toBeVisible();

    const pdfPage = page.getByLabel("PDF 页面");
    const beforeZoom = await pdfPage.boundingBox();
    expect(beforeZoom).not.toBeNull();
    await page.getByRole("button", { name: "放大" }).click();
    await expect
      .poll(async () => (await pdfPage.boundingBox())?.width ?? 0)
      .toBeGreaterThan(beforeZoom?.width ?? 0);

    await selectPdfEvidence(page);
    const selectedFragment = page.getByRole("region", {
      name: "选中片段"
    });
    await expect(selectedFragment).toContainText(
      "Attention controls working memory."
    );
    await page.getByRole("button", { name: "保存引用" }).click();
    await expect(page.getByText("引用已保存", { exact: true })).toBeVisible();

    const citations = await page.evaluate(async (path) => {
      const response = await fetch(
        `/api/citations?path=${encodeURIComponent(path)}`
      );
      return (await response.json()) as Array<Record<string, unknown>>;
    }, pdfRelativePath);

    expect(citations).toHaveLength(1);
    expect(citations[0]).toMatchObject({
      page: 1,
      path: pdfRelativePath
    });
    expect(citations[0].quote).toContain("Attention controls working memory.");
    expect(citations[0].pdfSha256).toMatch(/^[a-f0-9]{64}$/);
  } finally {
    await app.stop();
    await rm(workspaceDir, { recursive: true, force: true });
  }
});

test("an externally changed PDF marks its saved citation as mismatched", async ({
  page
}) => {
  const workspaceDir = await mkdtemp(path.join(tmpdir(), "studynotes-workspace-"));
  await mkdir(path.join(workspaceDir, "课程"), { recursive: true });
  const pdfRelativePath = "课程/文献综述.pdf";
  const pdfPath = path.join(workspaceDir, pdfRelativePath);
  await writeFile(pdfPath, createTextLayerPdf());

  const app = await startApp();

  try {
    await page.goto(app.webUrl);
    await page.getByLabel("Notebook workspace 路径").fill(workspaceDir);
    await page.getByRole("button", { name: "打开工作区" }).click();
    await page
      .getByRole("button", { name: "文献综述.pdf", exact: true })
      .click();
    await expect(page.getByText("第 1 / 3 页", { exact: true })).toBeVisible();

    await selectPdfEvidence(page);
    await page.getByRole("button", { name: "保存引用" }).click();
    await expect(page.getByText("引用已保存", { exact: true })).toBeVisible();
    await page.getByRole("button", { name: "校验引用" }).click();
    await expect(page.getByText("引用仍有效", { exact: true })).toBeVisible();

    await writeFile(pdfPath, createTextLayerPdf("Second page revision."));
    await page.getByRole("button", { name: "校验引用" }).click();
    await expect(
      page.getByText("引用已失配：PDF 内容已变更", { exact: true })
    ).toBeVisible();
  } finally {
    await app.stop();
    await rm(workspaceDir, { recursive: true, force: true });
  }
});

test("a PDF page without a text layer explains that OCR is unsupported", async ({
  page
}) => {
  const workspaceDir = await mkdtemp(path.join(tmpdir(), "studynotes-workspace-"));
  await mkdir(path.join(workspaceDir, "课程"), { recursive: true });
  const pdfPath = path.join(workspaceDir, "课程", "扫描资料.pdf");
  await writeFile(pdfPath, createTextLayerPdf());

  const app = await startApp();

  try {
    await page.goto(app.webUrl);
    await page.getByLabel("Notebook workspace 路径").fill(workspaceDir);
    await page.getByRole("button", { name: "打开工作区" }).click();
    await page
      .getByRole("button", { name: "扫描资料.pdf", exact: true })
      .click();
    await expect(page.getByText("第 1 / 3 页", { exact: true })).toBeVisible();
    await page.getByRole("button", { name: "下一页" }).click();
    await page.getByRole("button", { name: "下一页" }).click();
    await expect(page.getByText("第 3 / 3 页", { exact: true })).toBeVisible();
    await expect(
      page.getByText("当前页没有可提取文本，首版不支持 OCR。", {
        exact: true
      })
    ).toBeVisible();
    await expect(page.getByRole("button", { name: "保存引用" })).toBeDisabled();
  } finally {
    await app.stop();
    await rm(workspaceDir, { recursive: true, force: true });
  }
});

test("the active Notebook workspace survives an application restart", async ({
  page
}) => {
  const workspaceDir = await mkdtemp(path.join(tmpdir(), "studynotes-workspace-"));
  const dataDir = await mkdtemp(path.join(tmpdir(), "studynotes-data-"));
  await mkdir(path.join(workspaceDir, "课程"), { recursive: true });
  await writeFile(
    path.join(workspaceDir, "课程", "持久化.md"),
    "# 持久化\n",
    "utf8"
  );
  const canonicalWorkspaceDir = await realpath(workspaceDir);

  const firstApp = await startApp({ dataDir });
  try {
    await page.goto(firstApp.webUrl);
    await page.getByLabel("Notebook workspace 路径").fill(workspaceDir);
    await page.getByRole("button", { name: "打开工作区" }).click();
    await expect(
      page.getByRole("button", { name: "课程", exact: true })
    ).toBeVisible();
  } finally {
    await firstApp.stop();
  }

  const secondApp = await startApp({ dataDir });
  try {
    await page.goto(secondApp.webUrl);
    await expect(
      page.getByRole("button", { name: "课程", exact: true })
    ).toBeVisible();
    await expect(
      page.getByText(canonicalWorkspaceDir, { exact: true })
    ).toBeVisible();
    await expect(
      page.getByRole("heading", { name: "打开你的学习空间" })
    ).toHaveCount(0);
  } finally {
    await secondApp.stop();
    await rm(workspaceDir, { recursive: true, force: true });
    await rm(dataDir, { recursive: true, force: true });
  }
});

test("a user can create a Markdown page in the selected directory", async ({
  page
}) => {
  const workspaceDir = await mkdtemp(path.join(tmpdir(), "studynotes-workspace-"));
  await mkdir(path.join(workspaceDir, "课程"), { recursive: true });
  const app = await startApp();

  try {
    await page.goto(app.webUrl);
    await page.getByLabel("Notebook workspace 路径").fill(workspaceDir);
    await page.getByRole("button", { name: "打开工作区" }).click();
    await page.getByRole("button", { name: "课程", exact: true }).click();
    await expect(
      page.getByRole("button", { name: "删除", exact: true })
    ).toBeDisabled();

    await page.getByRole("button", { name: "新建页面" }).click();
    await expect(page.getByText("Markdown 页面不存在。")).toHaveCount(0);
    await page.getByLabel("页面名称").fill("课堂笔记.md");
    await page.getByRole("button", { name: "创建页面" }).click();

    await expect(
      page.getByRole("button", { name: "课堂笔记.md", exact: true })
    ).toBeVisible();
    expect(
      await readFile(path.join(workspaceDir, "课程", "课堂笔记.md"), "utf8")
    ).toBe("# 课堂笔记\n\n");
  } finally {
    await app.stop();
    await rm(workspaceDir, { recursive: true, force: true });
  }
});

test("a user can move a page and rename a directory without losing content", async ({
  page
}) => {
  const workspaceDir = await mkdtemp(path.join(tmpdir(), "studynotes-workspace-"));
  const courseDir = path.join(workspaceDir, "课程");
  const archiveDir = path.join(workspaceDir, "归档");
  await mkdir(courseDir, { recursive: true });
  await mkdir(archiveDir, { recursive: true });
  const markdown = "# 课堂笔记\n\n不能丢失的内容。\n";
  await writeFile(path.join(courseDir, "课堂笔记.md"), markdown, "utf8");
  const app = await startApp();

  try {
    await page.goto(app.webUrl);
    await page.getByLabel("Notebook workspace 路径").fill(workspaceDir);
    await page.getByRole("button", { name: "打开工作区" }).click();
    await page
      .getByRole("button", { name: "课堂笔记.md", exact: true })
      .click();
    await page.getByRole("button", { name: "重命名或移动" }).click();
    await page.getByLabel("新相对路径").fill("归档/课堂笔记.md");
    await page.getByRole("button", { name: "保存路径" }).click();

    await expect(
      page.getByRole("button", { name: "课堂笔记.md", exact: true })
    ).toBeVisible();
    expect(
      await readFile(path.join(archiveDir, "课堂笔记.md"), "utf8")
    ).toBe(markdown);
    await expect(
      page.getByRole("button", { name: "归档", exact: true })
    ).toHaveAttribute("aria-pressed", "false");

    await page.getByRole("button", { name: "课程", exact: true }).click();
    await page.getByRole("button", { name: "重命名或移动" }).click();
    await page.getByLabel("新相对路径").fill("课程资料");
    await page.getByRole("button", { name: "保存路径" }).click();

    await expect(
      page.getByRole("button", { name: "课程资料", exact: true })
    ).toBeVisible();
    await expect(
      page.getByRole("button", { name: "课程", exact: true })
    ).toHaveCount(0);
    expect((await stat(path.join(workspaceDir, "课程资料"))).isDirectory()).toBe(
      true
    );
  } finally {
    await app.stop();
    await rm(workspaceDir, { recursive: true, force: true });
  }
});

test("deleting a page requires explicit confirmation", async ({ page }) => {
  const workspaceDir = await mkdtemp(path.join(tmpdir(), "studynotes-workspace-"));
  const courseDir = path.join(workspaceDir, "课程");
  const markdownPath = path.join(courseDir, "待删除.md");
  await mkdir(courseDir, { recursive: true });
  await writeFile(markdownPath, "# 待删除\n", "utf8");
  const app = await startApp();

  try {
    await page.goto(app.webUrl);
    await page.getByLabel("Notebook workspace 路径").fill(workspaceDir);
    await page.getByRole("button", { name: "打开工作区" }).click();
    await page.getByRole("button", { name: "待删除.md", exact: true }).click();
    await page.getByRole("button", { name: "删除", exact: true }).click();

    await expect(
      page.getByRole("heading", { name: "删除 Markdown 页面" })
    ).toBeVisible();
    expect((await stat(markdownPath)).isFile()).toBe(true);

    await page.getByRole("button", { name: "确认删除" }).click();
    await expect(
      page.getByRole("button", { name: "待删除.md", exact: true })
    ).toHaveCount(0);
    await expect(stat(markdownPath)).rejects.toThrow();
  } finally {
    await app.stop();
    await rm(workspaceDir, { recursive: true, force: true });
  }
});

test("external Markdown changes refresh the page tree and open page", async ({
  page
}) => {
  const workspaceDir = await mkdtemp(path.join(tmpdir(), "studynotes-workspace-"));
  const courseDir = path.join(workspaceDir, "课程");
  const livePagePath = path.join(courseDir, "实时.md");
  const addedPagePath = path.join(courseDir, "外部新增.md");
  const movedPagePath = path.join(courseDir, "外部移动.md");
  await mkdir(courseDir, { recursive: true });
  await writeFile(livePagePath, "# 实时\n\n初始内容。\n", "utf8");
  const app = await startApp();

  try {
    await page.goto(app.webUrl);
    await page.getByLabel("Notebook workspace 路径").fill(workspaceDir);
    await page.getByRole("button", { name: "打开工作区" }).click();
    await page.getByRole("button", { name: "实时.md", exact: true }).click();
    await expect(page.getByText("初始内容。")).toBeVisible();

    await writeFile(addedPagePath, "# 外部新增\n", "utf8");
    await expect(
      page.getByRole("button", { name: "外部新增.md", exact: true })
    ).toBeVisible();

    await writeFile(
      livePagePath,
      "# 实时\n\n外部更新内容。\n",
      "utf8"
    );
    await expect(page.getByText("外部更新内容。")).toBeVisible();

    await rename(addedPagePath, movedPagePath);
    await expect(
      page.getByRole("button", { name: "外部移动.md", exact: true })
    ).toBeVisible();
    await expect(
      page.getByRole("button", { name: "外部新增.md", exact: true })
    ).toHaveCount(0);

    await rm(movedPagePath);
    await expect(
      page.getByRole("button", { name: "外部移动.md", exact: true })
    ).toHaveCount(0);
  } finally {
    await app.stop();
    await rm(workspaceDir, { recursive: true, force: true });
  }
});

test("a moved Notebook workspace can be relocated without losing its records", async ({
  page
}) => {
  const workspaceDir = await mkdtemp(path.join(tmpdir(), "studynotes-workspace-"));
  const movedWorkspaceDir = `${workspaceDir}-moved`;
  const dataDir = await mkdtemp(path.join(tmpdir(), "studynotes-data-"));
  const courseDir = path.join(workspaceDir, "课程");
  const markdown = "# 可恢复页面\n\n学习记录仍然保留。\n";
  await mkdir(courseDir, { recursive: true });
  await writeFile(path.join(courseDir, "可恢复页面.md"), markdown, "utf8");
  const canonicalWorkspacePath = await realpath(workspaceDir);
  await mkdir(movedWorkspaceDir, { recursive: true });
  const canonicalMovedPath = await realpath(movedWorkspaceDir);
  await rm(movedWorkspaceDir, { recursive: true, force: true });
  const app = await startApp({ dataDir });

  try {
    await page.goto(app.webUrl);
    await page.getByLabel("Notebook workspace 路径").fill(workspaceDir);
    await page.getByRole("button", { name: "打开工作区" }).click();
    await expect(
      page.getByRole("button", { name: "可恢复页面.md", exact: true })
    ).toBeVisible();

    await rename(workspaceDir, movedWorkspaceDir);
    await expect(
      page.getByRole("heading", {
        name: "Notebook workspace 需要重新定位"
      })
    ).toBeVisible();
    await expect(
      page.getByText(canonicalWorkspacePath, { exact: true })
    ).toBeVisible();

    await page.getByLabel("新的 workspace 路径").fill(movedWorkspaceDir);
    await page.getByRole("button", { name: "重新定位工作区" }).click();

    await expect(
      page.getByRole("button", { name: "可恢复页面.md", exact: true })
    ).toBeVisible();
    await page
      .getByRole("button", { name: "可恢复页面.md", exact: true })
      .click();
    await expect(page.getByText("学习记录仍然保留。")).toBeVisible();
    await expect(page.getByText(canonicalMovedPath, { exact: true })).toBeVisible();
  } finally {
    await app.stop();
    await rm(movedWorkspaceDir, { recursive: true, force: true });
    await rm(dataDir, { recursive: true, force: true });
  }
});

test("the Electron development shell loads the same UI and stops local services", async () => {
  const workspaceDir = await mkdtemp(path.join(tmpdir(), "studynotes-workspace-"));
  const dataDir = await mkdtemp(path.join(tmpdir(), "studynotes-data-"));
  const backendPort = reservePort();
  const webPort = reservePort();
  await mkdir(path.join(workspaceDir, "课程"), { recursive: true });
  await writeFile(
    path.join(workspaceDir, "课程", "桌面壳.md"),
    "# 桌面壳\n",
    "utf8"
  );

  const electronApp = await electron.launch({
    args: [path.resolve(import.meta.dirname, "../../desktop/main.cjs")],
    env: {
      ...process.env,
      STUDY_NOTES_DATA_DIR: dataDir,
      STUDY_NOTES_BACKEND_PORT: String(backendPort),
      STUDY_NOTES_WEB_PORT: String(webPort)
    }
  });

  try {
    const window = await electronApp.firstWindow();
    await expect(
      window.getByRole("heading", { name: "打开你的学习空间" })
    ).toBeVisible();
    await window.getByLabel("Notebook workspace 路径").fill(workspaceDir);
    await window.getByRole("button", { name: "打开工作区" }).click();
    await expect(
      window.getByRole("button", { name: "桌面壳.md", exact: true })
    ).toBeVisible();
  } finally {
    await electronApp.close();
  }

  for (const url of [
    `http://127.0.0.1:${backendPort}/api/health`,
    `http://127.0.0.1:${webPort}`
  ]) {
    await expect
      .poll(
        async () => {
          try {
            await fetch(url);
            return true;
          } catch {
            return false;
          }
        },
        { timeout: 10_000 }
      )
      .toBe(false);
  }

  await rm(workspaceDir, { recursive: true, force: true });
  await rm(dataDir, { recursive: true, force: true });
});
