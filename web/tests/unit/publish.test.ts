import {
  createHash,
  generateKeyPairSync,
  type KeyObject
} from "node:crypto";
import { describe, expect, it } from "vitest";
import {
  AuthenticationError,
  ConflictError,
  ExternalServiceError,
  ReplayError,
  ValidationError
} from "@/domain/errors";
import type {
  MediaReferenceInput,
  PublicKeyJwk
} from "@/domain/types";
import { validateContract, getContractDocument } from "@/lib/contract";
import { preparePublishRequest } from "@/lib/publish-preview";
import { MemoryRepository } from "@/lib/repository/memory";
import {
  assertTimestampFresh,
  createCanonicalString,
  sha256,
  signRequest,
  verifyRequestSignature
} from "@/lib/signature";
import { SignatureAuthenticator } from "@/lib/signature-auth";
import { MemoryStorageAdapter } from "@/lib/storage/memory";
import { PublishService } from "@/lib/services/publish-service";
import { ReadService } from "@/lib/services/read-service";
import type {
  PublishRequest,
  VisibilityRequest
} from "@/lib/api-types";
import { buildReaderContent } from "@/lib/html";

interface Harness {
  repository: MemoryRepository;
  storage: MemoryStorageAdapter;
  publishService: PublishService;
  readService: ReadService;
  authenticator: SignatureAuthenticator;
  privateKey: KeyObject;
  publicJwk: PublicKeyJwk;
  kid: string;
}

async function createHarness(): Promise<Harness> {
  const repository = new MemoryRepository();
  const storage = new MemoryStorageAdapter();
  const publishService = new PublishService(repository, storage, {
    baseUrl: "http://127.0.0.1:8090",
    mediaUrlTtlSeconds: 300
  });
  const readService = new ReadService(repository, storage);
  const authenticator = new SignatureAuthenticator(repository, {
    timestampSkewSeconds: 300
  });
  const { privateKey, publicKey } = generateKeyPairSync("ed25519");
  const publicJwk = publicKey.export({ format: "jwk" }) as JsonWebKey;
  const kid = "test-publish-key-01";
  await publishService.registerKey({
    kid,
    publicKeyJwk: {
      kty: "OKP",
      crv: "Ed25519",
      x: publicJwk.x!
    }
  });
  return {
    repository,
    storage,
    publishService,
    readService,
    authenticator,
    privateKey,
    publicJwk: publicJwk as PublicKeyJwk,
    kid
  };
}

function buildRequest(overrides: Partial<PublishRequest> = {}): PublishRequest {
  return {
    requestId: "publish-request-0001",
    sourceMaterialId: "material-001",
    sourceVersionId: "local-version-1",
    expectedVersion: 0,
    visibility: "PUBLIC",
    title: "认知负荷理论与学习设计",
    summary: "从工作记忆限制出发设计学习材料。",
    bodyHtml:
      "<h2>认知负荷是什么？</h2><p>有效设计应降低无关负荷，并为生成性加工留出空间。</p><h2>学习设计启示</h2><p>减少无关加工。</p>",
    tags: ["认知心理", "学习科学"],
    publishAnnotations: false,
    publishAi: false,
    ...overrides
  };
}

async function authenticate(
  harness: Harness,
  method: string,
  pathname: string,
  body: string,
  nonce: string
) {
  const signature = signRequest(
    { method, pathname, body },
    harness.privateKey,
    { nonce }
  );
  const request = new Request(`https://example.test${pathname}`, {
    method,
    headers: {
      "x-studynotes-key-id": harness.kid,
      "x-studynotes-timestamp": signature.timestamp,
      "x-studynotes-nonce": nonce,
      "x-studynotes-signature": signature.signature,
      "x-studynotes-content-sha256": signature.contentSha256
    }
  });
  return harness.authenticator.authenticate(request, body);
}

