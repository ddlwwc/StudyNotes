import {
  and,
  desc,
  eq,
  inArray,
  lt,
  or,
  sql
} from "drizzle-orm";
import type {
  ArticleRow,
  ArticleVersionRow,
  MediaAssetRow,
  MediaCleanupJobRow,
  PublishKeyRow
} from "@/db/schema";
import {
  articleSearch,
  articles,
  articleVersionMedia,
  articleVersions,
  mediaCleanupJobs,
  mediaAssets,
  publishKeys,
  publishLocks,
  publishRequests,
  requestNonces
} from "@/db/schema";
import {
  ConflictError,
  IdempotencyMismatchError,
  NotFoundError,
  ValidationError
} from "@/domain/errors";
import type {
  ArticleRecord,
  ArticleSummary,
  ArticleVersionRecord,
  AtomicPublishInput,
  DeleteInput,
  DeleteOutcome,
  MediaAsset,
  MediaCleanupJob,
  PublishKey,
  PublishOutcome,
  PublishRepository,
  PublishStatus,
  RollbackInput,
  RollbackOutcome,
  VersionMedia,
  VisibilityInput,
  VisibilityOutcome
} from "@/domain/types";
import { createDatabase, type Database } from "@/db/client";
import { getRuntimeConfig } from "@/lib/env";
import { plainTextFromHtml } from "@/lib/html";
import { randomUuid } from "@/lib/ids";

type Transaction = Parameters<Parameters<Database["transaction"]>[0]>[0];
type Executor = Database | Transaction;

function toArticle(row: ArticleRow): ArticleRecord {
  return {
    id: row.id,
    articleId: row.articleId,
    unlistedToken: row.unlistedToken,
    sourceMaterialId: row.sourceMaterialId,
    visibility: row.visibility,
    currentVersionId: row.currentVersionId,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt
  };
}

function toKey(row: PublishKeyRow): PublishKey {
  return {
    id: row.id,
    kid: row.kid,
    publicKeyJwk: row.publicKeyJwk,
    status: row.status as PublishKey["status"],
    createdAt: row.createdAt,
    revokedAt: row.revokedAt
  };
}

function toMedia(row: MediaAssetRow): MediaAsset {
  return {
    id: row.id,
    objectKey: row.objectKey,
    contentHash: row.contentHash,
    contentType: row.contentType,
    size: row.size,
    status: row.status as MediaAsset["status"],
    createdAt: row.createdAt
  };
}

function toCleanupJob(row: MediaCleanupJobRow): MediaCleanupJob {
  return {
    id: row.id,
    objectKey: row.objectKey,
    articlePublicId: row.articlePublicId,
    status: row.status,
    attempts: row.attempts,
    lastError: row.lastError,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt
  };
}

export class MySqlRepository implements PublishRepository {
  private readonly connection: ReturnType<typeof createDatabase>;
  private readonly db: Database;

  constructor(databaseUrl: string) {
    this.connection = createDatabase(databaseUrl);
    this.db = this.connection.db;
  }

  async health() {
    await this.db.execute(sql`select 1`);
    return true;
  }

  async close() {
    await this.connection.pool.end();
  }

  async registerPublishKey(publishKey: PublishKey) {
    const existing = await this.getPublishKey(publishKey.kid);
    if (existing) {
      if (existing.publicKeyJwk.x !== publishKey.publicKeyJwk.x) {
        throw new ConflictError("发布密钥标识已登记不同公钥");
      }
      return existing;
    }
    await this.db.insert(publishKeys).values({
      id: publishKey.id,
      kid: publishKey.kid,
      publicKeyJwk: publishKey.publicKeyJwk,
      status: publishKey.status,
      createdAt: publishKey.createdAt,
      revokedAt: publishKey.revokedAt
    });
    return publishKey;
  }

  async getPublishKey(kid: string) {
    const rows = await this.db
      .select()
      .from(publishKeys)
      .where(eq(publishKeys.kid, kid))
      .limit(1);
    const row = rows[0];
    return row ? toKey(row) : null;
  }

