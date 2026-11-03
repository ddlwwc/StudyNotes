import {
  createHash,
  generateKeyPairSync,
  randomBytes,
  randomUUID,
  sign,
  type KeyObject
} from "node:crypto";
import {
  expect,
  test,
  type APIRequestContext,
  type APIResponse
} from "@playwright/test";

interface E2EKey {
  kid: string;
  privateKey: KeyObject;
  publicJwk: JsonWebKey;
}

interface PublishResponse {
  articleId: string;
  publicUrl: string;
  unlistedUrl: string;
  version: number;
  versionId: string;
  fingerprint: string;
}

const LIBRARY_MEDIA_KEY = "library-media-e2e-key-0123456789abcdef";

let key: E2EKey;

test.describe.configure({ mode: "serial" });

test.beforeAll(async ({ request }, testInfo) => {
  const { privateKey, publicKey } = generateKeyPairSync("ed25519");
  const publicJwk = publicKey.export({ format: "jwk" }) as JsonWebKey;
  key = {
    kid: `e2e-${testInfo.project.name}-${randomBytes(5).toString("hex")}`.slice(
      0,
      120
    ),
    privateKey,
    publicJwk
  };
  const response = await request.post("/api/v1/publish-keys", {
    headers: {
      "x-studynotes-registration-secret": "test-registration-secret"
    },
    data: {
      kid: key.kid,
      publicKeyJwk: {
        kty: "OKP",
        crv: "Ed25519",
        x: publicJwk.x
      }
    }
  });
  expect(response.status()).toBe(201);
});

test("public library matches the prototype layout and responsive bounds", async ({
  page
}, testInfo) => {
  await page.goto("/");
  await expect(page.getByRole("heading", { name: "公开学习资料" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "认知负荷理论与学习设计" })).toBeVisible();

  const metrics = await page.evaluate(() => {
    const header = document.querySelector(".site-header");
    const hero = document.querySelector(".public-hero");
    const heading = document.querySelector(".public-hero h1");
    const grid = document.querySelector(".article-grid");
    return {
      headerHeight: header ? getComputedStyle(header).height : "",
      heroHeight: hero ? getComputedStyle(hero).height : "",
      heroBackground: hero ? getComputedStyle(hero).backgroundColor : "",
      headingSize: heading ? getComputedStyle(heading).fontSize : "",
      gridColumns: grid ? getComputedStyle(grid).gridTemplateColumns : "",
      viewportWidth: window.innerWidth,
      scrollWidth: document.documentElement.scrollWidth
    };
  });
  expect(metrics.headerHeight).toBe("64px");
  expect(metrics.heroBackground).toBe("rgb(247, 248, 250)");
  if (testInfo.project.name === "chromium") {
    expect(metrics.heroHeight).toBe("248px");
    expect(metrics.headingSize).toBe("34px");
    expect(metrics.gridColumns.split(" ")).toHaveLength(3);
  } else {
    expect(Number.parseFloat(metrics.heroHeight)).toBeGreaterThan(248);
    expect(metrics.headingSize).toBe("30px");
    expect(metrics.gridColumns.split(" ")).toHaveLength(1);
  }
  expect(metrics.scrollWidth).toBeLessThanOrEqual(metrics.viewportWidth + 1);
  await page.screenshot({
    path: testInfo.outputPath("home.png"),
    fullPage: true
  });
});

