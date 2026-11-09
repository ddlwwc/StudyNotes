import { expect, test } from "@playwright/test";
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

function reservePort(): number {
  return 35_000 + Math.floor(Math.random() * 10_000);
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