  async revokePublishKey(kid: string, revokedAt: Date) {
    const result = await this.db
      .update(publishKeys)
      .set({ status: "REVOKED", revokedAt })
      .where(eq(publishKeys.kid, kid));
    if (result[0].affectedRows === 0) {
      throw new NotFoundError("发布密钥不存在");
    }
  }

  async consumeNonce(
    keyId: string,
    nonce: string,
    seenAt: Date,
    expiresAt: Date
  ) {
    await this.db
      .delete(requestNonces)
      .where(sql`${requestNonces.expiresAt} < ${new Date()}`);
    try {
      await this.db.insert(requestNonces).values({
        keyId,
        nonce,
        seenAt,
        expiresAt
      });
      return true;
    } catch (error) {
      if ((error as { code?: string }).code === "ER_DUP_ENTRY") {
        return false;
      }
      throw error;
    }
  }

  async executePublish(input: AtomicPublishInput): Promise<PublishOutcome> {
    return this.db.transaction(async (tx) => {
      await this.lockOperations(tx, [
        `request:${input.keyId}:${input.requestId}`,
        `material:${input.sourceMaterialId}`
      ]);
      const replay = await this.readRequest(
        tx,
        input.keyId,
        input.requestId,
        input.requestHash,
        true
      );
      if (replay) {
        return { ...(replay as PublishOutcome), idempotent: true };
      }

      let article = input.articlePublicId
        ? await this.findArticleByPublicId(tx, input.articlePublicId, true)
        : await this.findArticleByMaterial(tx, input.sourceMaterialId, true);
      if (input.articlePublicId && !article) {
        throw new NotFoundError("要更新的文章不存在");
      }
      if (article && article.sourceMaterialId !== input.sourceMaterialId) {
        throw new ConflictError("文章与来源学习材料不匹配");
      }

      const versions = article
        ? await tx
            .select()
            .from(articleVersions)
            .where(eq(articleVersions.articleRowId, article.id))
            .orderBy(articleVersions.version)
        : [];
      const currentRow = article?.currentVersionId
        ? await tx
            .select()
            .from(articleVersions)
            .where(eq(articleVersions.id, article.currentVersionId))
            .limit(1)
        : [];
      const current = currentRow[0] ?? null;
      const currentVersion = current?.version ?? 0;
      if (currentVersion !== input.expectedVersion) {
        throw new ConflictError("客户端期望版本落后或超前", {
          expectedVersion: input.expectedVersion,
          currentVersion
        });
      }

      if (input.media.length) {
        const mediaIds = [...new Set(input.media.map((item) => item.mediaId))];
        const lockedMedia = await tx
          .select({ id: mediaAssets.id })
          .from(mediaAssets)
          .where(inArray(mediaAssets.id, mediaIds))
          .for("update");
        if (lockedMedia.length !== mediaIds.length) {
          throw new ValidationError("发布媒体已被清理，请重新上传");
        }
      }

      const createdArticle = !article;
      if (!article) {
        const row: ArticleRow = {
          id: input.newArticleRowId,
          articleId: input.newArticlePublicId,
          unlistedToken: input.newUnlistedToken,
          sourceMaterialId: input.sourceMaterialId,
          visibility: input.visibility,
          currentVersionId: null,
          createdAt: input.publishedAt,
          updatedAt: input.publishedAt
        };
        await tx.insert(articles).values(row);
        article = row;
      }

      const existing = versions.find(
        (row) => row.fingerprint === input.fingerprint
      );
      let versionRow: ArticleVersionRow;
      let createdVersion = false;
      if (existing) {
        versionRow = existing;
      } else {
        versionRow = {
          id: input.versionId,
          articleRowId: article.id,
          version:
            versions.reduce((max, row) => Math.max(max, row.version), 0) + 1,
          sourceVersionId: input.sourceVersionId,
          fingerprint: input.fingerprint,
          title: input.title,
          summary: input.summary,
          bodyHtml: input.bodyHtml,
          readerHtml: input.readerHtml,
          toc: input.toc,
          tags: input.tags,
          annotations: input.annotations,
          aiAppendix: input.aiAppendix,
          visibilityAtPublish: input.visibility,
          publishedAt: input.publishedAt
        };
        await tx.insert(articleVersions).values(versionRow);
        createdVersion = true;
      }

      await tx
        .update(articles)
        .set({
          currentVersionId: versionRow.id,
          visibility: input.visibility,
          updatedAt: input.publishedAt
        })
        .where(eq(articles.id, article.id));
      article.currentVersionId = versionRow.id;
      article.visibility = input.visibility;
      article.updatedAt = input.publishedAt;

      if (createdVersion && input.media.length) {
        await tx.insert(articleVersionMedia).values(
          input.media.map((item) => ({
            versionId: versionRow.id,
            mediaId: item.mediaId,
            reference: item.reference
          }))
        );
      }
      if (input.media.length) {
        await tx
          .update(mediaAssets)
          .set({ status: "READY" })
          .where(inArray(mediaAssets.id, input.media.map((item) => item.mediaId)));
      }

      await this.syncSearch(
        tx,
        toArticle(article),
        this.toVersionRecord(versionRow, input.media)
      );

      const outcome: PublishOutcome = {
        articleId: article.articleId,
        unlistedToken: article.unlistedToken,
        visibility: article.visibility,
        version: versionRow.version,
        versionId: versionRow.id,
        fingerprint: versionRow.fingerprint,
        publishedAt: versionRow.publishedAt.toISOString(),
        createdArticle,
        createdVersion,
        reusedVersion: !createdVersion,
        idempotent: false
      };
      await this.storeRequest(tx, input, article.id, outcome);
      return outcome;
    });
  }