test("public discovery, Chinese search and unlisted isolation", async ({
  page,
  request
}, testInfo) => {
  const suffix = uniqueSuffix(testInfo);
  const publicTitle = `公开发现文章 ${suffix}`;
  const unlistedTitle = `未列出隐藏文章 ${suffix}`;
  const publicKeyword = `公开独有关键词${suffix}`;
  const unlistedKeyword = `未列出独有关键词${suffix}`;
  const publicArticle = await publishArticle(request, {
    requestId: requestId("discover-public"),
    sourceMaterialId: `discover-public-${suffix}`,
    title: publicTitle,
    bodyHtml: `<h2>公开章节</h2><p>${publicKeyword}</p>`,
    tags: ["公开发现"]
  });
  const unlistedArticle = await publishArticle(request, {
    requestId: requestId("discover-unlisted"),
    sourceMaterialId: `discover-unlisted-${suffix}`,
    visibility: "UNLISTED",
    title: unlistedTitle,
    bodyHtml: `<h2>未列出章节</h2><p>${unlistedKeyword}</p>`,
    tags: ["不可发现"]
  });

  await page.goto("/");
  await expect(page.getByRole("heading", { name: publicTitle })).toBeVisible();
  await expect(page.getByText(unlistedTitle)).toHaveCount(0);

  await page.goto(`/search?q=${encodeURIComponent(publicKeyword)}`);
  await expect(page.getByRole("heading", { name: publicTitle })).toBeVisible();
  await expect(page.getByRole("heading", { name: unlistedTitle })).toHaveCount(0);

  await page.goto(`/search?q=${encodeURIComponent(unlistedKeyword)}`);
  await expect(page.getByRole("heading", { name: unlistedTitle })).toHaveCount(0);
  await expect(page.getByText("没有找到匹配的公开文章")).toBeVisible();

  await page.goto(`/a/${publicArticle.articleId}`);
  await expect(page.getByRole("heading", { name: publicTitle })).toBeVisible();
  await expect(page.locator('meta[name="robots"]')).toHaveAttribute(
    "content",
    /noindex/
  );

  await page.goto(`/u/${unlistedArticle.unlistedUrl.split("/").at(-1)}`);
  await expect(page.getByRole("heading", { name: unlistedTitle })).toBeVisible();
  await expect(page.locator('meta[name="robots"]')).toHaveAttribute(
    "content",
    /noindex/
  );
  expect((await request.get("/sitemap.xml")).status()).toBe(404);
});

test("default-hidden study layer supports annotation-only, AI-only and both", async ({
  page,
  request
}, testInfo) => {
  const suffix = uniqueSuffix(testInfo);
  const pageErrors: string[] = [];
  page.on("pageerror", (error) => pageErrors.push(error.message));
  const quote = "有效设计应降低无关负荷，并为生成性加工留出空间。";
  const annotationNote = `仅标注备注${suffix}`;
  const aiBody = `仅 AI 研读内容${suffix}`;
  const bothNote = `同时公开备注${suffix}`;
  const bothAi = `同时公开 AI 附录${suffix}`;

  const annotationOnly = await publishArticle(request, {
    requestId: requestId("annotation-only"),
    sourceMaterialId: `annotation-only-${suffix}`,
    title: `仅公开标注 ${suffix}`,
    bodyHtml: `<h2>标注章节</h2><p>${quote}</p>`,
    publishAnnotations: true,
    annotations: [{ id: "annotation-only", quote, note: annotationNote }]
  });
  await page.goto(`/a/${annotationOnly.articleId}`);
  await expect(page.locator(".article-body .public-annotation")).toContainText(
    annotationNote
  );
  await expect(page.getByText(/AI 研读附录/)).toHaveCount(0);
  await expect(page.locator(".study-panel")).toHaveCount(0);
  await page.getByRole("button", { name: /研读层/ }).click();
  await expect(page.locator(".study-panel")).toContainText(annotationNote);
  expect(pageErrors).toEqual([]);

  const aiOnly = await publishArticle(request, {
    requestId: requestId("ai-only"),
    sourceMaterialId: `ai-only-${suffix}`,
    title: `仅公开 AI ${suffix}`,
    bodyHtml: `<h2>AI 章节</h2><p>正文保持独立。</p>`,
    publishAi: true,
    aiAppendix: [{ id: "ai-only", title: "AI 研读附录", body: aiBody }]
  });
  await page.goto(`/a/${aiOnly.articleId}`);
  await expect(page.getByText("AI 研读附录 · 1 项")).toBeVisible();
  await expect(page.locator(".article-body .public-annotation")).toHaveCount(0);
  await page.getByRole("button", { name: /研读层/ }).click();
  await page.getByRole("tab", { name: /AI 附录/ }).click();
  await expect(page.locator(".study-panel")).toContainText(aiBody);

  const both = await publishArticle(request, {
    requestId: requestId("both-layers"),
    sourceMaterialId: `both-layers-${suffix}`,
    title: `同时公开研读层 ${suffix}`,
    bodyHtml: `<h2>完整研读层</h2><p>${quote}</p>`,
    publishAnnotations: true,
    publishAi: true,
    annotations: [{ id: "both-annotation", quote, note: bothNote }],
    aiAppendix: [{ id: "both-ai", title: "AI 研读附录", body: bothAi }]
  });
  await page.goto(`/a/${both.articleId}`);
  await expect(page.locator(".article-body .public-annotation")).toContainText(
    bothNote
  );
  await expect(page.getByText("AI 研读附录 · 1 项")).toBeVisible();
  await expect(page.getByRole("button", { name: /回复|点赞|收藏/ })).toHaveCount(
    0
  );

  await page.goto(`/search?q=${encodeURIComponent(annotationNote)}`);
  await expect(page.getByRole("heading", { name: `仅公开标注 ${suffix}` })).toBeVisible();
  await page.goto(`/search?q=${encodeURIComponent(aiBody)}`);
  await expect(page.getByRole("heading", { name: `仅公开 AI ${suffix}` })).toBeVisible();
});

