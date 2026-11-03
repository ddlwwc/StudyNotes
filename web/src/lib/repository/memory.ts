import type {
  ArticleRecord,
  ArticleSummary,
  ArticleVersionRecord,
  AtomicPublishInput,
  DeleteInput,
  DeleteOutcome,
  LibraryMediaAsset,
  LibraryMediaCleanupJob,
  LibraryMediaReference,
  MediaAsset,
  MediaCleanupJob,
  PublishKey,
  PublishOutcome,
  PublishRepository,
  PublishStatus,
  RollbackInput,
  RollbackOutcome,
  StoredRequest,
  VersionMedia,
  VisibilityInput,
  VisibilityOutcome
} from "@/domain/types";
import {
  ConflictError,
  IdempotencyMismatchError,
  NotFoundError
} from "@/domain/errors";
import { plainTextFromHtml } from "@/lib/html";
import { randomUuid } from "@/lib/ids";
import { sameMediaMetadata } from "@/lib/media-content-type";

interface InternalRequest {
  stored: StoredRequest;
  articleRowId: string | null;
}

interface SearchRow {
  summary: ArticleSummary;
  text: string;
}

export class MemoryRepository implements PublishRepository {
  private readonly keys = new Map<string, PublishKey>();
  private readonly nonces = new Set<string>();
  private readonly articles = new Map<string, ArticleRecord>();
  private readonly articleByPublicId = new Map<string, string>();
  private readonly articleByToken = new Map<string, string>();
  private readonly articleByMaterial = new Map<string, string>();
  private readonly versions = new Map<string, ArticleVersionRecord>();
  private readonly versionsByArticle = new Map<string, string[]>();
  private readonly requests = new Map<string, InternalRequest>();
  private readonly media = new Map<string, MediaAsset>();
  private readonly mediaByObjectKey = new Map<string, string>();
  private readonly libraryMedia = new Map<string, LibraryMediaAsset>();
  private readonly libraryMediaByObjectKey = new Map<string, string>();
  private readonly libraryMediaByContentHash = new Map<string, string>();
  private readonly libraryMediaReferences = new Map<
    string,
    LibraryMediaReference[]
  >();
  private readonly libraryCleanupJobs = new Map<
    string,
    LibraryMediaCleanupJob
  >();
  private readonly versionMedia = new Map<string, VersionMedia[]>();
  private readonly searchRows = new Map<string, SearchRow>();
  private readonly cleanupJobs = new Map<string, MediaCleanupJob>();

  async health() {
    return true;
  }

  async registerPublishKey(publishKey: PublishKey) {
    const existing = this.keys.get(publishKey.kid);
    if (existing) {
      if (existing.publicKeyJwk.x !== publishKey.publicKeyJwk.x) {
        throw new ConflictError("发布密钥标识已登记不同公钥");
      }
      return existing;
    }
    this.keys.set(publishKey.kid, { ...publishKey });
    return { ...publishKey };
  }

  async getPublishKey(kid: string) {
    return this.keys.get(kid) ?? null;
  }

  async revokePublishKey(kid: string, revokedAt: Date) {
    const key = this.keys.get(kid);
    if (!key) {
      throw new NotFoundError("发布密钥不存在");
    }
    key.status = "REVOKED";
    key.revokedAt = revokedAt;
  }

  async consumeNonce(
    keyId: string,
    nonce: string,
    seenAt: Date,
    expiresAt: Date
  ) {
    void seenAt;
    void expiresAt;
    const value = `${keyId}:${nonce}`;
    if (this.nonces.has(value)) {
      return false;
    }
    this.nonces.add(value);
    return true;
  }

  async getPublishOutcomeByRequest(
    keyId: string,
    requestId: string,
    requestHash: string
  ): Promise<PublishOutcome | null> {
    const replay = this.readRequest(keyId, requestId, requestHash);
    return replay ? { ...(replay as PublishOutcome), idempotent: true } : null;
  }