  async executeVisibilityChange(
    input: VisibilityInput
  ): Promise<VisibilityOutcome> {
    return this.db.transaction(async (tx) => {
      await this.lockOperations(tx, this.operationKeys(input, input.articlePublicId));
      const replay = await this.readRequest(
        tx,
        input.keyId,
        input.requestId,
        input.requestHash,
        true
      );
      if (replay) {
        return { ...(replay as VisibilityOutcome), idempotent: true };
      }
      const article = await this.requireArticle(tx, input.articlePublicId);
      const version = await this.requireCurrentVersion(tx, article);
      this.assertExpected(version.version, input.expectedVersion);
      const now = new Date();
      article.visibility = input.visibility;
      article.updatedAt = now;
      await tx
        .update(articles)
        .set({ visibility: input.visibility, updatedAt: now })
        .where(eq(articles.id, article.id));
      await this.syncSearch(tx, article, version);
      const outcome: VisibilityOutcome = {
        articleId: article.articleId,
        visibility: input.visibility,
        currentVersion: version.version,
        idempotent: false
      };
      await this.storeRequest(tx, input, article.id, outcome);
      return outcome;
    });
  }

  async executeWithdraw(input: VisibilityInput): Promise<VisibilityOutcome> {
    return this.db.transaction(async (tx) => {
      await this.lockOperations(tx, this.operationKeys(input, input.articlePublicId));
      const replay = await this.readRequest(
        tx,
        input.keyId,
        input.requestId,
        input.requestHash,
        true
      );
      if (replay) {
        return { ...(replay as VisibilityOutcome), idempotent: true };
      }
      const article = await this.requireArticle(tx, input.articlePublicId);
      const version = await this.requireCurrentVersion(tx, article);
      this.assertExpected(version.version, input.expectedVersion);
      const now = new Date();
      article.visibility = "WITHDRAWN";
      article.updatedAt = now;
      await tx
        .update(articles)
        .set({ visibility: "WITHDRAWN", updatedAt: now })
        .where(eq(articles.id, article.id));
      await tx
        .delete(articleSearch)
        .where(eq(articleSearch.articleRowId, article.id));
      const outcome: VisibilityOutcome = {
        articleId: article.articleId,
        visibility: "WITHDRAWN",
        currentVersion: version.version,
        idempotent: false
      };
      await this.storeRequest(tx, input, article.id, outcome);
      return outcome;
    });
  }