test("private media upload, public signed read and standalone HTML export", async ({
  page,
  request
}, testInfo) => {
  const suffix = uniqueSuffix(testInfo);
  const objectKey = `articles/e2e/${suffix}.png`;
  const bytes = Buffer.from(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9ZQmcAAAAASUVORK5CYII=",
    "base64"
  );
  const contentType = "image/png";
  const contentHash = `sha256:${createHash("sha256").update(bytes).digest("hex")}`;
  const upload = await signedFetch(request, "POST", "/api/v1/media/upload-token", {
    objectKey,
    contentHash,
    contentType,
    size: bytes.length
  });
  expect(upload.status()).toBe(200);

  const stored = await request.post("/api/test/media", {
    data: {
      objectKey,
      contentType,
      base64: bytes.toString("base64")
    }
  });
  expect(stored.status()).toBe(200);
  const metadata = (await stored.json()) as { contentHash: string; size: number };

  const publish = await publishArticle(request, {
    requestId: requestId("media-publish"),
    sourceMaterialId: `media-publish-${suffix}`,
    title: `带私有媒体的文章 ${suffix}`,
    bodyHtml: `<h2>媒体章节</h2><figure><img data-object-key="${objectKey}" alt="单像素图片"><figcaption>受控媒体</figcaption></figure>`,
    mediaRefs: [
      {
        objectKey,
        contentHash: metadata.contentHash,
        contentType,
        size: bytes.length,
        reference: "figure-e2e"
      }
    ]
  });

  await page.goto(`/a/${publish.articleId}`);
  const image = page.locator(".article-body img");
  await expect(image).toBeVisible();
  const source = await image.getAttribute("src");
  expect(source).toContain(`/a/${publish.articleId}/media/`);
  const redirect = await request.get(source!, { maxRedirects: 0 });
  expect(redirect.status()).toBe(307);
  expect(redirect.headers().location).toContain("memory://media/");

  const exported = await request.get(`/a/${publish.articleId}/export`);
  expect(exported.status()).toBe(200);
  expect(exported.headers()["content-disposition"]).toContain("attachment");
  const html = await exported.text();
  expect(html).toContain("<!doctype html>");
  expect(html).toContain("<style>");
  expect(html).toContain("data:image/png;base64,");
  expect(html).not.toContain("script");
});