describe("Ed25519 publish signatures", () => {
  it("signs canonical request fields and verifies them", async () => {
    const harness = await createHarness();
    const body = JSON.stringify({ title: "测试" });
    const headers = signRequest(
      {
        method: "POST",
        pathname: "/api/v1/publish",
        searchParams: new URLSearchParams("z=2&a=1"),
        body
      },
      harness.privateKey,
      { timestamp: "1760000000", nonce: "nonce-1234567890" }
    );
    expect(
      createCanonicalString(
        {
          method: "POST",
          pathname: "/api/v1/publish",
          searchParams: new URLSearchParams("z=2&a=1"),
          body
        },
        headers.timestamp,
        headers.nonce,
        headers.contentSha256
      )
    ).toContain("/api/v1/publish?a=1&z=2");
    expect(() =>
      verifyRequestSignature(
        {
          method: "POST",
          pathname: "/api/v1/publish",
          searchParams: new URLSearchParams("z=2&a=1"),
          body
        },
        {
          ...headers,
          keyId: harness.kid
        },
        harness.publicJwk
      )
    ).not.toThrow();
  });

  it("rejects tampered body, stale timestamps and nonce replay", async () => {
    const harness = await createHarness();
    const body = JSON.stringify(buildRequest());
    const signature = signRequest(
      { method: "POST", pathname: "/api/v1/publish", body },
      harness.privateKey,
      { nonce: "nonce-tamper-00001" }
    );
    expect(() =>
      verifyRequestSignature(
        {
          method: "POST",
          pathname: "/api/v1/publish",
          body: body.replace("认知负荷", "篡改内容")
        },
        {
          ...signature,
          keyId: harness.kid
        },
        harness.publicJwk
      )
    ).toThrow(AuthenticationError);
    expect(() =>
      assertTimestampFresh("1000000000", 300, 1760000000000)
    ).toThrow(AuthenticationError);

    await authenticate(
      harness,
      "POST",
      "/api/v1/publish",
      body,
      "nonce-replay-000001"
    );
    await expect(
      authenticate(
        harness,
        "POST",
        "/api/v1/publish",
        body,
        "nonce-replay-000001"
      )
    ).rejects.toBeInstanceOf(ReplayError);
  });
});

describe("OpenAPI runtime boundary", () => {
  it("applies defaults and rejects private or unknown request fields", () => {
    const valid = {
      requestId: "request-contract-001",
      sourceMaterialId: "material-contract",
      expectedVersion: 0,
      visibility: "PUBLIC",
      title: "契约测试",
      bodyHtml: "<p>正文</p>",
      publishAnnotations: false,
      publishAi: false
    };
    const parsed = validateContract<PublishRequest>("PublishRequest", valid);
    expect(parsed.summary).toBe("");
    expect(parsed.tags).toEqual([]);
    expect(() =>
      validateContract("PublishRequest", {
        ...valid,
        privateAnnotations: [{ id: "private" }]
      })
    ).toThrow(ValidationError);
  });

  it("allows a public annotation without a note", () => {
    const parsed = validateContract<PublishRequest>("PublishRequest", {
      requestId: "request-contract-note",
      sourceMaterialId: "material-contract-note",
      expectedVersion: 0,
      visibility: "PUBLIC",
      title: "无备注标注",
      bodyHtml: "<p>可高亮正文</p>",
      publishAnnotations: true,
      publishAi: false,
      annotations: [
        {
          id: "annotation-without-note",
          quote: "可高亮正文",
          blockId: "0"
        }
      ]
    });
    expect(parsed.annotations?.[0]?.note).toBe("");
  });

  it("defines the complete publish lifecycle in one contract", () => {
    const contract = getContractDocument<{
      paths: Record<string, unknown>;
      openapi: string;
    }>();
    expect(contract.openapi).toBe("3.1.0");
    expect(Object.keys(contract.paths)).toEqual(
      expect.arrayContaining([
        "/api/v1/publish",
        "/api/v1/articles/{articleId}/visibility",
        "/api/v1/articles/{articleId}/rollback",
        "/api/v1/articles/{articleId}/withdraw",
        "/api/v1/articles/{articleId}",
        "/api/v1/media/upload-token"
      ])
    );
  });
});

