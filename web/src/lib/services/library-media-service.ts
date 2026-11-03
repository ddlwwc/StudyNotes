import type {
  LibraryMediaAsset,
  LibraryMediaCleanupJob,
  LibraryMediaReference,
  MediaMetadata,
  MediaReferenceInput,
  PublishRepository,
  StorageAdapter
} from "@/domain/types";
import { ConflictError, NotFoundError, ValidationError } from "@/domain/errors";
import { randomUuid } from "@/lib/ids";
import { referencedMediaKeys } from "@/lib/html";
import { libraryObjectKey } from "@/lib/media-object-key";
import { sameMediaMetadata } from "@/lib/media-content-type";
import type {
  LibraryMediaCompleteRequest,
  LibraryMediaCompleteResponse,
  LibraryMediaCleanupCandidateResponse,
  LibraryMediaCleanupRequest,
  LibraryMediaCleanupResponse,
  LibraryMediaPublishPreviewRequest,
  LibraryMediaPublishPreviewResponse,
  LibraryMediaReadRequest,
  LibraryMediaReadResponse,
  LibraryMediaScanRequest,
  LibraryMediaScanResponse,
  LibraryMediaUploadRequest,
  LibraryMediaUploadResponse,
  LibraryMediaStatusResponse
} from "@/lib/api-types";

interface LibraryMediaServiceOptions {
  baseUrl: string;
  mediaUrlTtlSeconds: number;
  cleanupDelaySeconds: number;
  qiniu: {
    bucket: string;
    domain: string;
    uploadUrl: string;
  };
}

export class LibraryMediaService {
  constructor(
    private readonly repository: PublishRepository,
    private readonly storage: StorageAdapter,
    private readonly options: LibraryMediaServiceOptions
  ) {}

  async createUploadToken(
    input: LibraryMediaUploadRequest
  ): Promise<LibraryMediaUploadResponse> {
    const objectKey = libraryObjectKey(input.contentHash, input.contentType);
    const existing = await this.repository.getLibraryMediaAssetByContentHash(
      input.contentHash
    );
    if (existing?.status === "DELETING") {
      throw new ConflictError("笔记媒体正在清理，请稍后重试");
    }
    if (existing && !sameMediaMetadata(existing, input)) {
      throw new ConflictError("同一内容已登记不同的笔记媒体");
    }
    const asset =
      existing ??
      (await this.repository.createLibraryMediaAsset(
        newLibraryAsset(input, objectKey)
      ));
    const credential = await this.storage.createUploadCredential({
      objectKey: asset.objectKey,
      contentHash: asset.contentHash,
      contentType: asset.contentType,
      size: asset.size,
      expiresInSeconds: 600
    });
    return {
      ...credential,
      alreadyExists: existing !== null
    };
  }

  async completeUpload(
    input: LibraryMediaCompleteRequest
  ): Promise<LibraryMediaCompleteResponse> {
    const asset = await this.repository.getLibraryMediaAssetByObjectKey(
      input.objectKey
    );
    if (!asset) {
      throw new NotFoundError("笔记媒体上传登记不存在");
    }
    if (asset.status === "DELETING") {
      throw new ConflictError("笔记媒体正在清理");
    }
    const verified = await this.storage.verifyObject(asset);
    if (!sameMediaMetadata(verified, asset)) {
      throw new ValidationError("笔记媒体元数据与上传登记不一致");
    }
    await this.repository.markLibraryMediaReady(asset.id, new Date());
    return {
      objectKey: asset.objectKey,
      status: "READY",
      contentHash: asset.contentHash,
      contentType: asset.contentType,
      size: asset.size
    };
  }

  async createReadUrl(
    input: LibraryMediaReadRequest
  ): Promise<LibraryMediaReadResponse> {
    const asset = await this.repository.getLibraryMediaAssetByObjectKey(
      input.objectKey
    );
    if (!asset || asset.status !== "READY") {
      throw new NotFoundError("笔记媒体不存在或尚未就绪");
    }
    return {
      url: await this.storage.createReadUrl(
        asset.objectKey,
        this.options.mediaUrlTtlSeconds
      ),
      expiresAt: new Date(
        Date.now() + this.options.mediaUrlTtlSeconds * 1000
      ).toISOString()
    };
  }