  async executeRollback(input: RollbackInput): Promise<RollbackOutcome> {
    return this.db.transaction(async (tx) => {
      await this.lockOperations(tx, this.operationKeys(input, input.articlePublicId));
      const replay = await this.readRequest(
        tx,
        input.keyId,
        input.requestId,
        input.requestHash,
        true
      );
      if (replay) {
        return { ...(replay as RollbackOutcome), idempotent: true };
      }
      const article = await this.requireArticle(tx, input.articlePublicId);
      const current = await this.requireCurrentVersion(tx, article);
      this.assertExpected(current.version, input.expectedVersion);
      const targetRows = await tx
        .select()
        .from(articleVersions)
        .where(
          and(
            eq(articleVersions.articleRowId, article.id),
            eq(articleVersions.version, input.targetVersion)
          )
        )
        .limit(1);
      const target = targetRows[0];
      if (!target) {
        throw new NotFoundError("目标发布版本不存在");
      }
      const media = await this.loadVersionMedia(tx, target.id);
      const now = new Date();
      article.currentVersionId = target.id;
      article.updatedAt = now;
      await tx
        .update(articles)
        .set({ currentVersionId: target.id, updatedAt: now })
        .where(eq(articles.id, article.id));
      await this.syncSearch(
        tx,
        article,
        this.toVersionRecord(target, media)
      );
      const outcome: RollbackOutcome = {
        articleId: article.articleId,
        currentVersion: target.version,
        versionId: target.id,
        fingerprint: target.fingerprint,
        idempotent: false
      };
      await this.storeRequest(tx, input, article.id, outcome);
      return outcome;
    });
  }

  async deleteArticle(input: DeleteInput): Promise<DeleteOutcome> {
    return this.db.transaction(async (tx) => {
      await this.lockOperations(
        tx,
        this.operationKeys(input, input.articlePublicId)
      );
      const replay = await this.readRequest(
        tx,
        input.keyId,
        input.requestId,
        input.requestHash,
        true
      );
      if (replay) {
        return { ...(replay as DeleteOutcome), idempotent: true };
      }
      const article = await this.requireArticle(tx, input.articlePublicId);
      const version = await this.requireCurrentVersion(tx, article);
      this.assertExpected(version.version, input.expectedVersion);
      const orphans = await this.findOrphanMediaForArticle(tx, article);
      const versionRows = await tx
        .select({ id: articleVersions.id })
        .from(articleVersions)
        .where(eq(articleVersions.articleRowId, article.id));
      const versionIds = versionRows.map((row) => row.id);
      if (versionIds.length) {
        await tx
          .delete(articleVersionMedia)
          .where(inArray(articleVersionMedia.versionId, versionIds));
      }
      await tx
        .delete(publishRequests)
        .where(eq(publishRequests.articleRowId, article.id));
      await tx
        .delete(articleSearch)
        .where(eq(articleSearch.articleRowId, article.id));
      await tx
        .delete(articleVersions)
        .where(eq(articleVersions.articleRowId, article.id));
      await tx.delete(articles).where(eq(articles.id, article.id));
      if (orphans.length) {
        await tx
          .delete(mediaAssets)
          .where(inArray(mediaAssets.id, orphans.map((item) => item.id)));
        const now = new Date();
        await tx
          .insert(mediaCleanupJobs)
          .values(
            orphans.map((item) => ({
              id: randomUuid(),
              objectKey: item.objectKey,
              articlePublicId: article.articleId,
              status: "PENDING" as const,
              attempts: 0,
              lastError: null,
              createdAt: now,
              updatedAt: now
            }))
          )
          .onDuplicateKeyUpdate({
            set: {
              status: "PENDING",
              attempts: 0,
              lastError: null,
              updatedAt: now
            }
          });
      }
      const outcome: DeleteOutcome = {
        articleId: article.articleId,
        deleted: true,
        idempotent: false
      };
      await this.storeRequest(tx, input, null, outcome);
      return outcome;
    });
  }