describe("publishing, idempotency and immutable versions", () => {
  it("creates one stable article and reuses identical requests and content", async () => {
    const harness = await createHarness();
    const input = buildRequest();
    const raw = JSON.stringify(input);
    await authenticate(
      harness,
      "POST",
      "/api/v1/publish",
      raw,
      "nonce-publish-000001"
    );
    const first = await harness.publishService.publish(
      harness.kid,
      sha256(raw),
      input
    );
    expect(first.status).toBe(201);
    expect(first.response.createdArticle).toBe(true);
    expect(first.response.version).toBe(1);

    await authenticate(
      harness,
      "POST",
      "/api/v1/publish",
      raw,
      "nonce-publish-000002"
    );
    const repeated = await harness.publishService.publish(
      harness.kid,
      sha256(raw),
      input
    );
    expect(repeated.response.idempotent).toBe(true);
    expect(repeated.response.articleId).toBe(first.response.articleId);
    expect(repeated.response.version).toBe(1);

    const sameContent = { ...input, requestId: "publish-request-0002", expectedVersion: 1 };
    const sameRaw = JSON.stringify(sameContent);
    await authenticate(
      harness,
      "POST",
      "/api/v1/publish",
      sameRaw,
      "nonce-publish-000003"
    );
    const reused = await harness.publishService.publish(
      harness.kid,
      sha256(sameRaw),
      sameContent
    );
    expect(reused.response.reusedVersion).toBe(true);
    expect(reused.response.createdVersion).toBe(false);
    expect(reused.response.version).toBe(1);
  });

  it("creates immutable versions and rejects stale clients", async () => {
    const harness = await createHarness();
    const firstInput = buildRequest();
    const firstRaw = JSON.stringify(firstInput);
    await authenticate(
      harness,
      "POST",
      "/api/v1/publish",
      firstRaw,
      "nonce-version-000001"
    );
    const first = await harness.publishService.publish(
      harness.kid,
      sha256(firstRaw),
      firstInput
    );
    const updateInput = buildRequest({
      requestId: "publish-request-0102",
      expectedVersion: 1,
      bodyHtml:
        "<h2>更新后的章节</h2><p>这是不可变第二版本的正文内容。</p>"
    });
    const updateRaw = JSON.stringify(updateInput);
    await authenticate(
      harness,
      "POST",
      "/api/v1/publish",
      updateRaw,
      "nonce-version-000002"
    );
    const second = await harness.publishService.publish(
      harness.kid,
      sha256(updateRaw),
      updateInput
    );
    expect(second.response.version).toBe(2);
    expect(second.response.createdVersion).toBe(true);

    const article = await harness.repository.getArticleByPublicId(
      first.response.articleId
    );
    expect(article).not.toBeNull();
    const versionOne = await harness.repository.getVersion(article!.id, 1);
    const versionTwo = await harness.repository.getVersion(article!.id, 2);
    expect(versionOne?.title).toBe(firstInput.title);
    expect(versionTwo?.bodyHtml).toContain("不可变第二版本");

    const stale = buildRequest({
      requestId: "publish-request-0103",
      articleId: first.response.articleId,
      expectedVersion: 1,
      bodyHtml: "<p>试图覆盖较新版本。</p>"
    });
    const staleRaw = JSON.stringify(stale);
    await authenticate(
      harness,
      "POST",
      "/api/v1/publish",
      staleRaw,
      "nonce-version-000003"
    );
    await expect(
      harness.publishService.publish(harness.kid, sha256(staleRaw), stale)
    ).rejects.toBeInstanceOf(ConflictError);
  });

  it("serializes concurrent request replay and expected-version updates", async () => {
    const harness = await createHarness();
    const duplicate = buildRequest({
      requestId: "publish-concurrent-same-01",
      sourceMaterialId: "material-concurrent-same"
    });
    const duplicateRaw = JSON.stringify(duplicate);
    const duplicates = await Promise.all([
      harness.publishService.publish(
        harness.kid,
        sha256(duplicateRaw),
        duplicate
      ),
      harness.publishService.publish(
        harness.kid,
        sha256(duplicateRaw),
        duplicate
      )
    ]);
    expect(new Set(duplicates.map((item) => item.response.articleId)).size).toBe(
      1
    );
    expect(duplicates.map((item) => item.response.version)).toEqual([1, 1]);
    expect(duplicates.some((item) => item.response.idempotent)).toBe(true);

    const first = buildRequest({
      requestId: "publish-concurrent-race-01",
      sourceMaterialId: "material-concurrent-race"
    });
    const second = buildRequest({
      requestId: "publish-concurrent-race-02",
      sourceMaterialId: "material-concurrent-race",
      title: "并发覆盖尝试"
    });
    const results = await Promise.allSettled([
      harness.publishService.publish(
        harness.kid,
        sha256(JSON.stringify(first)),
        first
      ),
      harness.publishService.publish(
        harness.kid,
        sha256(JSON.stringify(second)),
        second
      )
    ]);
    expect(results.filter((item) => item.status === "fulfilled")).toHaveLength(1);
    const rejected = results.find((item) => item.status === "rejected");
    expect(rejected?.status).toBe("rejected");
    if (rejected?.status === "rejected") {
      expect(rejected.reason).toBeInstanceOf(ConflictError);
    }
  });
});

