import { createHash } from "node:crypto";
import qiniu from "qiniu";
import type {
  ObjectMetadata,
  StorageAdapter,
  UploadCredentialInput
} from "@/domain/types";
import {
  ExternalServiceError,
  ValidationError
} from "@/domain/errors";
import { normalizeContentType } from "@/lib/media-content-type";

interface QiniuConfig {
  accessKey: string;
  secretKey: string;
  bucket: string;
  domain: string;
  uploadUrl: string;
}

function encodeObjectPath(objectKey: string): string {
  return objectKey
    .split("/")
    .map((part) => encodeURIComponent(part))
    .join("/");
}

export class QiniuStorageAdapter implements StorageAdapter {
  private readonly mac: qiniu.auth.digest.Mac;
  private readonly bucketManager: qiniu.rs.BucketManager;
  private readonly config: QiniuConfig;

  constructor(config: QiniuConfig) {
    this.config = config;
    this.mac = new qiniu.auth.digest.Mac(
      config.accessKey,
      config.secretKey
    );
    this.bucketManager = new qiniu.rs.BucketManager(
      this.mac,
      new qiniu.conf.Config()
    );
  }

  async health() {
    const response = await this.bucketManager.stat(
      this.config.bucket,
      ".studynotes-media-health-probe"
    );
    if (response.ok()) {
      return true;
    }
    return Number(
      (response as unknown as { statusCode?: number }).statusCode ?? 0
    ) === 612;
  }

  async createUploadCredential(input: UploadCredentialInput) {
    const policy = new qiniu.rs.PutPolicy({
      scope: `${this.config.bucket}:${input.objectKey}`,
      expires: input.expiresInSeconds,
      insertOnly: 1,
      mimeLimit: input.contentType,
      fsizeLimit: input.size,
      returnBody: JSON.stringify({
        key: "$(key)",
        hash: "$(etag)",
        fsize: "$(fsize)",
        mimeType: "$(mimeType)"
      })
    });
    return {
      uploadUrl: this.config.uploadUrl,
      token: policy.uploadToken(this.mac),
      objectKey: input.objectKey,
      expiresAt: new Date(
        Date.now() + input.expiresInSeconds * 1000
      ).toISOString(),
      method: "POST" as const
    };
  }

  async verifyObject(input: {
    objectKey: string;
    contentHash: string;
    contentType: string;
    size: number;
  }): Promise<ObjectMetadata> {
    const stat = await this.stat(input.objectKey);
    if (Number(stat.fsize) !== input.size) {
      throw new ValidationError("发布媒体大小不匹配");
    }

    const storedContentType = String(stat.mimeType ?? "");
    if (
      !storedContentType ||
      normalizeContentType(storedContentType) !==
        normalizeContentType(input.contentType)
    ) {
      throw new ValidationError("笔记媒体类型不匹配");
    }

    const bytes = await this.readObject(input.objectKey);
    const computed = `sha256:${createHash("sha256")
      .update(bytes)
      .digest("hex")}`;
    if (computed !== input.contentHash) {
      throw new ValidationError("发布媒体内容哈希不匹配");
    }
    return {
      objectKey: input.objectKey,
      contentHash: computed,
      contentType: storedContentType,
      size: Number(stat.fsize)
    };
  }

  async copyObject(
    sourceObjectKey: string,
    destinationObjectKey: string
  ): Promise<void> {
    const response = await this.bucketManager.copy(
      this.config.bucket,
      sourceObjectKey,
      this.config.bucket,
      destinationObjectKey,
      { force: true }
    );
    if (!response.ok()) {
      throw new ExternalServiceError("复制七牛云笔记媒体失败");
    }
  }

  async createReadUrl(
    objectKey: string,
    expiresInSeconds: number
  ): Promise<string> {
    const deadline = Math.floor(Date.now() / 1000) + expiresInSeconds;
    if (typeof this.bucketManager.privateDownloadUrl !== "function") {
      throw new ExternalServiceError("七牛云 SDK 不支持私有下载签名");
    }
    return this.bucketManager.privateDownloadUrl(
      this.config.domain,
      encodeObjectPath(objectKey),
      deadline
    );
  }

  async readObject(objectKey: string): Promise<Buffer> {
    const url = await this.createReadUrl(objectKey, 120);
    const response = await fetch(url, {
      cache: "no-store",
      signal: AbortSignal.timeout(20_000)
    });
    if (!response.ok) {
      throw new ExternalServiceError(
        `读取七牛云对象失败：HTTP ${response.status}`
      );
    }
    const contentLength = Number(response.headers.get("content-length") ?? "0");
    if (contentLength > 50 * 1024 * 1024) {
      throw new ExternalServiceError("七牛云对象超过允许大小");
    }
    const bytes = Buffer.from(await response.arrayBuffer());
    if (bytes.length > 50 * 1024 * 1024) {
      throw new ExternalServiceError("七牛云对象超过允许大小");
    }
    return bytes;
  }

  async deleteObject(objectKey: string): Promise<void> {
    const response = await this.bucketManager.delete(
      this.config.bucket,
      objectKey
    );
    if (!response.ok()) {
      const statusCode = Number(
        (response as unknown as { statusCode?: number }).statusCode ?? 0
      );
      if (statusCode === 404 || statusCode === 612) {
        return;
      }
      throw new ExternalServiceError("删除七牛云对象失败");
    }
  }

  private async stat(objectKey: string): Promise<Record<string, unknown>> {
    const response = await this.bucketManager.stat(
      this.config.bucket,
      objectKey
    );
    if (!response.ok()) {
      throw new ExternalServiceError("读取七牛云对象元数据失败");
    }
    return response.data as unknown as Record<string, unknown>;
  }
}