  async executePublish(input: AtomicPublishInput): Promise<PublishOutcome> {
    const replay = this.readRequest(input.keyId, input.requestId, input.requestHash);
    if (replay) {
      return { ...(replay as PublishOutcome), idempotent: true };
    }

    let article =
      (input.articlePublicId
        ? this.articles.get(this.articleByPublicId.get(input.articlePublicId) ?? "")
        : undefined) ??
      this.articles.get(this.articleByMaterial.get(input.sourceMaterialId) ?? "");

    if (input.articlePublicId && !article) {
      throw new NotFoundError("要更新的文章不存在");
    }
    if (article && article.sourceMaterialId !== input.sourceMaterialId) {
      throw new ConflictError("文章与来源学习材料不匹配");
    }

    const articleVersions = article
      ? (this.versionsByArticle.get(article.id) ?? [])
          .map((id) => this.versions.get(id))
          .filter((item): item is ArticleVersionRecord => Boolean(item))
      : [];
    const currentVersion = article?.currentVersionId
      ? this.versions.get(article.currentVersionId) ?? null
      : null;
    const currentNumber = currentVersion?.version ?? 0;
    if (currentNumber !== input.expectedVersion) {
      throw new ConflictError("客户端期望版本落后或超前", {
        expectedVersion: input.expectedVersion,
        currentVersion: currentNumber
      });
    }

    const createdArticle = !article;
    if (!article) {
      article = {
        id: input.newArticleRowId,
        articleId: input.newArticlePublicId,
        unlistedToken: input.newUnlistedToken,
        sourceMaterialId: input.sourceMaterialId,
        visibility: input.visibility,
        currentVersionId: null,
        createdAt: input.publishedAt,
        updatedAt: input.publishedAt
      };
      this.articles.set(article.id, article);
      this.articleByPublicId.set(article.articleId, article.id);
      this.articleByToken.set(article.unlistedToken, article.id);
      this.articleByMaterial.set(article.sourceMaterialId, article.id);
    }

    const existingVersion = articleVersions.find(
      (item) => item.fingerprint === input.fingerprint
    );
    let version: ArticleVersionRecord;
    let createdVersion = false;
    if (existingVersion) {
      version = existingVersion;
    } else {
      version = this.versionFromInput(input, article.id);
      createdVersion = true;
      this.versions.set(version.id, version);
      const ids = this.versionsByArticle.get(article.id) ?? [];
      ids.push(version.id);
      this.versionsByArticle.set(article.id, ids);
    }

    article.currentVersionId = version.id;
    article.visibility = input.visibility;
    article.updatedAt = input.publishedAt;
    this.versionMedia.set(version.id, input.media);
    input.media.forEach((item) => {
      const asset = this.media.get(item.mediaId);
      if (asset) {
        asset.status = "READY";
      }
    });
    this.updateSearch(article, version);

    const outcome: PublishOutcome = {
      articleId: article.articleId,
      unlistedToken: article.unlistedToken,
      visibility: article.visibility,
      version: version.version,
      versionId: version.id,
      fingerprint: version.fingerprint,
      publishedAt: version.publishedAt.toISOString(),
      createdArticle,
      createdVersion,
      reusedVersion: !createdVersion,
      idempotent: false
    };
    this.storeRequest(input, article.id, outcome);
    return outcome;
  }

  async executeVisibilityChange(
    input: VisibilityInput
  ): Promise<VisibilityOutcome> {
    const replay = this.readRequest(input.keyId, input.requestId, input.requestHash);
    if (replay) {
      return { ...(replay as VisibilityOutcome), idempotent: true };
    }
    const article = this.requireArticle(input.articlePublicId);
    const current = article.currentVersionId
      ? this.versions.get(article.currentVersionId)
      : null;
    if (!current) {
      throw new NotFoundError("文章当前版本不存在");
    }
    this.assertExpected(current.version, input.expectedVersion);
    article.visibility = input.visibility;
    article.updatedAt = new Date();
    this.updateSearch(article, current);
    const outcome: VisibilityOutcome = {
      articleId: article.articleId,
      visibility: input.visibility,
      currentVersion: current.version,
      idempotent: false
    };
    this.storeRequest(input, article.id, outcome);
    return outcome;
  }

  async executeWithdraw(input: VisibilityInput): Promise<VisibilityOutcome> {
    const replay = this.readRequest(input.keyId, input.requestId, input.requestHash);
    if (replay) {
      return { ...(replay as VisibilityOutcome), idempotent: true };
    }
    const article = this.requireArticle(input.articlePublicId);
    const current = article.currentVersionId
      ? this.versions.get(article.currentVersionId)
      : null;
    if (!current) {
      throw new NotFoundError("文章当前版本不存在");
    }
    this.assertExpected(current.version, input.expectedVersion);
    article.visibility = "WITHDRAWN";
    article.updatedAt = new Date();
    this.searchRows.delete(article.id);
    const outcome: VisibilityOutcome = {
      articleId: article.articleId,
      visibility: "WITHDRAWN",
      currentVersion: current.version,
      idempotent: false
    };
    this.storeRequest(input, article.id, outcome);
    return outcome;
  }