describe("visibility, rollback, search and deletion", () => {
  it("updates the public search projection transactionally and hides unlisted articles", async () => {
    const harness = await createHarness();
    const annotations = [
      {
        id: "annotation-1",
        quote: "有效设计应降低无关负荷，并为生成性加工留出空间。",
        note: "这条备注应当只在开启公开标注后可搜索。"
      }
    ];
    const aiAppendix = [
      {
        id: "ai-1",
        title: "结构提示",
        body: "AI 附录关键词：三类负荷"
      }
    ];
    const input = buildRequest({
      publishAnnotations: true,
      publishAi: true,
      annotations,
      aiAppendix
    });
    const raw = JSON.stringify(input);
    await authenticate(
      harness,
      "POST",
      "/api/v1/publish",
      raw,
      "nonce-lifecycle-00001"
    );
    const published = await harness.publishService.publish(
      harness.kid,
      sha256(raw),
      input
    );
    expect(await harness.readService.search("这条备注")).toHaveLength(1);
    expect(await harness.readService.search("三类负荷")).toHaveLength(1);

    const versionTwoInput = buildRequest({
      requestId: "publish-request-0202",
      articleId: published.response.articleId,
      expectedVersion: 1,
      title: "更新后的版本",
      bodyHtml:
        "<h2>更新后的章节</h2><p>有效设计应降低无关负荷，并为生成性加工留出空间。</p>",
      publishAnnotations: true,
      publishAi: false,
      annotations
    });
    const versionTwoRaw = JSON.stringify(versionTwoInput);
    await authenticate(
      harness,
      "POST",
      "/api/v1/publish",
      versionTwoRaw,
      "nonce-lifecycle-00002"
    );
    await harness.publishService.publish(
      harness.kid,
      sha256(versionTwoRaw),
      versionTwoInput
    );

    const rollbackBody = {
      requestId: "rollback-request-0001",
      expectedVersion: 2,
      targetVersion: 1
    };
    const rollbackRaw = JSON.stringify(rollbackBody);
    await authenticate(
      harness,
      "POST",
      `/api/v1/articles/${published.response.articleId}/rollback`,
      rollbackRaw,
      "nonce-lifecycle-00003"
    );
    const rolledBack = await harness.publishService.rollback(
      harness.kid,
      published.response.articleId,
      sha256(rollbackRaw),
      rollbackBody
    );
    expect(rolledBack.currentVersion).toBe(1);
    expect((await harness.readService.search("三类负荷")).length).toBe(1);

    const visibility: VisibilityRequest = {
      requestId: "visibility-request-01",
      expectedVersion: 1,
      visibility: "UNLISTED"
    };
    const visibilityRaw = JSON.stringify(visibility);
    await authenticate(
      harness,
      "POST",
      `/api/v1/articles/${published.response.articleId}/visibility`,
      visibilityRaw,
      "nonce-lifecycle-00004"
    );
    await harness.publishService.changeVisibility(
      harness.kid,
      published.response.articleId,
      sha256(visibilityRaw),
      visibility
    );
    expect(await harness.readService.search("这条备注")).toHaveLength(0);
    await expect(
      harness.readService.publicView(published.response.articleId)
    ).rejects.toThrow();
    await expect(
      harness.readService.unlistedView(published.response.unlistedUrl.split("/").at(-1)!)
    ).resolves.toBeTruthy();

    const withdraw = {
      requestId: "withdraw-request-001",
      expectedVersion: 1
    };
    const withdrawRaw = JSON.stringify(withdraw);
    await authenticate(
      harness,
      "POST",
      `/api/v1/articles/${published.response.articleId}/withdraw`,
      withdrawRaw,
      "nonce-lifecycle-00005"
    );
    await harness.publishService.withdraw(
      harness.kid,
      published.response.articleId,
      sha256(withdrawRaw),
      withdraw
    );
    await expect(
      harness.readService.unlistedView(published.response.unlistedUrl.split("/").at(-1)!)
    ).rejects.toThrow();
  });
});

