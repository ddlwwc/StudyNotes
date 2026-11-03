import { createHash } from "node:crypto";
import type {
  ObjectMetadata,
  StorageAdapter,
  UploadCredentialInput
} from "@/domain/types";
import { ExternalServiceError, ValidationError } from "@/domain/errors";
import { normalizeContentType } from "@/lib/media-content-type";

interface MemoryObject {
  bytes: Buffer;
  contentType: string;
  contentHash: string;
}

export class MemoryStorageAdapter implements StorageAdapter {
  private readonly objects = new Map<string, MemoryObject>();

  async health() {
    return true;
  }

  putObject(
    objectKey: string,
    bytes: Buffer | Uint8Array,
    contentType: string
  ): ObjectMetadata {
    const buffer = Buffer.from(bytes);
    const contentHash = `sha256:${createHash("sha256")
      .update(buffer)
      .digest("hex")}`;
    this.objects.set(objectKey, {
      bytes: buffer,
      contentType,
      contentHash
    });
    return {
      objectKey,
      contentHash,
      contentType,
      size: buffer.length
    };
  }

  async createUploadCredential(input: UploadCredentialInput) {
    const expiresAt = new Date(
      Date.now() + input.expiresInSeconds * 1000
    ).toISOString();
    return {
      uploadUrl: "memory://upload",
      token: `memory-upload:${input.objectKey}`,
      objectKey: input.objectKey,
      expiresAt,
      method: "POST" as const
    };
  }

  async verifyObject(input: {
    objectKey: string;
    contentHash: string;
    contentType: string;
    size: number;
  }): Promise<ObjectMetadata> {
    const object = this.objects.get(input.objectKey);
    if (!object) {
      throw new ExternalServiceError("发布媒体不存在");
    }
    if (object.contentHash !== input.contentHash) {
      throw new ExternalServiceError("发布媒体内容哈希不匹配");
    }
    if (object.bytes.length !== input.size) {
      throw new ExternalServiceError("发布媒体大小不匹配");
    }
    if (normalizeContentType(object.contentType) !== normalizeContentType(input.contentType)) {
      throw new ValidationError("笔记媒体类型不匹配");
    }
    return {
      objectKey: input.objectKey,
      contentHash: object.contentHash,
      contentType: object.contentType,
      size: object.bytes.length
    };
  }

  async copyObject(
    sourceObjectKey: string,
    destinationObjectKey: string,
    contentType: string
  ): Promise<void> {
    const source = this.objects.get(sourceObjectKey);
    if (!source) {
      throw new ExternalServiceError("笔记媒体不存在");
    }
    this.objects.set(destinationObjectKey, {
      bytes: Buffer.from(source.bytes),
      contentType: normalizeContentType(contentType),
      contentHash: source.contentHash
    });
  }

  async createReadUrl(objectKey: string, expiresInSeconds: number) {
    if (!this.objects.has(objectKey)) {
      throw new ExternalServiceError("发布媒体不存在");
    }
    const expiresAt = Date.now() + expiresInSeconds * 1000;
    return `memory://media/${encodeURIComponent(objectKey)}?expires=${expiresAt}`;
  }

  async readObject(objectKey: string): Promise<Buffer> {
    const object = this.objects.get(objectKey);
    if (!object) {
      throw new ExternalServiceError("发布媒体不存在");
    }
    return Buffer.from(object.bytes);
  }

  async deleteObject(objectKey: string): Promise<void> {
    this.objects.delete(objectKey);
  }

  hasObject(objectKey: string): boolean {
    return this.objects.has(objectKey);
  }
}
