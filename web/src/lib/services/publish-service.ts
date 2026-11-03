import { createHash, createPublicKey } from "node:crypto";
import type {
  AiAppendixItem,
  ArticleAnnotation,
  ArticleView,
  AtomicPublishInput,
  MediaAsset,
  MediaReferenceInput,
  PublishOutcome,
  PublishRepository,
  StorageAdapter,
  VersionMedia,
  Visibility,
  VisibilityOutcome
} from "@/domain/types";
import {
  ConflictError,
  NotFoundError,
  ValidationError
} from "@/domain/errors";
import type {
  DeleteRequest,
  MediaUploadTokenRequest,
  MediaUploadTokenResponse,
  PublishKeyRegistrationRequest,
  PublishKeyResponse,
  PublishRequest,
  PublishResponse,
  RollbackRequest,
  VisibilityRequest,
  WithdrawRequest
} from "@/lib/api-types";
import { computePublishFingerprint } from "@/lib/fingerprint";
import {
  buildReaderContent,
  referencedMediaKeys,
  sanitizeArticleHtml
} from "@/lib/html";
import { randomId, randomUuid } from "@/lib/ids";

const MAX_ANNOTATIONS = 200;
const MAX_AI_ITEMS = 50;

export interface PublishServiceOptions {
  baseUrl: string;
  mediaUrlTtlSeconds: number;
}

export class PublishService {
  private readonly baseUrl: string;

  constructor(
    private readonly repository: PublishRepository,
    private readonly storage: StorageAdapter,
    private readonly options: PublishServiceOptions
  ) {
    this.baseUrl = options.baseUrl.replace(/\/+$/, "");
  }

  async registerKey(input: PublishKeyRegistrationRequest): Promise<PublishKeyResponse> {
    if ("d" in input.publicKeyJwk) {
      throw new ValidationError("只能登记 Ed25519 公钥，私钥不得上传");
    }
    try {
      createPublicKey({
        key: input.publicKeyJwk as unknown as JsonWebKey,
        format: "jwk"
      });
    } catch {
      throw new ValidationError("发布公钥格式无效");
    }
    const now = new Date();
    const key = await this.repository.registerPublishKey({
      id: randomUuid(),
      kid: input.kid,
      publicKeyJwk: input.publicKeyJwk,
      status: "ACTIVE",
      createdAt: now,
      revokedAt: null
    });
    return {
      kid: key.kid,
      status: key.status,
      createdAt: key.createdAt.toISOString()
    };
  }

  async revokeKey(kid: string): Promise<void> {
    await this.repository.revokePublishKey(kid, new Date());
  }

  async publish(
    keyId: string,
    requestHash: string,
    input: PublishRequest
  ): Promise<{ status: number; response: PublishResponse }> {
    await this.flushMediaCleanupJobs();
    const annotations = this.activeAnnotations(input);
    const aiAppendix = this.activeAiAppendix(input);
    const tags = this.normalizeTags(input.tags);
    const mediaRefs = input.mediaRefs ?? [];
    const media = await this.validateMediaRefs(mediaRefs, input.bodyHtml);
    const reader = buildReaderContent(input.bodyHtml, annotations);
    const fingerprint = computePublishFingerprint({
      title: input.title,
      summary: input.summary ?? "",
      bodyHtml: reader.bodyHtml,
      tags,
      annotations,
      aiAppendix,
      mediaRefs
    });

    const atomicInput: AtomicPublishInput = {
      keyId,
      requestId: input.requestId,
      requestHash,
      articlePublicId: input.articleId,
      sourceMaterialId: input.sourceMaterialId,
      sourceVersionId: input.sourceVersionId ?? null,
      expectedVersion: input.expectedVersion,
      visibility: input.visibility,
      title: input.title.trim(),
      summary: input.summary?.trim() ?? "",
      fingerprint,
      bodyHtml: reader.bodyHtml,
      readerHtml: reader.readerHtml,
      toc: reader.toc,
      tags,
      annotations,
      aiAppendix,
      media,
      versionId: randomUuid(),
      newArticleRowId: randomUuid(),
      newArticlePublicId: randomId(24),
      newUnlistedToken: randomId(32),
      publishedAt: new Date()
    };
    const outcome = await this.repository.executePublish(atomicInput);
    return {
      status:
        outcome.idempotent ||
        (!outcome.createdArticle && !outcome.createdVersion)
          ? 200
          : 201,
      response: this.toPublishResponse(outcome)
    };
  }