  async executeRollback(input: RollbackInput): Promise<RollbackOutcome> {
    const replay = this.readRequest(input.keyId, input.requestId, input.requestHash);
    if (replay) {
      return { ...(replay as RollbackOutcome), idempotent: true };
    }
    const article = this.requireArticle(input.articlePublicId);
    const current = article.currentVersionId
      ? this.versions.get(article.currentVersionId)
      : null;
    if (!current) {
      throw new NotFoundError("文章当前版本不存在");
    }
    this.assertExpected(current.version, input.expectedVersion);
    const ids = this.versionsByArticle.get(article.id) ?? [];
    const target = ids
      .map((id) => this.versions.get(id))
      .find((item) => item?.version === input.targetVersion);
    if (!target) {
      throw new NotFoundError("目标发布版本不存在");
    }
    article.currentVersionId = target.id;
    article.updatedAt = new Date();
    this.updateSearch(article, target);
    const outcome: RollbackOutcome = {
      articleId: article.articleId,
      currentVersion: target.version,
      versionId: target.id,
      fingerprint: target.fingerprint,
      idempotent: false
    };
    this.storeRequest(input, article.id, outcome);
    return outcome;
  }

  async deleteArticle(input: DeleteInput): Promise<DeleteOutcome> {
    const replay = this.readRequest(
      input.keyId,
      input.requestId,
      input.requestHash
    );
    if (replay) {
      return { ...(replay as DeleteOutcome), idempotent: true };
    }
    const article = this.requireArticle(input.articlePublicId);
    const current = article.currentVersionId
      ? this.versions.get(article.currentVersionId)
      : null;
    if (!current) {
      throw new NotFoundError("文章当前版本不存在");
    }
    this.assertExpected(current.version, input.expectedVersion);
    const orphans = this.orphanMediaForArticle(article);
    const versionIds = this.versionsByArticle.get(article.id) ?? [];
    versionIds.forEach((id) => {
      this.versions.delete(id);
      this.versionMedia.delete(id);
    });
    this.versionsByArticle.delete(article.id);
    this.searchRows.delete(article.id);
    this.articles.delete(article.id);
    this.articleByPublicId.delete(article.articleId);
    this.articleByToken.delete(article.unlistedToken);
    this.articleByMaterial.delete(article.sourceMaterialId);
    for (const [requestKey, request] of this.requests) {
      if (request.articleRowId === article.id) {
        this.requests.delete(requestKey);
      }
    }
    const now = new Date();
    orphans.forEach((asset) => {
      this.mediaByObjectKey.delete(asset.objectKey);
      this.media.delete(asset.id);
      this.cleanupJobs.set(asset.objectKey, {
        id: randomUuid(),
        objectKey: asset.objectKey,
        articlePublicId: article.articleId,
        status: "PENDING",
        attempts: 0,
        lastError: null,
        createdAt: now,
        updatedAt: now
      });
    });
    const outcome: DeleteOutcome = {
      articleId: article.articleId,
      deleted: true,
      idempotent: false
    };
    this.storeRequest(input, null, outcome);
    return outcome;
  }

  async getArticleByPublicId(articleId: string) {
    const rowId = this.articleByPublicId.get(articleId);
    return rowId ? this.articles.get(rowId) ?? null : null;
  }

  async getArticleByUnlistedToken(token: string) {
    const rowId = this.articleByToken.get(token);
    return rowId ? this.articles.get(rowId) ?? null : null;
  }

  async getArticleView(article: ArticleRecord) {
    if (!article.currentVersionId) {
      return null;
    }
    const version = this.versions.get(article.currentVersionId);
    if (!version) {
      return null;
    }
    return {
      article,
      version: {
        ...version,
        media: this.versionMedia.get(version.id) ?? []
      }
    };
  }

  async getVersion(articleRowId: string, version: number) {
    const ids = this.versionsByArticle.get(articleRowId) ?? [];
    const found = ids
      .map((id) => this.versions.get(id))
      .find((item) => item?.version === version);
    return found
      ? {
          ...found,
          media: this.versionMedia.get(found.id) ?? []
        }
      : null;
  }

