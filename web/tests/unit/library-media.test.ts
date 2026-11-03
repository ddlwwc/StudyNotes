import { createHash } from "node:crypto";
import { describe, expect, it } from "vitest";
import { AuthenticationError, ConflictError } from "@/domain/errors";
import { LibraryMediaService } from "@/lib/services/library-media-service";
import { PublishService } from "@/lib/services/publish-service";
import { ReadService } from "@/lib/services/read-service";
import { MediaBearerAuthenticator } from "@/lib/media-auth";
import { rewriteMediaReferences } from "@/lib/html";
import { MemoryRepository } from "@/lib/repository/memory";
import { MemoryStorageAdapter } from "@/lib/storage/memory";
import { getContractDocument } from "@/lib/contract";

const LIBRARY_MEDIA_KEY = "library-media-key-0123456789abcdef";

function sha256(value: string | Buffer): string {
  return `sha256:${createHash("sha256").update(value).digest("hex")}`;
}

function createHarness() {
  const repository = new MemoryRepository();
  const storage = new MemoryStorageAdapter();
  const service = new LibraryMediaService(repository, storage, {
    baseUrl: "http://127.0.0.1:8090",
    mediaUrlTtlSeconds: 300,
    cleanupDelaySeconds: 0,
    qiniu: {
      bucket: "studynotes-test",
      domain: "https://media.example.test",
      uploadUrl: "https://upload.example.test"
    }
  });
  return { repository, storage, service };
}

describe("library media Bearer authentication", () => {
  it("accepts only the configured key while storing just its hash", async () => {
    const authenticator = new MediaBearerAuthenticator({
      keyHash: sha256(LIBRARY_MEDIA_KEY)
    });

    await expect(
      authenticator.authenticate(
        new Request("https://example.test/api/v1/library-media/status")
      )
    ).rejects.toBeInstanceOf(AuthenticationError);
    await expect(
      authenticator.authenticate(
        new Request("https://example.test/api/v1/library-media/status", {
          headers: { authorization: "Bearer wrong-library-media-key-0000" }
        })
      )
    ).rejects.toBeInstanceOf(AuthenticationError);
    await expect(
      authenticator.authenticate(
        new Request("https://example.test/api/v1/library-media/status", {
          headers: { authorization: `Bearer ${LIBRARY_MEDIA_KEY}` }
        })
      )
    ).resolves.toBeUndefined();
    expect(sha256(LIBRARY_MEDIA_KEY)).not.toContain(LIBRARY_MEDIA_KEY);
  });

  it("publishes all note-media routes as Bearer HTTP contracts", () => {
    const contract = getContractDocument<{
      paths: Record<string, unknown>;
      components: {
        securitySchemes: Record<string, unknown>;
      };
    }>();
    expect(Object.keys(contract.paths)).toEqual(
      expect.arrayContaining([
        "/api/v1/library-media/status",
        "/api/v1/library-media/upload-token",
        "/api/v1/library-media/complete",
        "/api/v1/library-media/read-url",
        "/api/v1/library-media/scan",
        "/api/v1/library-media/cleanup",
        "/api/v1/library-media/cleanup-candidates",
        "/api/v1/library-media/publish-preview"
      ])
    );
    expect(contract.components.securitySchemes).toHaveProperty(
      "LibraryMediaBearer"
    );
  });
});

describe("library media upload lifecycle", () => {
  it("issues a content-addressed credential and reports duplicate content", async () => {
    const { service } = createHarness();
    const bytes = Buffer.from("library-media-bytes");
    const contentHash = sha256(bytes);

    const first = await service.createUploadToken({
      contentHash,
      contentType: "image/png",
      size: bytes.length
    });
    const second = await service.createUploadToken({
      contentHash,
      contentType: "image/png",
      size: bytes.length
    });

    expect(first.objectKey).toBe(
      `library-media/${contentHash.slice("sha256:".length)}.png`
    );
    expect(first.alreadyExists).toBe(false);
    expect(second.objectKey).toBe(first.objectKey);
    expect(second.alreadyExists).toBe(true);
    await expect(
      service.createUploadToken({
        contentHash,
        contentType: "application/pdf",
        size: bytes.length
      })
    ).rejects.toThrow("同一内容");
  });

  it("marks media ready only after storage verification and then returns a read URL", async () => {
    const { service, storage } = createHarness();
    const bytes = Buffer.from("verified-library-media");
    const contentHash = sha256(bytes);
    const upload = await service.createUploadToken({
      contentHash,
      contentType: "image/png",
      size: bytes.length
    });
    storage.putObject(upload.objectKey, bytes, "image/png");

    await expect(
      service.completeUpload({ objectKey: upload.objectKey })
    ).resolves.toEqual({
      objectKey: upload.objectKey,
      status: "READY",
      contentHash,
      contentType: "image/png",
      size: bytes.length
    });
    const read = await service.createReadUrl({ objectKey: upload.objectKey });
    expect(read.url).toContain("memory://media/");
    expect(read.expiresAt).toBeTruthy();
  });

  it("rejects completion when bytes or content type do not match the credential", async () => {
    const { service, storage } = createHarness();
    const bytes = Buffer.from("actual-library-media");
    const contentHash = sha256(bytes);
    const upload = await service.createUploadToken({
      contentHash,
      contentType: "image/png",
      size: bytes.length
    });
    storage.putObject(upload.objectKey, bytes, "application/pdf");
    await expect(
      service.completeUpload({ objectKey: upload.objectKey })
    ).rejects.toThrow("笔记媒体类型不匹配");
  });
});