  async getArticleByPublicId(articleId: string) {
    return this.findArticleByPublicId(this.db, articleId);
  }

  async getArticleByUnlistedToken(token: string) {
    const rows = await this.db
      .select()
      .from(articles)
      .where(eq(articles.unlistedToken, token))
      .limit(1);
    return rows[0] ? toArticle(rows[0]) : null;
  }

  async getArticleView(article: ArticleRecord) {
    if (!article.currentVersionId) {
      return null;
    }
    const rows = await this.db
      .select()
      .from(articleVersions)
      .where(eq(articleVersions.id, article.currentVersionId))
      .limit(1);
    const row = rows[0];
    if (!row) {
      return null;
    }
    const media = await this.loadVersionMedia(this.db, row.id);
    return {
      article,
      version: this.toVersionRecord(row, media)
    };
  }

  async getVersion(articleRowId: string, version: number) {
    const rows = await this.db
      .select()
      .from(articleVersions)
      .where(
        and(
          eq(articleVersions.articleRowId, articleRowId),
          eq(articleVersions.version, version)
        )
      )
      .limit(1);
    const row = rows[0];
    if (!row) {
      return null;
    }
    return this.toVersionRecord(
      row,
      await this.loadVersionMedia(this.db, row.id)
    );
  }

  async getMediaAsset(mediaId: string) {
    const rows = await this.db
      .select()
      .from(mediaAssets)
      .where(eq(mediaAssets.id, mediaId))
      .limit(1);
    return rows[0] ? toMedia(rows[0]) : null;
  }

  async getMediaAssetByObjectKey(objectKey: string) {
    const rows = await this.db
      .select()
      .from(mediaAssets)
      .where(eq(mediaAssets.objectKey, objectKey))
      .limit(1);
    return rows[0] ? toMedia(rows[0]) : null;
  }

  async createMediaAsset(asset: MediaAsset) {
    const existing = await this.getMediaAssetByObjectKey(asset.objectKey);
    if (existing) {
      if (
        existing.contentHash !== asset.contentHash ||
        existing.contentType !== asset.contentType ||
        existing.size !== asset.size
      ) {
        throw new ConflictError("同一对象键已登记不同媒体");
      }
      return existing;
    }
    await this.db.insert(mediaAssets).values({
      id: asset.id,
      objectKey: asset.objectKey,
      contentHash: asset.contentHash,
      contentType: asset.contentType,
      size: asset.size,
      status: asset.status,
      createdAt: asset.createdAt
    });
    return asset;
  }

  async markMediaReady(mediaId: string) {
    await this.db
      .update(mediaAssets)
      .set({ status: "READY" })
      .where(eq(mediaAssets.id, mediaId));
  }

  async claimMediaCleanupJobs(limit: number): Promise<MediaCleanupJob[]> {
    return this.db.transaction(async (tx) => {
      const now = new Date();
      const staleBefore = new Date(now.getTime() - 5 * 60 * 1000);
      const rows = await tx
        .select()
        .from(mediaCleanupJobs)
        .where(
          or(
            inArray(mediaCleanupJobs.status, ["PENDING", "FAILED"]),
            and(
              eq(mediaCleanupJobs.status, "PROCESSING"),
              lt(mediaCleanupJobs.updatedAt, staleBefore)
            )
          )
        )
        .orderBy(mediaCleanupJobs.createdAt)
        .limit(limit)
        .for("update", { skipLocked: true });
      if (!rows.length) {
        return [];
      }
      await tx
        .update(mediaCleanupJobs)
        .set({ status: "PROCESSING", updatedAt: now })
        .where(inArray(mediaCleanupJobs.id, rows.map((row) => row.id)));
      return rows.map((row) =>
        toCleanupJob({
          ...row,
          status: "PROCESSING",
          updatedAt: now
        })
      );
    });
  }