  async getMediaAsset(mediaId: string) {
    return this.media.get(mediaId) ?? null;
  }

  async getMediaAssetByObjectKey(objectKey: string) {
    const id = this.mediaByObjectKey.get(objectKey);
    return id ? this.media.get(id) ?? null : null;
  }

  async createMediaAsset(asset: MediaAsset) {
    const existing = this.mediaByObjectKey.get(asset.objectKey);
    if (existing) {
      const value = this.media.get(existing);
      if (!value) {
        throw new ConflictError("媒体索引损坏");
      }
      if (!sameMediaMetadata(value, asset)) {
        throw new ConflictError("同一对象键已登记不同媒体");
      }
      return value;
    }
    this.media.set(asset.id, { ...asset });
    this.mediaByObjectKey.set(asset.objectKey, asset.id);
    return { ...asset };
  }

  async getLibraryMediaAssetByContentHash(contentHash: string) {
    const id = this.libraryMediaByContentHash.get(contentHash);
    return id ? this.libraryMedia.get(id) ?? null : null;
  }

  async getLibraryMediaAssetByObjectKey(objectKey: string) {
    const id = this.libraryMediaByObjectKey.get(objectKey);
    return id ? this.libraryMedia.get(id) ?? null : null;
  }

  async listLibraryMediaAssets() {
    return [...this.libraryMedia.values()].map((asset) => ({ ...asset }));
  }

  async createLibraryMediaAsset(asset: LibraryMediaAsset) {
    const existingByHash = await this.getLibraryMediaAssetByContentHash(
      asset.contentHash
    );
    const existingByKey = this.libraryMedia.get(
      this.libraryMediaByObjectKey.get(asset.objectKey) ?? ""
    );
    const existing = existingByHash ?? existingByKey;
    if (existing) {
      if (
        existing.objectKey !== asset.objectKey ||
        !sameMediaMetadata(existing, asset)
      ) {
        throw new ConflictError("同一内容已登记不同的笔记媒体");
      }
      return existing;
    }
    this.libraryMedia.set(asset.id, { ...asset });
    this.libraryMediaByObjectKey.set(asset.objectKey, asset.id);
    this.libraryMediaByContentHash.set(asset.contentHash, asset.id);
    return { ...asset };
  }

  async markLibraryMediaReady(mediaId: string, verifiedAt: Date) {
    const asset = this.libraryMedia.get(mediaId);
    if (!asset) {
      throw new NotFoundError("笔记媒体不存在");
    }
    if (asset.status === "DELETING") {
      throw new ConflictError("笔记媒体正在清理");
    }
    asset.status = "READY";
    asset.verifiedAt = verifiedAt;
  }

  async markLibraryMediaDeletingIfUnreferenced(objectKey: string) {
    if ((await this.getLibraryMediaReferences([objectKey])).length) {
      return false;
    }
    const id = this.libraryMediaByObjectKey.get(objectKey);
    const asset = id ? this.libraryMedia.get(id) : undefined;
    if (!asset || asset.status === "PENDING") {
      return false;
    }
    asset.status = "DELETING";
    return true;
  }

  async replaceLibraryMediaReferences(
    sourceId: string,
    references: LibraryMediaReference[]
  ) {
    const deletingKeys = new Set(
      (await Promise.all(
        [...new Set(references.map((reference) => reference.objectKey))].map(
          (objectKey) => this.getLibraryMediaAssetByObjectKey(objectKey)
        )
      ))
        .filter((asset) => asset?.status === "DELETING")
        .map((asset) => asset!.objectKey)
    );
    if (deletingKeys.size) {
      throw new ConflictError("笔记媒体正在清理，请稍后重试扫描", {
        objectKeys: [...deletingKeys]
      });
    }
    this.libraryMediaReferences.set(
      sourceId,
      references.map((reference) => ({ ...reference }))
    );
  }

  async getLibraryMediaReferences(objectKeys: string[]) {
    const wanted = new Set(objectKeys);
    return [...this.libraryMediaReferences.values()]
      .flat()
      .filter((reference) => wanted.has(reference.objectKey))
      .map((reference) => ({ ...reference }));
  }