describe("library media publish preview", () => {
  it("blocks pending and missing media and unlocks only after verification", async () => {
    const { service, storage } = createHarness();
    const bytes = Buffer.from("preview-library-media");
    const contentHash = sha256(bytes);
    const upload = await service.createUploadToken({
      contentHash,
      contentType: "image/png",
      size: bytes.length
    });
    const input = {
      bodyHtml: `<figure><img data-object-key="${upload.objectKey}" alt="预览"></figure>`,
      mediaRefs: [
        {
          objectKey: upload.objectKey,
          contentHash,
          contentType: "image/png",
          size: bytes.length,
          reference: "figure-preview"
        }
      ]
    };

    await expect(service.publishPreview(input)).resolves.toMatchObject({
      ready: false,
      media: [expect.objectContaining({ status: "PENDING" })]
    });
    storage.putObject(upload.objectKey, bytes, "image/png");
    await service.completeUpload({ objectKey: upload.objectKey });
    await expect(service.publishPreview(input)).resolves.toMatchObject({
      ready: true,
      media: [expect.objectContaining({ status: "READY" })]
    });
    await expect(
      service.publishPreview({
        bodyHtml: '<img data-object-key="library-media/missing.png" alt="缺失">',
        mediaRefs: [
          {
            objectKey: "library-media/missing.png",
            contentHash: sha256("missing"),
            contentType: "image/png",
            size: 7,
            reference: "missing-image"
          }
        ]
      })
    ).resolves.toMatchObject({
      ready: false,
      media: [expect.objectContaining({ status: "MISSING" })]
    });
  });
});