  async changeVisibility(
    keyId: string,
    articleId: string,
    requestHash: string,
    input: VisibilityRequest
  ) {
    const outcome = await this.repository.executeVisibilityChange({
      keyId,
      requestHash,
      requestId: input.requestId,
      articlePublicId: articleId,
      expectedVersion: input.expectedVersion,
      visibility: input.visibility
    });
    return this.toVisibilityResponse(outcome);
  }

  async withdraw(
    keyId: string,
    articleId: string,
    requestHash: string,
    input: WithdrawRequest
  ) {
    const outcome = await this.repository.executeWithdraw({
      keyId,
      requestHash,
      requestId: input.requestId,
      articlePublicId: articleId,
      expectedVersion: input.expectedVersion,
      visibility: "WITHDRAWN"
    });
    return this.toVisibilityResponse(outcome);
  }

  async rollback(
    keyId: string,
    articleId: string,
    requestHash: string,
    input: RollbackRequest
  ) {
    const outcome = await this.repository.executeRollback({
      keyId,
      requestHash,
      requestId: input.requestId,
      articlePublicId: articleId,
      expectedVersion: input.expectedVersion,
      targetVersion: input.targetVersion
    });
    return {
      articleId: outcome.articleId,
      currentVersion: outcome.currentVersion,
      versionId: outcome.versionId,
      fingerprint: outcome.fingerprint,
      idempotent: outcome.idempotent
    };
  }

  async deleteArticle(
    keyId: string,
    articleId: string,
    requestHash: string,
    input: DeleteRequest
  ): Promise<{ articleId: string; deleted: true }> {
    const result = await this.repository.deleteArticle({
      keyId,
      requestId: input.requestId,
      requestHash,
      articlePublicId: articleId,
      expectedVersion: input.expectedVersion
    });
    await this.flushMediaCleanupJobs();
    return { articleId: result.articleId, deleted: true };
  }

  async getStatus(articleId: string) {
    const status = await this.repository.getPublishStatus(articleId);
    if (!status) {
      throw new NotFoundError();
    }
    return {
      ...status,
      publicUrl: this.absoluteUrl(status.publicUrl),
      unlistedUrl: this.absoluteUrl(status.unlistedUrl)
    };
  }

  async createMediaUploadToken(
    input: MediaUploadTokenRequest
  ): Promise<MediaUploadTokenResponse> {
    await this.flushMediaCleanupJobs();
    let asset = await this.repository.getMediaAssetByObjectKey(input.objectKey);
    if (asset) {
      if (
        asset.contentHash !== input.contentHash ||
        asset.contentType !== input.contentType ||
        asset.size !== input.size
      ) {
        throw new ConflictError("对象键已登记不同媒体");
      }
    } else {
      asset = await this.repository.createMediaAsset({
        id: randomUuid(),
        objectKey: input.objectKey,
        contentHash: input.contentHash,
        contentType: input.contentType,
        size: input.size,
        status: "PENDING",
        createdAt: new Date()
      });
    }
    const expiresInSeconds = 600;
    return this.storage.createUploadCredential({
      ...input,
      expiresInSeconds
    });
  }

  async getViewForExport(
    lookup: { type: "public"; articleId: string } | { type: "unlisted"; token: string }
  ): Promise<ArticleView> {
    const article =
      lookup.type === "public"
        ? await this.repository.getArticleByPublicId(lookup.articleId)
        : await this.repository.getArticleByUnlistedToken(lookup.token);
    if (!article) {
      throw new NotFoundError();
    }
    if (
      (lookup.type === "public" && article.visibility !== "PUBLIC") ||
      (lookup.type === "unlisted" && article.visibility !== "UNLISTED")
    ) {
      throw new NotFoundError();
    }
    const view = await this.repository.getArticleView(article);
    if (!view) {
      throw new NotFoundError();
    }
    return view;
  }

  private activeAnnotations(input: PublishRequest): ArticleAnnotation[] {
    const values = input.annotations ?? [];
    if (!input.publishAnnotations && values.length) {
      throw new ValidationError(
        "未开启公开标注时，发布请求不得携带私人标注"
      );
    }
    if (!input.publishAnnotations) {
      return [];
    }
    if (values.length > MAX_ANNOTATIONS) {
      throw new ValidationError("公开标注数量超过限制");
    }
    const ids = new Set<string>();
    values.forEach((item) => {
      if (!item.quote.trim()) {
        throw new ValidationError("公开标注的摘录不能为空");
      }
      if (ids.has(item.id)) {
        throw new ValidationError("公开标注标识重复");
      }
      ids.add(item.id);
    });
    return values.map((item) => ({
      ...item,
      note: item.note?.trim() ?? ""
    }));
  }