describe("published study layer controls", () => {
  it("defaults private layers off and omits them from the publish request", () => {
    const payload = preparePublishRequest({
      requestId: "preview-request-0001",
      sourceMaterialId: "material-preview",
      expectedVersion: 0,
      visibility: "PUBLIC",
      title: "预览",
      bodyHtml: "<p>正文</p>",
      annotations: [{ id: "a", quote: "正文", note: "私人标注" }],
      aiAppendix: [{ id: "ai", title: "AI", body: "私人结果" }]
    });
    expect(payload.publishAnnotations).toBe(false);
    expect(payload.publishAi).toBe(false);
    expect(payload).not.toHaveProperty("annotations");
    expect(payload).not.toHaveProperty("aiAppendix");
  });

  it("publishes a public highlight without a note", async () => {
    const harness = await createHarness();
    const input = validateContract<PublishRequest>("PublishRequest", {
      requestId: "no-note-publish-request",
      sourceMaterialId: "no-note-material",
      expectedVersion: 0,
      visibility: "PUBLIC",
      title: "无备注高亮",
      bodyHtml: "<p>只需高亮的正文</p>",
      publishAnnotations: true,
      publishAi: false,
      annotations: [
        {
          id: "no-note-annotation",
          quote: "只需高亮的正文",
          blockPath: [0]
        }
      ]
    });
    const raw = JSON.stringify(input);
    await authenticate(
      harness,
      "POST",
      "/api/v1/publish",
      raw,
      "nonce-no-note-publish"
    );
    const published = await harness.publishService.publish(
      harness.kid,
      sha256(raw),
      input
    );
    const view = await harness.readService.publicView(
      published.response.articleId
    );
    expect(view.version.annotations[0]?.note).toBe("");
    expect(view.version.readerHtml).toContain("public-annotation");
  });

  it("rejects private layer arrays when their switches are disabled", async () => {
    const harness = await createHarness();
    const input = buildRequest({
      requestId: "private-layer-0001",
      annotations: [
        {
          id: "a",
          quote: "有效设计应降低无关负荷，并为生成性加工留出空间。",
          note: "不应上传"
        }
      ]
    });
    const raw = JSON.stringify(input);
    await authenticate(
      harness,
      "POST",
      "/api/v1/publish",
      raw,
      "nonce-study-layer-0001"
    );
    await expect(
      harness.publishService.publish(harness.kid, sha256(raw), input)
    ).rejects.toBeInstanceOf(ValidationError);
  });

  it("creates new immutable versions for annotation-only, AI-only and both", async () => {
    const harness = await createHarness();
    const quote = "有效设计应降低无关负荷，并为生成性加工留出空间。";
    let expectedVersion = 0;
    const variants = [
      {
        annotations: [{ id: "a1", quote, note: "仅标注" }],
        aiAppendix: undefined,
        publishAnnotations: true,
        publishAi: false,
        keyword: "仅标注"
      },
      {
        annotations: undefined,
        aiAppendix: [{ id: "ai1", title: "仅 AI", body: "仅 AI 内容" }],
        publishAnnotations: false,
        publishAi: true,
        keyword: "仅 AI 内容"
      },
      {
        annotations: [{ id: "a2", quote, note: "两者同时公开" }],
        aiAppendix: [{ id: "ai2", title: "同时 AI", body: "同时公开附录" }],
        publishAnnotations: true,
        publishAi: true,
        keyword: "同时公开附录"
      }
    ];
    let articleId: string | undefined;
    for (const [index, variant] of variants.entries()) {
      const input = buildRequest({
        requestId: `study-version-request-${index + 1}`,
        articleId,
        expectedVersion,
        publishAnnotations: variant.publishAnnotations,
        publishAi: variant.publishAi,
        annotations: variant.annotations,
        aiAppendix: variant.aiAppendix
      });
      const raw = JSON.stringify(input);
      await authenticate(
        harness,
        "POST",
        "/api/v1/publish",
        raw,
        `nonce-study-version-000${index + 1}`
      );
      const result = await harness.publishService.publish(
        harness.kid,
        sha256(raw),
        input
      );
      articleId = result.response.articleId;
      expectedVersion = result.response.version;
      expect(result.response.version).toBe(index + 1);
      expect(await harness.readService.search(variant.keyword)).toHaveLength(1);
    }
  });
});