  async enqueueLibraryMediaCleanup(objectKeys: string[], availableAt: Date) {
    const now = new Date();
    return objectKeys.map((objectKey) => {
      const existing = this.libraryCleanupJobs.get(objectKey);
      const job: LibraryMediaCleanupJob = {
        id: existing?.id ?? randomUuid(),
        objectKey,
        status: "PENDING",
        attempts: 0,
        lastError: null,
        availableAt,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now
      };
      this.libraryCleanupJobs.set(objectKey, job);
      return { ...job };
    });
  }

  async claimLibraryMediaCleanupJobs(limit: number, now: Date) {
    const staleBefore = now.getTime() - 5 * 60 * 1000;
    return [...this.libraryCleanupJobs.values()]
      .filter(
        (job) =>
          job.availableAt.getTime() <= now.getTime() &&
          (job.status === "PENDING" ||
            job.status === "FAILED" ||
            (job.status === "PROCESSING" &&
              job.updatedAt.getTime() < staleBefore))
      )
      .sort(
        (left, right) => left.createdAt.getTime() - right.createdAt.getTime()
      )
      .slice(0, limit)
      .map((job) => {
        const claimed = {
          ...job,
          status: "PROCESSING" as const,
          updatedAt: now
        };
        this.libraryCleanupJobs.set(job.objectKey, claimed);
        return { ...claimed };
      });
  }

  async completeLibraryMediaCleanupJob(jobId: string) {
    for (const [objectKey, job] of this.libraryCleanupJobs) {
      if (job.id === jobId) {
        this.libraryCleanupJobs.delete(objectKey);
        return;
      }
    }
  }

  async failLibraryMediaCleanupJob(jobId: string, message: string) {
    for (const job of this.libraryCleanupJobs.values()) {
      if (job.id === jobId) {
        job.status = "FAILED";
        job.attempts += 1;
        job.lastError = message;
        job.updatedAt = new Date();
        return;
      }
    }
  }

  async deleteLibraryMediaAsset(objectKey: string) {
    const id = this.libraryMediaByObjectKey.get(objectKey);
    if (!id) {
      return;
    }
    const asset = this.libraryMedia.get(id);
    this.libraryMedia.delete(id);
    this.libraryMediaByObjectKey.delete(objectKey);
    if (asset) {
      this.libraryMediaByContentHash.delete(asset.contentHash);
    }
  }

  async markMediaReady(mediaId: string) {
    const asset = this.media.get(mediaId);
    if (asset) {
      asset.status = "READY";
    }
  }

  private orphanMediaForArticle(article: ArticleRecord) {
    const ids = this.versionsByArticle.get(article.id) ?? [];
    const articleMediaIds = new Set<string>();
    ids.forEach((versionId) => {
      (this.versionMedia.get(versionId) ?? []).forEach((item) =>
        articleMediaIds.add(item.mediaId)
      );
    });
    const referencedElsewhere = new Set<string>();
    for (const [versionId, refs] of this.versionMedia) {
      if (ids.includes(versionId)) {
        continue;
      }
      refs.forEach((item) => referencedElsewhere.add(item.mediaId));
    }
    return [...articleMediaIds]
      .filter((id) => !referencedElsewhere.has(id))
      .map((id) => this.media.get(id))
      .filter((item): item is MediaAsset => Boolean(item));
  }

  async claimMediaCleanupJobs(limit: number): Promise<MediaCleanupJob[]> {
    const now = new Date();
    const staleBefore = now.getTime() - 5 * 60 * 1000;
    return [...this.cleanupJobs.values()]
      .filter(
        (job) =>
          job.status === "PENDING" ||
          job.status === "FAILED" ||
          (job.status === "PROCESSING" &&
            job.updatedAt.getTime() < staleBefore)
      )
      .sort(
        (left, right) => left.createdAt.getTime() - right.createdAt.getTime()
      )
      .slice(0, limit)
      .map((job) => {
        const claimed: MediaCleanupJob = {
          ...job,
          status: "PROCESSING",
          updatedAt: now
        };
        this.cleanupJobs.set(job.objectKey, claimed);
        return { ...claimed };
      });
  }

  async completeMediaCleanupJob(jobId: string) {
    for (const [objectKey, job] of this.cleanupJobs) {
      if (job.id === jobId) {
        this.cleanupJobs.delete(objectKey);
        return;
      }
    }
  }

  async failMediaCleanupJob(jobId: string, message: string) {
    for (const job of this.cleanupJobs.values()) {
      if (job.id === jobId) {
        job.status = "FAILED";
        job.attempts += 1;
        job.lastError = message;
        job.updatedAt = new Date();
        return;
      }
    }
  }