  private activeAiAppendix(input: PublishRequest): AiAppendixItem[] {
    const values = input.aiAppendix ?? [];
    if (!input.publishAi && values.length) {
      throw new ValidationError(
        "未开启 AI 研读结果时，发布请求不得携带 AI 附录"
      );
    }
    if (!input.publishAi) {
      return [];
    }
    if (values.length > MAX_AI_ITEMS) {
      throw new ValidationError("AI 研读结果数量超过限制");
    }
    return values;
  }

  private normalizeTags(tags: string[] | undefined): string[] {
    return [...new Set((tags ?? []).map((tag) => tag.trim()).filter(Boolean))];
  }

  private async validateMediaRefs(
    refs: MediaReferenceInput[],
    rawBodyHtml: string
  ): Promise<VersionMedia[]> {
    const sanitized = sanitizeArticleHtml(rawBodyHtml);
    const referenced = referencedMediaKeys(sanitized);
    const byKey = new Map<string, MediaReferenceInput>();
    refs.forEach((ref) => {
      if (byKey.has(ref.objectKey)) {
        throw new ValidationError("发布媒体对象键重复");
      }
      byKey.set(ref.objectKey, ref);
    });
    referenced.forEach((key) => {
      if (!byKey.has(key)) {
        throw new ValidationError(`正文引用的媒体 ${key} 缺少媒体提交信息`);
      }
    });

    const media: VersionMedia[] = [];
    for (const ref of refs) {
      const asset = await this.repository.getMediaAssetByObjectKey(ref.objectKey);
      if (!asset) {
        throw new ValidationError("发布媒体尚未取得受控上传凭据");
      }
      this.assertAssetMatches(asset, ref);
      await this.storage.verifyObject(ref);
      await this.repository.markMediaReady(asset.id);
      media.push({
        id: asset.id,
        mediaId: asset.id,
        objectKey: asset.objectKey,
        contentHash: asset.contentHash,
        contentType: asset.contentType,
        size: asset.size,
        reference: ref.reference
      });
    }
    return media;
  }

  private assertAssetMatches(asset: MediaAsset, ref: MediaReferenceInput): void {
    if (
      asset.contentHash !== ref.contentHash ||
      asset.contentType !== ref.contentType ||
      asset.size !== ref.size
    ) {
      throw new ValidationError("发布媒体信息与上传凭据登记不一致");
    }
  }

  private toPublishResponse(outcome: PublishOutcome): PublishResponse {
    return {
      articleId: outcome.articleId,
      visibility: outcome.visibility,
      publicUrl: `${this.baseUrl}/a/${outcome.articleId}`,
      unlistedUrl: `${this.baseUrl}/u/${outcome.unlistedToken}`,
      version: outcome.version,
      versionId: outcome.versionId,
      fingerprint: outcome.fingerprint,
      publishedAt: outcome.publishedAt,
      createdArticle: outcome.createdArticle,
      createdVersion: outcome.createdVersion,
      reusedVersion: outcome.reusedVersion,
      idempotent: outcome.idempotent
    };
  }

  private toVisibilityResponse(outcome: VisibilityOutcome) {
    return {
      articleId: outcome.articleId,
      visibility: outcome.visibility as Visibility,
      currentVersion: outcome.currentVersion,
      idempotent: outcome.idempotent
    };
  }

  private absoluteUrl(value: string): string {
    return value.startsWith("http") ? value : `${this.baseUrl}${value}`;
  }

  private async flushMediaCleanupJobs() {
    let jobs;
    try {
      jobs = await this.repository.claimMediaCleanupJobs(20);
    } catch (error) {
      console.error("读取媒体清理任务失败", error);
      return;
    }
    for (const job of jobs) {
      try {
        const existing = await this.repository.getMediaAssetByObjectKey(
          job.objectKey
        );
        if (!existing) {
          await this.storage.deleteObject(job.objectKey);
        }
        await this.repository.completeMediaCleanupJob(job.id);
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        try {
          await this.repository.failMediaCleanupJob(job.id, message);
        } catch (recordError) {
          console.error(`记录媒体清理任务 ${job.id} 失败状态出错`, recordError);
        }
        console.error(`媒体清理任务 ${job.id} 失败，稍后重试`, error);
      }
    }
  }
}

export function requestBodyHash(body: string): string {
  return `sha256:${createHash("sha256").update(body).digest("hex")}`;
}