  async completeMediaCleanupJob(jobId: string) {
    await this.db
      .delete(mediaCleanupJobs)
      .where(eq(mediaCleanupJobs.id, jobId));
  }

  async failMediaCleanupJob(jobId: string, message: string) {
    await this.db
      .update(mediaCleanupJobs)
      .set({
        status: "FAILED",
        attempts: sql`${mediaCleanupJobs.attempts} + 1`,
        lastError: message.slice(0, 4000),
        updatedAt: new Date()
      })
      .where(eq(mediaCleanupJobs.id, jobId));
  }

  private async findOrphanMediaForArticle(
    executor: Executor,
    article: ArticleRecord
  ) {
    const ownRows = await executor
      .selectDistinct({ mediaId: articleVersionMedia.mediaId })
      .from(articleVersionMedia)
      .innerJoin(
        articleVersions,
        eq(articleVersionMedia.versionId, articleVersions.id)
      )
      .where(eq(articleVersions.articleRowId, article.id));
    const mediaIds = ownRows.map((row) => row.mediaId);
    if (!mediaIds.length) {
      return [];
    }
    const lockedMedia = await executor
      .select()
      .from(mediaAssets)
      .where(inArray(mediaAssets.id, mediaIds))
      .for("update");
    const allRefs = await executor
      .select({
        mediaId: articleVersionMedia.mediaId,
        articleRowId: articleVersions.articleRowId
      })
      .from(articleVersionMedia)
      .innerJoin(
        articleVersions,
        eq(articleVersionMedia.versionId, articleVersions.id)
      )
      .where(inArray(articleVersionMedia.mediaId, mediaIds))
      .for("update");
    const referencedElsewhere = new Set(
      allRefs
        .filter((row) => row.articleRowId !== article.id)
        .map((row) => row.mediaId)
    );
    const orphanIds = mediaIds.filter(
      (mediaId) => !referencedElsewhere.has(mediaId)
    );
    if (!orphanIds.length) {
      return [];
    }
    return lockedMedia
      .filter((row) => orphanIds.includes(row.id))
      .map(toMedia);
  }

  async listPublicArticles(limit: number) {
    const rows = await this.db
      .select({
        articleId: articleSearch.articleId,
        versionId: articleSearch.versionId,
        title: articleSearch.title,
        summary: articleSearch.summary,
        tagsText: articleSearch.tagsText,
        publishedAt: articleSearch.publishedAt,
        updatedAt: articleSearch.updatedAt
      })
      .from(articleSearch)
      .orderBy(desc(articleSearch.publishedAt))
      .limit(limit);
    return rows.map(this.toSummary);
  }

  async searchPublicArticles(query: string, limit: number) {
    const normalized = query.trim();
    if (!normalized) {
      return this.listPublicArticles(limit);
    }
    const rows = await this.db
      .select({
        articleId: articleSearch.articleId,
        versionId: articleSearch.versionId,
        title: articleSearch.title,
        summary: articleSearch.summary,
        tagsText: articleSearch.tagsText,
        publishedAt: articleSearch.publishedAt,
        updatedAt: articleSearch.updatedAt
      })
      .from(articleSearch)
      .where(
        sql`MATCH(${articleSearch.title}, ${articleSearch.summary}, ${articleSearch.bodyText}, ${articleSearch.tagsText}, ${articleSearch.studyText}) AGAINST (${normalized} IN NATURAL LANGUAGE MODE)`
      )
      .orderBy(desc(articleSearch.publishedAt))
      .limit(limit);
    return rows.map(this.toSummary);
  }