test("library media uses Bearer, survives publish copy and can be cleaned independently", async ({
  page,
  request
}, testInfo) => {
  const suffix = uniqueSuffix(testInfo);
  const bytes = Buffer.from(`library-media-${suffix}`);
  const contentHash = sha256(bytes);
  const unauthorized = await request.get("/api/v1/library-media/status");
  expect(unauthorized.status()).toBe(401);
  const status = await request.get("/api/v1/library-media/status", {
    headers: { authorization: `Bearer ${LIBRARY_MEDIA_KEY}` }
  });
  expect(status.status()).toBe(200);
  expect(await status.json()).toMatchObject({
    ok: true,
    bucket: "memory",
    httpWarning: true
  });

  const upload = await libraryMediaJson(
    request,
    "/api/v1/library-media/upload-token",
    {
      contentHash,
      contentType: "image/png",
      size: bytes.length
    }
  );
  expect(upload.status()).toBe(200);
  const credential = (await upload.json()) as {
    objectKey: string;
    alreadyExists: boolean;
  };
  expect(credential.objectKey).toMatch(/^library-media\/[a-f0-9]{64}\.png$/);
  expect(credential.alreadyExists).toBe(false);

  const stored = await request.post("/api/test/media", {
    data: {
      objectKey: credential.objectKey,
      contentType: "image/png",
      base64: bytes.toString("base64")
    }
  });
  expect(stored.status()).toBe(200);
  const pendingPreview = await libraryMediaJson(
    request,
    "/api/v1/library-media/publish-preview",
    {
      bodyHtml: `<img data-object-key="${credential.objectKey}" alt="待上传">`,
      mediaRefs: [
        {
          objectKey: credential.objectKey,
          contentHash,
          contentType: "image/png",
          size: bytes.length,
          reference: `media://qiniu/${credential.objectKey}`
        }
      ]
    }
  );
  expect(await pendingPreview.json()).toMatchObject({
    ready: false,
    media: [{ status: "PENDING" }]
  });
  const complete = await libraryMediaJson(
    request,
    "/api/v1/library-media/complete",
    { objectKey: credential.objectKey }
  );
  expect(complete.status()).toBe(200);
  const readyPreview = await libraryMediaJson(
    request,
    "/api/v1/library-media/publish-preview",
    {
      bodyHtml: `<img data-object-key="${credential.objectKey}" alt="已就绪">`,
      mediaRefs: [
        {
          objectKey: credential.objectKey,
          contentHash,
          contentType: "image/png",
          size: bytes.length,
          reference: `media://qiniu/${credential.objectKey}`
        }
      ]
    }
  );
  expect(await readyPreview.json()).toMatchObject({ ready: true });
  const readUrl = await libraryMediaJson(
    request,
    "/api/v1/library-media/read-url",
    { objectKey: credential.objectKey }
  );
  expect(readUrl.status()).toBe(200);
  expect(((await readUrl.json()) as { url: string }).url).toContain(
    "memory://media/"
  );

  const published = await publishArticle(request, {
    requestId: requestId("library-media-publish"),
    sourceMaterialId: `library-media-publish-${suffix}`,
    title: `笔记媒体发布 ${suffix}`,
    bodyHtml: `<figure><img data-object-key="${credential.objectKey}" alt="笔记媒体"></figure>`,
    mediaRefs: [
      {
        objectKey: credential.objectKey,
        contentHash,
        contentType: "image/png",
        size: bytes.length,
        reference: `media://qiniu/${credential.objectKey}`
      }
    ]
  });
  await page.goto(`/a/${published.articleId}`);
  const image = page.locator(".article-body img");
  await expect(image).toBeVisible();
  const imageSource = await image.getAttribute("src");
  const redirect = await request.get(imageSource!, { maxRedirects: 0 });
  expect(redirect.status()).toBe(307);
  expect(decodeURIComponent(redirect.headers().location!)).toContain(
    "memory://media/published-media/"
  );

  await libraryMediaJson(request, "/api/v1/library-media/scan", {
    sourceId: `library-note-${suffix}`,
    references: []
  });
  const candidates = await request.get(
    "/api/v1/library-media/cleanup-candidates",
    { headers: { authorization: `Bearer ${LIBRARY_MEDIA_KEY}` } }
  );
  expect(candidates.status()).toBe(200);
  expect(await candidates.json()).toMatchObject({
    media: expect.arrayContaining([
      expect.objectContaining({ objectKey: credential.objectKey })
    ])
  });
  const cleanup = await libraryMediaJson(
    request,
    "/api/v1/library-media/cleanup",
    { objectKeys: [credential.objectKey], confirmed: true }
  );
  expect(cleanup.status()).toBe(200);
  const gone = await libraryMediaJson(
    request,
    "/api/v1/library-media/read-url",
    { objectKey: credential.objectKey }
  );
  expect(gone.status()).toBe(404);

  await page.reload();
  await expect(page.locator(".article-body img")).toBeVisible();
});