describe("private Qiniu-compatible media adapter", () => {
  it("issues scoped credentials, verifies submitted media and signs reads", async () => {
    const harness = await createHarness();
    const bytes = Buffer.from("fake-png-content");
    const contentHash = `sha256:${createHash("sha256").update(bytes).digest("hex")}`;
    const objectKey = "articles/aa/fake-image.png";
    const token = await harness.publishService.createMediaUploadToken({
      objectKey,
      contentHash,
      contentType: "image/png",
      size: bytes.length
    });
    expect(token.token).toContain(objectKey);
    expect(token.expiresAt).toBeTruthy();
    harness.storage.putObject(objectKey, bytes, "image/png");

    const media: MediaReferenceInput = {
      objectKey,
      contentHash,
      contentType: "image/png",
      size: bytes.length,
      reference: "figure-1"
    };
    const input = buildRequest({
      requestId: "media-publish-00001",
      bodyHtml: `<h2>图片</h2><figure><img data-object-key="${objectKey}" alt="示意图"></figure>`,
      mediaRefs: [media]
    });
    const raw = JSON.stringify(input);
    await authenticate(
      harness,
      "POST",
      "/api/v1/publish",
      raw,
      "nonce-media-publish-01"
    );
    const published = await harness.publishService.publish(
      harness.kid,
      sha256(raw),
      input
    );
    const view = await harness.readService.publicView(
      published.response.articleId
    );
    expect(view.version.media).toHaveLength(1);
    const mediaUrl = await harness.readService.mediaUrl(
      { type: "public", articleId: published.response.articleId },
      view.version.media[0]!.mediaId,
      300
    );
    expect(mediaUrl).toContain("memory://media/");
  });

  it("fails publication on hash mismatch instead of rendering a broken image", async () => {
    const harness = await createHarness();
    const bytes = Buffer.from("media-bytes");
    const objectKey = "articles/bb/mismatch.png";
    await harness.publishService.createMediaUploadToken({
      objectKey,
      contentHash: `sha256:${"0".repeat(64)}`,
      contentType: "image/png",
      size: bytes.length
    });
    harness.storage.putObject(objectKey, bytes, "image/png");
    const input = buildRequest({
      requestId: "media-mismatch-0001",
      bodyHtml: `<img data-object-key="${objectKey}" alt="错误媒体">`,
      mediaRefs: [
        {
          objectKey,
          contentHash: `sha256:${"0".repeat(64)}`,
          contentType: "image/png",
          size: bytes.length,
          reference: "image-1"
        }
      ]
    });
    const raw = JSON.stringify(input);
    await authenticate(
      harness,
      "POST",
      "/api/v1/publish",
      raw,
      "nonce-media-mismatch1"
    );
    await expect(
      harness.publishService.publish(harness.kid, sha256(raw), input)
    ).rejects.toBeInstanceOf(ExternalServiceError);
  });

  it("retries cleanup and removes media not referenced by another article", async () => {
    const harness = await createHarness();
    const flaky = new FlakyStorageAdapter();
    const service = new PublishService(harness.repository, flaky, {
      baseUrl: "http://127.0.0.1:8090",
      mediaUrlTtlSeconds: 300
    });
    const bytes = Buffer.from("cleanup-bytes");
    const contentHash = `sha256:${createHash("sha256").update(bytes).digest("hex")}`;
    const objectKey = "articles/cc/cleanup.png";
    await service.createMediaUploadToken({
      objectKey,
      contentHash,
      contentType: "image/png",
      size: bytes.length
    });
    flaky.putObject(objectKey, bytes, "image/png");
    const input = buildRequest({
      requestId: "media-cleanup-publish",
      sourceMaterialId: "material-cleanup",
      bodyHtml: `<img data-object-key="${objectKey}" alt="待清理媒体">`,
      mediaRefs: [
        {
          objectKey,
          contentHash,
          contentType: "image/png",
          size: bytes.length,
          reference: "image-cleanup"
        }
      ]
    });
    const raw = JSON.stringify(input);
    await authenticate(
      harness,
      "POST",
      "/api/v1/publish",
      raw,
      "nonce-media-cleanup01"
    );
    const published = await service.publish(harness.kid, sha256(raw), input);
    const deleteBody = {
      requestId: "media-delete-request",
      expectedVersion: 1
    };
    const deleteRaw = JSON.stringify(deleteBody);
    await service.deleteArticle(
      harness.kid,
      published.response.articleId,
      sha256(deleteRaw),
      deleteBody
    );
    expect(flaky.deleteAttempts).toBe(1);
    expect(harness.repository.pendingMediaCleanupCount()).toBe(1);
    expect(flaky.hasObject(objectKey)).toBe(true);
    expect(await harness.repository.getMediaAssetByObjectKey(objectKey)).toBeNull();

    const repeated = await service.deleteArticle(
      harness.kid,
      published.response.articleId,
      sha256(deleteRaw),
      deleteBody
    );
    expect(repeated).toEqual({
      articleId: published.response.articleId,
      deleted: true
    });
    expect(flaky.deleteAttempts).toBe(2);
    expect(flaky.hasObject(objectKey)).toBe(false);
    expect(harness.repository.pendingMediaCleanupCount()).toBe(0);
  });

  it("keeps shared media alive when one referencing article is deleted", async () => {
    const harness = await createHarness();
    const bytes = Buffer.from("shared-media");
    const contentHash = `sha256:${createHash("sha256").update(bytes).digest("hex")}`;
    const objectKey = "articles/shared/image.png";
    await harness.publishService.createMediaUploadToken({
      objectKey,
      contentHash,
      contentType: "image/png",
      size: bytes.length
    });
    harness.storage.putObject(objectKey, bytes, "image/png");
    const ref = {
      objectKey,
      contentHash,
      contentType: "image/png",
      size: bytes.length,
      reference: "shared"
    };
    const first = buildRequest({
      requestId: "shared-media-first-01",
      sourceMaterialId: "shared-media-first",
      bodyHtml: `<img data-object-key="${objectKey}" alt="共享图片">`,
      mediaRefs: [ref]
    });
    const second = buildRequest({
      requestId: "shared-media-second-1",
      sourceMaterialId: "shared-media-second",
      bodyHtml: `<img data-object-key="${objectKey}" alt="共享图片">`,
      mediaRefs: [ref]
    });
    const firstPublished = await harness.publishService.publish(
      harness.kid,
      sha256(JSON.stringify(first)),
      first
    );
    const secondPublished = await harness.publishService.publish(
      harness.kid,
      sha256(JSON.stringify(second)),
      second
    );
    const deleteBody = {
      requestId: "shared-media-delete-1",
      expectedVersion: 1
    };
    await harness.publishService.deleteArticle(
      harness.kid,
      firstPublished.response.articleId,
      sha256(JSON.stringify(deleteBody)),
      deleteBody
    );

    expect(harness.repository.pendingMediaCleanupCount()).toBe(0);
    expect(harness.storage.hasObject(objectKey)).toBe(true);
    const view = await harness.readService.publicView(
      secondPublished.response.articleId
    );
    expect(view.version.media[0]?.objectKey).toBe(objectKey);
  });
});