  async publishPreview(
    input: LibraryMediaPublishPreviewRequest
  ): Promise<LibraryMediaPublishPreviewResponse> {
    const refs = new Map(
      (input.mediaRefs ?? []).map((ref) => [ref.objectKey, ref])
    );
    const media = await Promise.all(
      referencedMediaKeys(input.bodyHtml).map(async (objectKey) => {
        const ref = refs.get(objectKey);
        if (!ref) {
          return { objectKey, status: "MISSING_REFERENCE" as const };
        }
        const asset = await this.findAsset(objectKey);
        if (!asset) {
          return { objectKey, status: "MISSING" as const };
        }
        if (!matchesReference(asset, ref)) {
          return { objectKey, status: "MISMATCH" as const };
        }
        return {
          objectKey,
          status: asset.status,
          contentHash: asset.contentHash,
          contentType: asset.contentType,
          size: asset.size
        };
      })
    );
    return {
      ready: media.every((item) => item.status === "READY"),
      media
    };
  }

  async status(): Promise<LibraryMediaStatusResponse> {
    let ok = true;
    let message: string | undefined;
    try {
      const [repositoryHealthy, storageHealthy] = await Promise.all([
        this.repository.health(),
        this.storage.health()
      ]);
      ok = repositoryHealthy && storageHealthy;
      if (!ok) {
        message = "笔记媒体服务未就绪";
      }
    } catch (error) {
      ok = false;
      message = error instanceof Error ? error.message : String(error);
    }
    return {
      ok,
      bucket: this.options.qiniu.bucket,
      domain: this.options.qiniu.domain,
      uploadUrl: this.options.qiniu.uploadUrl,
      httpWarning: !this.options.baseUrl.startsWith("https://"),
      ...(message ? { message } : {})
    };
  }

  async scanReferences(
    input: LibraryMediaScanRequest
  ): Promise<LibraryMediaScanResponse> {
    const now = new Date();
    const references: LibraryMediaReference[] = input.references.map(
      (reference) => ({
        id: randomUuid(),
        sourceId: input.sourceId,
        scope: reference.scope,
        objectKey: reference.objectKey,
        reference: reference.reference,
        updatedAt: now
      })
    );
    await this.repository.replaceLibraryMediaReferences(
      input.sourceId,
      references
    );

    const byKey = new Map<
      string,
      {
        scopes: Set<"CURRENT" | "HISTORY">;
        references: Set<string>;
      }
    >();
    references.forEach((reference) => {
      const item = byKey.get(reference.objectKey) ?? {
        scopes: new Set<"CURRENT" | "HISTORY">(),
        references: new Set<string>()
      };
      item.scopes.add(reference.scope);
      item.references.add(reference.reference);
      byKey.set(reference.objectKey, item);
    });

    const media = await Promise.all(
      [...byKey.entries()].map(async ([objectKey, item]) => {
        const asset =
          await this.repository.getLibraryMediaAssetByObjectKey(objectKey);
        return {
          objectKey,
          scopes: [...item.scopes].sort(),
          references: [...item.references],
          status: asset?.status ?? ("MISSING" as const),
          ...(asset
            ? {
                contentHash: asset.contentHash,
                contentType: asset.contentType,
                size: asset.size
              }
            : {})
        };
      })
    );
    const currentKeys = new Set(
      references
        .filter((reference) => reference.scope === "CURRENT")
        .map((reference) => reference.objectKey)
    );
    const historyKeys = new Set(
      references
        .filter((reference) => reference.scope === "HISTORY")
        .map((reference) => reference.objectKey)
    );
    const historicalLocal = input.historicalLocalMedia ?? [];
    return {
      sourceId: input.sourceId,
      summary: {
        currentCount: currentKeys.size,
        historyCount: historyKeys.size,
        totalSize: media.reduce((total, item) => total + (item.size ?? 0), 0),
        missingCount: media.filter((item) => item.status === "MISSING").length,
        historicalLocalCount: historicalLocal.length,
        historicalLocalSize: historicalLocal.reduce(
          (total, item) => total + item.size,
          0
        )
      },
      media
    };
  }