describe("library media references and delayed cleanup", () => {
  it("protects current and historical references until a confirmed rescan removes them", async () => {
    const { service, storage } = createHarness();
    const currentBytes = Buffer.from("current-reference-media");
    const historyBytes = Buffer.from("history-reference-media");
    const current = await uploadAndComplete(service, storage, currentBytes);
    const history = await uploadAndComplete(service, storage, historyBytes);

    const scan = await service.scanReferences({
      sourceId: "note-001",
      references: [
        {
          scope: "CURRENT",
          objectKey: current.objectKey,
          reference: `media://qiniu/${current.objectKey}`
        },
        {
          scope: "HISTORY",
          objectKey: history.objectKey,
          reference: `media://qiniu/${history.objectKey}`
        }
      ],
      historicalLocalMedia: [
        { reference: "source/media/old.png", size: 4096 }
      ]
    });
    expect(scan.summary).toMatchObject({
      currentCount: 1,
      historyCount: 1,
      missingCount: 0,
      historicalLocalCount: 1,
      historicalLocalSize: 4096
    });

    const protectedCleanup = await service.requestCleanup({
      objectKeys: [current.objectKey, history.objectKey],
      confirmed: true
    });
    expect(protectedCleanup.skipped).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          objectKey: current.objectKey,
          reason: "REFERENCED"
        }),
        expect.objectContaining({
          objectKey: history.objectKey,
          reason: "REFERENCED"
        })
      ])
    );
    expect(storage.hasObject(current.objectKey)).toBe(true);
    expect(storage.hasObject(history.objectKey)).toBe(true);

    await service.scanReferences({
      sourceId: "note-001",
      references: [
        {
          scope: "HISTORY",
          objectKey: history.objectKey,
          reference: `media://qiniu/${history.objectKey}`
        }
      ]
    });
    const cleanup = await service.requestCleanup({
      objectKeys: [current.objectKey],
      confirmed: true
    });
    expect(cleanup.queued).toEqual([
      expect.objectContaining({ objectKey: current.objectKey })
    ]);
    expect(storage.hasObject(current.objectKey)).toBe(false);
    expect(storage.hasObject(history.objectKey)).toBe(true);
    await expect(
      service.createReadUrl({ objectKey: current.objectKey })
    ).rejects.toThrow();
  });

  it("keeps a failed cleanup job retryable without removing registration", async () => {
    const repository = new MemoryRepository();
    const storage = new FlakyLibraryStorage();
    const service = new LibraryMediaService(repository, storage, {
      baseUrl: "http://127.0.0.1:8090",
      mediaUrlTtlSeconds: 300,
      cleanupDelaySeconds: 0,
      qiniu: {
        bucket: "studynotes-test",
        domain: "https://media.example.test",
        uploadUrl: "https://upload.example.test"
      }
    });
    const bytes = Buffer.from("failed-cleanup-media");
    const upload = await uploadAndComplete(service, storage, bytes);
    await service.scanReferences({
      sourceId: "retry-note",
      references: []
    });

    storage.failNextDelete = true;
    await service.requestCleanup({
      objectKeys: [upload.objectKey],
      confirmed: true
    });
    expect(storage.hasObject(upload.objectKey)).toBe(true);
    expect(
      (await repository.getLibraryMediaAssetByObjectKey(upload.objectKey))
        ?.status
    ).toBe("DELETING");
    await expect(
      service.scanReferences({
        sourceId: "retry-note",
        references: [
          {
            scope: "CURRENT",
            objectKey: upload.objectKey,
            reference: `media://qiniu/${upload.objectKey}`
          }
        ]
      })
    ).rejects.toBeInstanceOf(ConflictError);
    expect(
      await repository.getLibraryMediaAssetByObjectKey(upload.objectKey)
    ).not.toBeNull();

    storage.failNextDelete = false;
    await service.requestCleanup({
      objectKeys: [upload.objectKey],
      confirmed: true
    });
    expect(storage.hasObject(upload.objectKey)).toBe(false);
    expect(
      await repository.getLibraryMediaAssetByObjectKey(upload.objectKey)
    ).toBeNull();
  });

  it("lists cloud media that no current or historical scan references", async () => {
    const { service, storage } = createHarness();
    const referenced = await uploadAndComplete(
      service,
      storage,
      Buffer.from("referenced-candidate")
    );
    const orphan = await uploadAndComplete(
      service,
      storage,
      Buffer.from("orphan-candidate")
    );
    await service.scanReferences({
      sourceId: "candidate-note",
      references: [
        {
          scope: "HISTORY",
          objectKey: referenced.objectKey,
          reference: `media://qiniu/${referenced.objectKey}`
        }
      ]
    });

    await expect(service.cleanupCandidates()).resolves.toMatchObject({
      summary: {
        count: 1,
        totalSize: Buffer.byteLength("orphan-candidate")
      },
      media: [
        expect.objectContaining({
          objectKey: orphan.objectKey,
          status: "READY"
        })
      ]
    });
  });
});

