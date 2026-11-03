import { createHash, generateKeyPairSync } from "node:crypto";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import mysql from "mysql2/promise";
import type { PublishRequest } from "@/lib/api-types";
import { ConflictError } from "@/domain/errors";
import { MySqlRepository } from "@/lib/repository/mysql";
import { PublishService } from "@/lib/services/publish-service";
import { MemoryStorageAdapter } from "@/lib/storage/memory";

const databaseUrl = process.env.DATABASE_URL;
const integrationEnabled =
  process.env.MYSQL_INTEGRATION_TESTS === "1" && Boolean(databaseUrl);

describe.skipIf(!integrationEnabled)("MySQL publish hardening", () => {
  const kid = "mysql-integration-publish-key";
  const pool = mysql.createPool({
    uri: databaseUrl ?? "mysql://127.0.0.1:3306/studynotes",
    connectionLimit: 4,
    timezone: "Z"
  });
  let repository: MySqlRepository;
  let storage: VerifyingStorage;
  let service: PublishService;

  beforeAll(async () => {
    repository = new MySqlRepository(databaseUrl!);
    expect(await repository.health()).toBe(true);
    await resetDatabase(pool);
    const { publicKey } = generateKeyPairSync("ed25519");
    const publicJwk = publicKey.export({ format: "jwk" }) as JsonWebKey;
    await serviceFor(new MemoryStorageAdapter()).registerKey({
      kid,
      publicKeyJwk: {
        kty: "OKP",
        crv: "Ed25519",
        x: publicJwk.x!
      }
    });
  });

  afterAll(async () => {
    await repository.close();
    await pool.end();
  });

  it("serializes request replay and expectedVersion without unique-key races", async () => {
    service = serviceFor(new MemoryStorageAdapter());
    const duplicate = request({
      requestId: "mysql-concurrent-same-request",
      sourceMaterialId: "mysql-concurrent-same-material"
    });
    const raw = JSON.stringify(duplicate);
    const duplicates = await Promise.all([
      service.publish(kid, hash(raw), duplicate),
      service.publish(kid, hash(raw), duplicate)
    ]);
    expect(new Set(duplicates.map((item) => item.response.articleId)).size).toBe(
      1
    );
    expect(duplicates.map((item) => item.response.version)).toEqual([1, 1]);
    expect(duplicates.some((item) => item.response.idempotent)).toBe(true);

    const base = request({
      requestId: "mysql-version-base-request",
      sourceMaterialId: "mysql-version-race-material"
    });
    const first = await service.publish(
      kid,
      hash(JSON.stringify(base)),
      base
    );
    const updates = [
      request({
        requestId: "mysql-version-race-first",
        articleId: first.response.articleId,
        sourceMaterialId: "mysql-version-race-material",
        expectedVersion: 1,
        bodyHtml: "<p>并发版本 A</p>"
      }),
      request({
        requestId: "mysql-version-race-second",
        articleId: first.response.articleId,
        sourceMaterialId: "mysql-version-race-material",
        expectedVersion: 1,
        bodyHtml: "<p>并发版本 B</p>"
      })
    ];
    const results = await Promise.allSettled(
      updates.map((input) =>
        service.publish(kid, hash(JSON.stringify(input)), input)
      )
    );
    expect(results.filter((item) => item.status === "fulfilled")).toHaveLength(1);
    const rejected = results.find((item) => item.status === "rejected");
    expect(rejected?.status).toBe("rejected");
    if (rejected?.status === "rejected") {
      expect(rejected.reason).toBeInstanceOf(ConflictError);
    }

    const article = await repository.getArticleByPublicId(
      first.response.articleId
    );
    expect(article).not.toBeNull();
    expect(await repository.getVersion(article!.id, 2)).not.toBeNull();
    expect(await repository.getVersion(article!.id, 3)).toBeNull();
  });

  it("commits deletion before object cleanup, keeps shared media and retries failures", async () => {
    storage = new VerifyingStorage(pool);
    service = serviceFor(storage);
    const bytes = Buffer.from("mysql-cleanup-media");
    const contentHash = hash(bytes);
    const objectKey = "articles/mysql/cleanup.png";
    await service.createMediaUploadToken({
      objectKey,
      contentHash,
      contentType: "image/png",
      size: bytes.length
    });
    storage.putObject(objectKey, bytes, "image/png");
    const mediaRef = {
      objectKey,
      contentHash,
      contentType: "image/png",
      size: bytes.length,
      reference: "shared-image"
    };
    const firstInput = request({
      requestId: "mysql-shared-first-request",
      sourceMaterialId: "mysql-shared-first-material",
      bodyHtml: `<img data-object-key="${objectKey}" alt="shared">`,
      mediaRefs: [mediaRef]
    });
    const secondInput = request({
      requestId: "mysql-shared-second-request",
      sourceMaterialId: "mysql-shared-second-material",
      bodyHtml: `<img data-object-key="${objectKey}" alt="shared">`,
      mediaRefs: [mediaRef]
    });
    const first = await service.publish(
      kid,
      hash(JSON.stringify(firstInput)),
      firstInput
    );
    const second = await service.publish(
      kid,
      hash(JSON.stringify(secondInput)),
      secondInput
    );
    const firstRowId = (
      await repository.getArticleByPublicId(first.response.articleId)
    )!.id;
    const secondRowId = (
      await repository.getArticleByPublicId(second.response.articleId)
    )!.id;

    await service.deleteArticle(
      kid,
      first.response.articleId,
      hash(JSON.stringify({
        requestId: "mysql-delete-first-request",
        expectedVersion: 1
      })),
      {
        requestId: "mysql-delete-first-request",
        expectedVersion: 1
      }
    );
    expect(storage.deleteCalls).toBe(0);
    expect(storage.hasObject(objectKey)).toBe(true);
    expect(await cleanupJobCount(pool)).toBe(0);
    expect(await repository.getArticleByPublicId(second.response.articleId)).not.toBeNull();
    expect(
      await articleRowCount(pool, first.response.articleId, firstRowId)
    ).toEqual({
      articles: 0,
      versions: 0,
      search: 0
    });

    storage.failDelete = true;
    storage.expectedDeletedArticleId = second.response.articleId;
    await service.deleteArticle(
      kid,
      second.response.articleId,
      hash(JSON.stringify({
        requestId: "mysql-delete-second-request",
        expectedVersion: 1
      })),
      {
        requestId: "mysql-delete-second-request",
        expectedVersion: 1
      }
    );
    expect(storage.deleteCalls).toBe(1);
    expect(storage.hasObject(objectKey)).toBe(true);
    expect(await cleanupJobCount(pool)).toBe(1);
    expect(await cleanupJobStatus(pool)).toBe("FAILED");
    expect(
      await articleRowCount(pool, second.response.articleId, secondRowId)
    ).toEqual({
      articles: 0,
      versions: 0,
      search: 0
    });

    storage.failDelete = false;
    await service.deleteArticle(
      kid,
      second.response.articleId,
      hash(JSON.stringify({
        requestId: "mysql-delete-second-request",
        expectedVersion: 1
      })),
      {
        requestId: "mysql-delete-second-request",
        expectedVersion: 1
      }
    );
    expect(storage.deleteCalls).toBe(2);
    expect(storage.hasObject(objectKey)).toBe(false);
    expect(await cleanupJobCount(pool)).toBe(0);
  });

  function serviceFor(adapter: MemoryStorageAdapter) {
    return new PublishService(repository, adapter, {
      baseUrl: "http://127.0.0.1:8090",
      mediaUrlTtlSeconds: 300
    });
  }
});