  async getPublishStatus(articlePublicId: string): Promise<PublishStatus | null> {
    const article = await this.getArticleByPublicId(articlePublicId);
    if (!article) {
      return null;
    }
    const current = article.currentVersionId
      ? await this.db
          .select()
          .from(articleVersions)
          .where(eq(articleVersions.id, article.currentVersionId))
          .limit(1)
      : [];
    const baseUrl = getRuntimeConfig().baseUrl.replace(/\/+$/, "");
    return {
      articleId: article.articleId,
      sourceMaterialId: article.sourceMaterialId,
      visibility: article.visibility,
      currentVersion: current[0]?.version ?? null,
      publicUrl: `${baseUrl}/a/${article.articleId}`,
      unlistedUrl: `${baseUrl}/u/${article.unlistedToken}`,
      fingerprint: current[0]?.fingerprint ?? null,
      updatedAt: article.updatedAt.toISOString()
    };
  }

  async getVersionMedia(versionId: string) {
    return this.loadVersionMedia(this.db, versionId);
  }

  private async findArticleByPublicId(
    executor: Executor,
    articleId: string,
    lock = false
  ) {
    const base = executor
      .select()
      .from(articles)
      .where(eq(articles.articleId, articleId))
      .limit(1);
    const rows = await (lock ? base.for("update") : base);
    return rows[0] ? toArticle(rows[0]) : null;
  }

  private async findArticleByMaterial(
    executor: Executor,
    sourceMaterialId: string,
    lock = false
  ) {
    const base = executor
      .select()
      .from(articles)
      .where(eq(articles.sourceMaterialId, sourceMaterialId))
      .limit(1);
    const rows = await (lock ? base.for("update") : base);
    return rows[0] ? toArticle(rows[0]) : null;
  }

  private async requireArticle(executor: Executor, articlePublicId: string) {
    const article = await this.findArticleByPublicId(
      executor,
      articlePublicId,
      true
    );
    if (!article) {
      throw new NotFoundError();
    }
    return article;
  }

  private async requireCurrentVersion(
    executor: Executor,
    article: ArticleRecord
  ) {
    if (!article.currentVersionId) {
      throw new NotFoundError("文章当前版本不存在");
    }
    const rows = await executor
      .select()
      .from(articleVersions)
      .where(eq(articleVersions.id, article.currentVersionId))
      .limit(1);
    const row = rows[0];
    if (!row) {
      throw new NotFoundError("文章当前版本不存在");
    }
    return this.toVersionRecord(
      row,
      await this.loadVersionMedia(executor, row.id)
    );
  }

  private async loadVersionMedia(
    executor: Executor,
    versionId: string
  ): Promise<VersionMedia[]> {
    const rows = await executor
      .select({
        versionId: articleVersionMedia.versionId,
        mediaId: mediaAssets.id,
        objectKey: mediaAssets.objectKey,
        contentHash: mediaAssets.contentHash,
        contentType: mediaAssets.contentType,
        size: mediaAssets.size,
        reference: articleVersionMedia.reference
      })
      .from(articleVersionMedia)
      .innerJoin(
        mediaAssets,
        eq(articleVersionMedia.mediaId, mediaAssets.id)
      )
      .where(eq(articleVersionMedia.versionId, versionId));
    return rows.map((row) => ({
      id: row.versionId,
      mediaId: row.mediaId,
      objectKey: row.objectKey,
      contentHash: row.contentHash,
      contentType: row.contentType,
      size: row.size,
      reference: row.reference
    }));
  }

  private toVersionRecord(
    row: ArticleVersionRow,
    media: VersionMedia[]
  ): ArticleVersionRecord {
    return {
      id: row.id,
      articleRowId: row.articleRowId,
      version: row.version,
      sourceVersionId: row.sourceVersionId,
      fingerprint: row.fingerprint,
      title: row.title,
      summary: row.summary,
      bodyHtml: row.bodyHtml,
      readerHtml: row.readerHtml,
      toc: row.toc,
      tags: row.tags,
      annotations: row.annotations,
      aiAppendix: row.aiAppendix,
      media,
      visibilityAtPublish: row.visibilityAtPublish,
      publishedAt: row.publishedAt
    };
  }