describe("published media namespace isolation", () => {
  it("blocks publication until every library reference is ready", async () => {
    const { repository, storage, service } = createHarness();
    const publishService = new PublishService(repository, storage, {
      baseUrl: "http://127.0.0.1:8090",
      mediaUrlTtlSeconds: 300
    });
    const bytes = Buffer.from("pending-publish-media");
    const contentHash = sha256(bytes);
    const upload = await service.createUploadToken({
      contentHash,
      contentType: "image/png",
      size: bytes.length
    });
    storage.putObject(upload.objectKey, bytes, "image/png");
    const input = publishRequest({
      bodyHtml: `<img data-object-key="${upload.objectKey}" alt="未就绪">`,
      mediaRefs: [
        {
          objectKey: upload.objectKey,
          contentHash,
          contentType: "image/png",
          size: bytes.length,
          reference: `media://qiniu/${upload.objectKey}`
        }
      ]
    });

    await expect(
      publishService.publish("test-key", sha256(JSON.stringify(input)), input)
    ).rejects.toMatchObject({
      status: 422,
      details: {
        media: [
          {
            objectKey: upload.objectKey,
            status: "PENDING"
          }
        ]
      }
    });
  });

  it("copies ready library media and survives source-note cleanup", async () => {
    const { repository, storage, service } = createHarness();
    const publishService = new PublishService(repository, storage, {
      baseUrl: "http://127.0.0.1:8090",
      mediaUrlTtlSeconds: 300
    });
    const readService = new ReadService(repository, storage);
    const bytes = Buffer.from("published-namespace-media");
    const contentHash = sha256(bytes);
    const upload = await uploadAndComplete(service, storage, bytes);
    const input = publishRequest({
      bodyHtml: `<figure><img data-object-key="${upload.objectKey}" alt="已发布"></figure>`,
      mediaRefs: [
        {
          objectKey: upload.objectKey,
          contentHash,
          contentType: "image/png",
          size: bytes.length,
          reference: `media://qiniu/${upload.objectKey}`
        }
      ]
    });

    const published = await publishService.publish(
      "test-key",
      sha256(JSON.stringify(input)),
      input
    );
    const view = await readService.publicView(published.response.articleId);
    expect(view.version.media).toHaveLength(1);
    expect(view.version.media[0]?.objectKey).toMatch(/^published-media\//);
    expect(view.version.media[0]?.objectKey).not.toBe(upload.objectKey);
    expect(storage.hasObject(upload.objectKey)).toBe(true);
    expect(storage.hasObject(view.version.media[0]!.objectKey)).toBe(true);

    await service.scanReferences({
      sourceId: "note-cleanup-isolation",
      references: []
    });
    await service.requestCleanup({
      objectKeys: [upload.objectKey],
      confirmed: true
    });

    expect(storage.hasObject(upload.objectKey)).toBe(false);
    expect(storage.hasObject(view.version.media[0]!.objectKey)).toBe(true);
    const stillPublished = await readService.publicView(
      published.response.articleId
    );
    expect(stillPublished.version.media[0]?.objectKey).toBe(
      view.version.media[0]?.objectKey
    );
    const replay = await publishService.publish(
      "test-key",
      sha256(JSON.stringify(input)),
      input
    );
    expect(replay.status).toBe(200);
    expect(replay.response).toMatchObject({
      articleId: published.response.articleId,
      idempotent: true,
      version: 1
    });
    await expect(
      publishService.createMediaUploadToken({
        objectKey: upload.objectKey,
        contentHash,
        contentType: "image/png",
        size: bytes.length
      })
    ).rejects.toThrow("articles/");
  });

  it("rewrites stable attachment references into published media links", async () => {
    const { repository, storage, service } = createHarness();
    const publishService = new PublishService(repository, storage, {
      baseUrl: "http://127.0.0.1:8090",
      mediaUrlTtlSeconds: 300
    });
    const bytes = Buffer.from("library-attachment");
    const contentHash = sha256(bytes);
    const upload = await service.createUploadToken({
      contentHash,
      contentType: "application/pdf",
      size: bytes.length
    });
    storage.putObject(upload.objectKey, bytes, "application/pdf");
    await service.completeUpload({ objectKey: upload.objectKey });
    const input = publishRequest({
      bodyHtml: `<p><a href="media://qiniu/${upload.objectKey}">学习附件</a></p>`,
      mediaRefs: [
        {
          objectKey: upload.objectKey,
          contentHash,
          contentType: "application/pdf",
          size: bytes.length,
          reference: `media://qiniu/${upload.objectKey}`
        }
      ]
    });
    const published = await publishService.publish(
      "test-key",
      sha256(JSON.stringify(input)),
      input
    );
    const view = await repository.getArticleView(
      (await repository.getArticleByPublicId(published.response.articleId))!
    );
    const reader = rewriteMediaReferences(
      view!.version.readerHtml,
      view!.version.media,
      `/a/${published.response.articleId}`
    );
    expect(view!.version.media[0]?.objectKey).toMatch(/^published-media\//);
    expect(reader).toContain(
      `/a/${published.response.articleId}/media/${view!.version.media[0]!.mediaId}`
    );
    expect(reader).toContain("学习附件");
  });
});

async function uploadAndComplete(
  service: LibraryMediaService,
  storage: MemoryStorageAdapter,
  bytes: Buffer
) {
  const contentHash = sha256(bytes);
  const upload = await service.createUploadToken({
    contentHash,
    contentType: "image/png",
    size: bytes.length
  });
  storage.putObject(upload.objectKey, bytes, "image/png");
  await service.completeUpload({ objectKey: upload.objectKey });
  return upload;
}

function publishRequest(
  overrides: Partial<Parameters<PublishService["publish"]>[2]> = {}
) {
  return {
    requestId: `library-publish-${crypto.randomUUID()}`,
    sourceMaterialId: `library-publish-${crypto.randomUUID()}`,
    sourceVersionId: "library-version-1",
    expectedVersion: 0,
    visibility: "PUBLIC" as const,
    title: "笔记媒体发布",
    summary: "",
    bodyHtml: "<p>正文</p>",
    tags: [],
    publishAnnotations: false,
    publishAi: false,
    ...overrides
  };
}

class FlakyLibraryStorage extends MemoryStorageAdapter {
  failNextDelete = false;

  override async deleteObject(objectKey: string): Promise<void> {
    if (this.failNextDelete) {
      this.failNextDelete = false;
      throw new Error("模拟七牛删除失败");
    }
    await super.deleteObject(objectKey);
  }
}