class VerifyingStorage extends MemoryStorageAdapter {
  failDelete = false;
  deleteCalls = 0;
  expectedDeletedArticleId = "";

  constructor(private readonly pool: mysql.Pool) {
    super();
  }

  override async deleteObject(objectKey: string): Promise<void> {
    this.deleteCalls += 1;
    const [rows] = await this.pool.query<mysql.RowDataPacket[]>(
      "SELECT COUNT(*) AS count FROM articles WHERE article_id = ?",
      [this.expectedDeletedArticleId]
    );
    if (Number(rows[0]?.count ?? 0) !== 0) {
      throw new Error("对象清理发生在数据库事务提交前");
    }
    if (this.failDelete) {
      throw new Error("模拟七牛对象删除失败");
    }
    await super.deleteObject(objectKey);
  }
}

function request(overrides: Partial<PublishRequest>): PublishRequest {
  return {
    requestId: "mysql-default-request",
    sourceMaterialId: "mysql-default-material",
    sourceVersionId: null,
    expectedVersion: 0,
    visibility: "PUBLIC",
    title: "MySQL 硬化测试",
    summary: "",
    bodyHtml: "<p>正文</p>",
    tags: [],
    publishAnnotations: false,
    publishAi: false,
    ...overrides
  };
}

function hash(value: string | Buffer): string {
  return `sha256:${createHash("sha256").update(value).digest("hex")}`;
}

async function resetDatabase(pool: mysql.Pool) {
  const tables = [
    "media_cleanup_jobs",
    "publish_locks",
    "article_search",
    "article_version_media",
    "article_versions",
    "publish_requests",
    "articles",
    "media_assets",
    "request_nonces",
    "publish_keys"
  ];
  await pool.query("SET FOREIGN_KEY_CHECKS = 0");
  try {
    for (const table of tables) {
      await pool.query(`TRUNCATE TABLE \`${table}\``);
    }
  } finally {
    await pool.query("SET FOREIGN_KEY_CHECKS = 1");
  }
}

async function cleanupJobCount(pool: mysql.Pool): Promise<number> {
  const [rows] = await pool.query<mysql.RowDataPacket[]>(
    "SELECT COUNT(*) AS count FROM media_cleanup_jobs"
  );
  return Number(rows[0]?.count ?? 0);
}

async function cleanupJobStatus(pool: mysql.Pool): Promise<string | null> {
  const [rows] = await pool.query<mysql.RowDataPacket[]>(
    "SELECT status FROM media_cleanup_jobs LIMIT 1"
  );
  return (rows[0]?.status as string | undefined) ?? null;
}

async function articleRowCount(
  pool: mysql.Pool,
  articleId: string,
  articleRowId: string
) {
  const [rows] = await pool.query<mysql.RowDataPacket[]>(
    `SELECT
      (SELECT COUNT(*) FROM articles WHERE article_id = ?) AS articles,
      (SELECT COUNT(*) FROM article_versions
        WHERE article_row_id = ?) AS versions,
      (SELECT COUNT(*) FROM article_search
        WHERE article_row_id = ?) AS search`,
    [articleId, articleRowId, articleRowId]
  );
  const row = rows[0];
  return {
    articles: Number(row?.articles ?? 0),
    versions: Number(row?.versions ?? 0),
    search: Number(row?.search ?? 0)
  };
}