  private async syncSearch(
    executor: Executor,
    article: ArticleRecord,
    version: ArticleVersionRecord
  ) {
    if (article.visibility !== "PUBLIC") {
      await executor
        .delete(articleSearch)
        .where(eq(articleSearch.articleRowId, article.id));
      return;
    }
    const studyText = [
      ...version.annotations.map((item) => `${item.quote} ${item.note}`),
      ...version.aiAppendix.map((item) => `${item.title} ${item.body}`)
    ].join(" ");
    const values = {
      articleRowId: article.id,
      articleId: article.articleId,
      versionId: version.id,
      title: version.title,
      summary: version.summary,
      bodyText: plainTextFromHtml(version.bodyHtml),
      tagsText: version.tags.join(" "),
      studyText,
      publishedAt: version.publishedAt,
      updatedAt: article.updatedAt
    };
    await executor
      .insert(articleSearch)
      .values(values)
      .onDuplicateKeyUpdate({
        set: {
          versionId: values.versionId,
          title: values.title,
          summary: values.summary,
          bodyText: values.bodyText,
          tagsText: values.tagsText,
          studyText: values.studyText,
          publishedAt: values.publishedAt,
          updatedAt: values.updatedAt
        }
      });
  }

  private async readRequest(
    executor: Executor,
    keyId: string,
    requestId: string,
    requestHash: string,
    lock = false
  ): Promise<unknown | null> {
    const base = executor
      .select()
      .from(publishRequests)
      .where(
        and(
          eq(publishRequests.keyId, keyId),
          eq(publishRequests.requestId, requestId)
        )
      )
      .limit(1);
    const rows = await (lock ? base.for("update") : base);
    const row = rows[0];
    if (!row) {
      return null;
    }
    if (row.requestHash !== requestHash) {
      throw new IdempotencyMismatchError();
    }
    return row.responseJson;
  }

  private async storeRequest(
    executor: Executor,
    input: {
      keyId: string;
      requestId: string;
      requestHash: string;
    },
    articleRowId: string | null,
    response: unknown
  ) {
    await executor.insert(publishRequests).values({
      id: randomUuid(),
      keyId: input.keyId,
      requestId: input.requestId,
      requestHash: input.requestHash,
      articleRowId,
      responseJson: response,
      createdAt: new Date()
    });
  }

  private operationKeys(
    input: { keyId: string; requestId: string },
    articlePublicId: string
  ): string[] {
    return [
      `request:${input.keyId}:${input.requestId}`,
      `article:${articlePublicId}`
    ];
  }

  private async lockOperations(executor: Executor, keys: string[]) {
    for (const key of [...new Set(keys)].sort()) {
      await executor
        .insert(publishLocks)
        .values({ lockKey: key, createdAt: new Date() })
        .onDuplicateKeyUpdate({
          set: { createdAt: sql`${publishLocks.createdAt}` }
        });
      await executor
        .select({ lockKey: publishLocks.lockKey })
        .from(publishLocks)
        .where(eq(publishLocks.lockKey, key))
        .limit(1)
        .for("update");
    }
  }

  private assertExpected(current: number, expected: number) {
    if (current !== expected) {
      throw new ConflictError("客户端期望版本落后或超前", {
        expectedVersion: expected,
        currentVersion: current
      });
    }
  }

  private toSummary(row: {
    articleId: string;
    versionId: string;
    title: string;
    summary: string;
    tagsText: string;
    publishedAt: Date;
    updatedAt: Date;
  }): ArticleSummary {
    return {
      articleId: row.articleId,
      versionId: row.versionId,
      title: row.title,
      summary: row.summary,
      tags: row.tagsText.split(/\s+/).filter(Boolean),
      publishedAt: row.publishedAt,
      updatedAt: row.updatedAt
    };
  }
}