test("lifecycle covers conflict, rollback, visibility, withdraw and permanent delete", async ({
  page,
  request
}, testInfo) => {
  const suffix = uniqueSuffix(testInfo);
  const oldKeyword = `旧版本关键词${suffix}`;
  const newKeyword = `新版本关键词${suffix}`;
  const first = await publishArticle(request, {
    requestId: requestId("lifecycle-v1"),
    sourceMaterialId: `lifecycle-${suffix}`,
    title: `生命周期文章 ${suffix}`,
    bodyHtml: `<h2>第一版</h2><p>${oldKeyword}</p>`
  });
  const secondBody = {
    requestId: requestId("lifecycle-v2"),
    articleId: first.articleId,
    sourceMaterialId: `lifecycle-${suffix}`,
    expectedVersion: 1,
    visibility: "PUBLIC",
    title: `生命周期文章 ${suffix}`,
    summary: "",
    bodyHtml: `<h2>第二版</h2><p>${newKeyword}</p>`,
    tags: [],
    publishAnnotations: false,
    publishAi: false
  };
  const second = await signedJson(request, "POST", "/api/v1/publish", secondBody);
  expect(second.status()).toBe(201);
  const secondResult = (await second.json()) as PublishResponse;
  expect(secondResult.version).toBe(2);

  const staleBody = {
    ...secondBody,
    requestId: requestId("lifecycle-stale")
  };
  const stale = await signedJson(request, "POST", "/api/v1/publish", staleBody);
  expect(stale.status()).toBe(409);
  expect((await stale.json()).code).toBe("VERSION_CONFLICT");

  const rollbackBody = {
    requestId: requestId("lifecycle-rollback"),
    expectedVersion: 2,
    targetVersion: 1
  };
  const rollback = await signedJson(
    request,
    "POST",
    `/api/v1/articles/${first.articleId}/rollback`,
    rollbackBody
  );
  expect(rollback.status()).toBe(200);
  await page.goto(`/search?q=${encodeURIComponent(oldKeyword)}`);
  await expect(
    page.getByRole("heading", { name: `生命周期文章 ${suffix}` })
  ).toBeVisible();
  await page.goto(`/search?q=${encodeURIComponent(newKeyword)}`);
  await expect(
    page.getByRole("heading", { name: `生命周期文章 ${suffix}` })
  ).toHaveCount(0);

  const visibilityBody = {
    requestId: requestId("lifecycle-unlisted"),
    expectedVersion: 1,
    visibility: "UNLISTED"
  };
  const visibility = await signedJson(
    request,
    "POST",
    `/api/v1/articles/${first.articleId}/visibility`,
    visibilityBody
  );
  expect(visibility.status()).toBe(200);
  expect((await request.get(`/a/${first.articleId}`)).status()).toBe(404);
  const token = first.unlistedUrl.split("/").at(-1)!;
  expect((await request.get(`/u/${token}`)).status()).toBe(200);

  const status = await signedFetch(
    request,
    "GET",
    `/api/v1/articles/${first.articleId}/status`,
    ""
  );
  expect(status.status()).toBe(200);
  const mapping = await status.json();
  expect(mapping).toMatchObject({
    articleId: first.articleId,
    currentVersion: 1,
    visibility: "UNLISTED"
  });

  const withdrawBody = {
    requestId: requestId("lifecycle-withdraw"),
    expectedVersion: 1
  };
  const withdraw = await signedJson(
    request,
    "POST",
    `/api/v1/articles/${first.articleId}/withdraw`,
    withdrawBody
  );
  expect(withdraw.status()).toBe(200);
  expect((await request.get(`/u/${token}`)).status()).toBe(404);

  const deleteBody = {
    requestId: requestId("lifecycle-delete"),
    expectedVersion: 1
  };
  const deletion = await signedJson(
    request,
    "DELETE",
    `/api/v1/articles/${first.articleId}`,
    deleteBody
  );
  expect(deletion.status()).toBe(200);
  const repeatedDeletion = await signedJson(
    request,
    "DELETE",
    `/api/v1/articles/${first.articleId}`,
    deleteBody
  );
  expect(repeatedDeletion.status()).toBe(200);
  expect(await repeatedDeletion.json()).toEqual({
    articleId: first.articleId,
    deleted: true
  });
  expect((await request.get(`/a/${first.articleId}`)).status()).toBe(404);
  expect((await request.get(`/u/${token}`)).status()).toBe(404);
  const goneStatus = await signedFetch(
    request,
    "GET",
    `/api/v1/articles/${first.articleId}/status`,
    ""
  );
  expect(goneStatus.status()).toBe(404);
});