  pendingMediaCleanupCount() {
    return this.cleanupJobs.size;
  }

  async listPublicArticles(limit: number) {
    return [...this.searchRows.values()]
      .map((row) => row.summary)
      .sort(
        (left, right) =>
          right.publishedAt.getTime() - left.publishedAt.getTime()
      )
      .slice(0, limit);
  }

  async searchPublicArticles(query: string, limit: number) {
    const normalized = query.trim().toLowerCase();
    if (!normalized) {
      return this.listPublicArticles(limit);
    }
    return [...this.searchRows.values()]
      .filter((row) => row.text.toLowerCase().includes(normalized))
      .map((row) => row.summary)
      .sort(
        (left, right) =>
          right.publishedAt.getTime() - left.publishedAt.getTime()
      )
      .slice(0, limit);
  }

  async getPublishStatus(articlePublicId: string): Promise<PublishStatus | null> {
    const article = await this.getArticleByPublicId(articlePublicId);
    if (!article) {
      return null;
    }
    const current = article.currentVersionId
      ? this.versions.get(article.currentVersionId)
      : null;
    return {
      articleId: article.articleId,
      sourceMaterialId: article.sourceMaterialId,
      visibility: article.visibility,
      currentVersion: current?.version ?? null,
      publicUrl: `/a/${article.articleId}`,
      unlistedUrl: `/u/${article.unlistedToken}`,
      fingerprint: current?.fingerprint ?? null,
      updatedAt: article.updatedAt.toISOString()
    };
  }

  async getVersionMedia(versionId: string) {
    return this.versionMedia.get(versionId) ?? [];
  }

  private versionFromInput(
    input: AtomicPublishInput,
    articleRowId: string
  ): ArticleVersionRecord {
    const ids = this.versionsByArticle.get(articleRowId) ?? [];
    const maxVersion = ids.reduce((max, id) => {
      const item = this.versions.get(id);
      return Math.max(max, item?.version ?? 0);
    }, 0);
    return {
      id: input.versionId,
      articleRowId,
      version: maxVersion + 1,
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
      media: input.media,
      visibilityAtPublish: input.visibility,
      publishedAt: input.publishedAt
    };
  }

  private updateSearch(
    article: ArticleRecord,
    version: ArticleVersionRecord
  ) {
    if (article.visibility !== "PUBLIC") {
      this.searchRows.delete(article.id);
      return;
    }
    const annotations = version.annotations
      .map((item) => `${item.quote} ${item.note}`)
      .join(" ");
    const ai = version.aiAppendix
      .map((item) => `${item.title} ${item.body}`)
      .join(" ");
    this.searchRows.set(article.id, {
      summary: {
        articleId: article.articleId,
        versionId: version.id,
        title: version.title,
        summary: version.summary,
        tags: version.tags,
        publishedAt: version.publishedAt,
        updatedAt: article.updatedAt
      },
      text: [
        version.title,
        version.summary,
        plainTextFromHtml(version.bodyHtml),
        version.tags.join(" "),
        annotations,
        ai
      ].join(" ")
    });
  }

  private readRequest(
    keyId: string,
    requestId: string,
    requestHash: string
  ): unknown | null {
    const request = this.requests.get(`${keyId}:${requestId}`);
    if (!request) {
      return null;
    }
    if (request.stored.requestHash !== requestHash) {
      throw new IdempotencyMismatchError();
    }
    return request.stored.response;
  }

  private storeRequest(
    input: {
      keyId: string;
      requestId: string;
      requestHash: string;
    },
    articleRowId: string | null,
    response: unknown
  ) {
    this.requests.set(`${input.keyId}:${input.requestId}`, {
      articleRowId,
      stored: {
        requestId: input.requestId,
        keyId: input.keyId,
        requestHash: input.requestHash,
        response: JSON.parse(JSON.stringify(response)),
        createdAt: new Date()
      }
    });
  }

  private requireArticle(articleId: string) {
    const article = this.articles.get(
      this.articleByPublicId.get(articleId) ?? ""
    );
    if (!article) {
      throw new NotFoundError();
    }
    return article;
  }

  private assertExpected(current: number, expected: number) {
    if (current !== expected) {
      throw new ConflictError("客户端期望版本落后或超前", {
        expectedVersion: expected,
        currentVersion: current
      });
    }
  }
}