  async requestCleanup(
    input: LibraryMediaCleanupRequest
  ): Promise<LibraryMediaCleanupResponse> {
    await this.flushCleanupJobs();
    if (!input.confirmed) {
      return {
        queued: [],
        skipped: input.objectKeys.map((objectKey) => ({
          objectKey,
          reason: "CONFIRMATION_REQUIRED" as const
        }))
      };
    }
    const objectKeys = [...new Set(input.objectKeys)];
    const referenced = new Set(
      (
        await this.repository.getLibraryMediaReferences(objectKeys)
      ).map((reference) => reference.objectKey)
    );
    const skipped: LibraryMediaCleanupResponse["skipped"] = [];
    const eligible: string[] = [];
    for (const objectKey of objectKeys) {
      if (referenced.has(objectKey)) {
        skipped.push({ objectKey, reason: "REFERENCED" });
        continue;
      }
      const asset =
        await this.repository.getLibraryMediaAssetByObjectKey(objectKey);
      if (!asset) {
        skipped.push({ objectKey, reason: "NOT_FOUND" });
        continue;
      }
      eligible.push(objectKey);
    }
    const availableAt = new Date(
      Date.now() + this.options.cleanupDelaySeconds * 1000
    );
    const jobs = await this.repository.enqueueLibraryMediaCleanup(
      eligible,
      availableAt
    );
    await this.flushCleanupJobs();
    return {
      queued: jobs.map((job) => ({
        objectKey: job.objectKey,
        availableAt: job.availableAt.toISOString()
      })),
      skipped
    };
  }

  async cleanupCandidates(): Promise<LibraryMediaCleanupCandidateResponse> {
    const assets = (await this.repository.listLibraryMediaAssets()).filter(
      (asset) => asset.status === "READY"
    );
    const references = await this.repository.getLibraryMediaReferences(
      assets.map((asset) => asset.objectKey)
    );
    const referenced = new Set(references.map((item) => item.objectKey));
    const media = assets.filter((asset) => !referenced.has(asset.objectKey));
    return {
      summary: {
        count: media.length,
        totalSize: media.reduce((total, asset) => total + asset.size, 0)
      },
      media: media.map((asset) => ({
        objectKey: asset.objectKey,
        status: "READY" as const,
        contentHash: asset.contentHash,
        contentType: asset.contentType,
        size: asset.size
      }))
    };
  }

  private async flushCleanupJobs() {
    const jobs = await this.repository.claimLibraryMediaCleanupJobs(
      20,
      new Date()
    );
    for (const job of jobs) {
      await this.processCleanupJob(job);
    }
  }

  private async processCleanupJob(job: LibraryMediaCleanupJob) {
    try {
      const shouldDelete =
        await this.repository.markLibraryMediaDeletingIfUnreferenced(
          job.objectKey
        );
      if (shouldDelete) {
        await this.storage.deleteObject(job.objectKey);
        await this.repository.deleteLibraryMediaAsset(job.objectKey);
      }
      await this.repository.completeLibraryMediaCleanupJob(job.id);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      await this.repository.failLibraryMediaCleanupJob(job.id, message);
    }
  }

  private async findAsset(objectKey: string): Promise<LibraryMediaAsset | null> {
    if (objectKey.startsWith("library-media/")) {
      return this.repository.getLibraryMediaAssetByObjectKey(objectKey);
    }
    const asset = await this.repository.getMediaAssetByObjectKey(objectKey);
    return asset ? { ...asset, verifiedAt: null } : null;
  }
}

function matchesReference(
  asset: MediaMetadata,
  ref: MediaReferenceInput
): boolean {
  return sameMediaMetadata(asset, ref);
}

function newLibraryAsset(
  input: LibraryMediaUploadRequest,
  objectKey: string
): LibraryMediaAsset {
  return {
    id: randomUuid(),
    objectKey,
    contentHash: input.contentHash,
    contentType: input.contentType,
    size: input.size,
    status: "PENDING",
    createdAt: new Date(),
    verifiedAt: null
  };
}