describe("safe HTML and annotations", () => {
  it("removes scripts and anchors public annotations near matching text", () => {
    const result = buildReaderContent(
      `<h2>标题</h2><p>需要高亮的关键句。</p><script>alert(1)</script><img src="https://evil.test/x.png">`,
      [
        {
          id: "a-1",
          quote: "需要高亮的关键句。",
          note: "公开备注"
        }
      ]
    );
    expect(result.readerHtml).not.toContain("<script");
    expect(result.readerHtml).not.toContain("evil.test");
    expect(result.readerHtml).toContain("has-public-annotation");
    expect(result.readerHtml).toContain("公开备注");
    expect(result.toc[0]?.text).toBe("标题");
  });

  it("uses block paths for duplicate quotes and rejects ambiguous fallback", () => {
    const body = `<p>重复引文</p><p>中间段落</p><p>重复引文</p>`;
    expect(() =>
      buildReaderContent(body, [
        { id: "duplicate", quote: "重复引文", note: "" }
      ])
    ).toThrow(ValidationError);

    const result = buildReaderContent(body, [
      {
        id: "second-block",
        quote: "重复引文",
        note: "",
        blockPath: [2]
      }
    ]);
    expect(result.readerHtml.indexOf("public-annotation")).toBeGreaterThan(
      result.readerHtml.indexOf("中间段落")
    );
    expect(() =>
      buildReaderContent(body, [
        {
          id: "wrong-block",
          quote: "重复引文",
          note: "",
          blockPath: [1]
        }
      ])
    ).toThrow(ValidationError);
  });

  it("keeps only canonical data-object-key media markers", () => {
    const result = buildReaderContent(
      `<img data-object-key="canonical.png" alt="canonical"><img data-media-key="legacy.png" alt="legacy">`,
      []
    );
    expect(result.bodyHtml).toContain('data-object-key="canonical.png"');
    expect(result.bodyHtml).not.toContain("data-media-key");
    expect((result.readerHtml.match(/<img/g) ?? []).length).toBe(1);
  });
});

class FlakyStorageAdapter extends MemoryStorageAdapter {
  deleteAttempts = 0;

  override async deleteObject(objectKey: string): Promise<void> {
    this.deleteAttempts += 1;
    if (this.deleteAttempts === 1) {
      throw new ExternalServiceError("模拟第一次删除失败");
    }
    await super.deleteObject(objectKey);
  }
}