async function publishArticle(
  request: APIRequestContext,
  overrides: Record<string, unknown>
): Promise<PublishResponse> {
  const response = await signedJson(request, "POST", "/api/v1/publish", {
    requestId: requestId("publish"),
    sourceMaterialId: `material-${randomUUID()}`,
    sourceVersionId: "local-version",
    expectedVersion: 0,
    visibility: "PUBLIC",
    title: "测试文章",
    summary: "",
    bodyHtml: "<h2>正文</h2><p>测试内容</p>",
    tags: [],
    publishAnnotations: false,
    publishAi: false,
    annotations: undefined,
    aiAppendix: undefined,
    mediaRefs: undefined,
    ...overrides
  });
  expect(response.status()).toBe(201);
  return (await response.json()) as PublishResponse;
}

async function signedJson(
  request: APIRequestContext,
  method: string,
  path: string,
  body: unknown | string
): Promise<APIResponse> {
  const raw =
    typeof body === "string" ? body : JSON.stringify(removeUndefined(body));
  return request.fetch(path, {
    method,
    headers: signedHeaders(method, path, raw),
    data: raw
  });
}

async function signedFetch(
  request: APIRequestContext,
  method: string,
  path: string,
  body: unknown | string
): Promise<APIResponse> {
  const raw =
    typeof body === "string" ? body : JSON.stringify(removeUndefined(body));
  return request.fetch(path, {
    method,
    headers: signedHeaders(method, path, raw),
    data: raw
  });
}

function signedHeaders(
  method: string,
  path: string,
  body: string
): Record<string, string> {
  const timestamp = Math.floor(Date.now() / 1000).toString();
  const nonce = randomBytes(18).toString("base64url");
  const contentSha256 = sha256(body);
  const canonical = [
    method.toUpperCase(),
    path,
    timestamp,
    nonce,
    contentSha256
  ].join("\n");
  const signature = sign(null, Buffer.from(canonical), key.privateKey).toString(
    "base64url"
  );
  return {
    "content-type": "application/json",
    "x-studynotes-key-id": key.kid,
    "x-studynotes-timestamp": timestamp,
    "x-studynotes-nonce": nonce,
    "x-studynotes-signature": signature,
    "x-studynotes-content-sha256": contentSha256
  };
}

function sha256(value: string | Buffer): string {
  return `sha256:${createHash("sha256").update(value).digest("hex")}`;
}

function libraryMediaJson(
  request: APIRequestContext,
  path: string,
  body: unknown
): Promise<APIResponse> {
  return request.post(path, {
    headers: { authorization: `Bearer ${LIBRARY_MEDIA_KEY}` },
    data: body
  });
}

function removeUndefined(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map(removeUndefined);
  }
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>)
        .filter(([, nested]) => nested !== undefined)
        .map(([name, nested]) => [name, removeUndefined(nested)])
    );
  }
  return value;
}

function requestId(prefix: string): string {
  return `${prefix}-${randomUUID()}`;
}

function uniqueSuffix(testInfo: { project: { name: string } }): string {
  return `${testInfo.project.name}-${randomBytes(5).toString("hex")}`;
}
