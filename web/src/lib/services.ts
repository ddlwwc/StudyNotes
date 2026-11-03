import { getRuntimeConfig } from "@/lib/env";
import { getRepository, getStorage } from "@/lib/runtime";
import { PublishService } from "@/lib/services/publish-service";
import { ReadService } from "@/lib/services/read-service";
import { SignatureAuthenticator } from "@/lib/signature-auth";
import { LibraryMediaService } from "@/lib/services/library-media-service";
import { MediaBearerAuthenticator } from "@/lib/media-auth";

export function getPublishService(): PublishService {
  const config = getRuntimeConfig();
  return new PublishService(getRepository(), getStorage(), {
    baseUrl: config.baseUrl,
    mediaUrlTtlSeconds: config.mediaUrlTtlSeconds
  });
}

export function getReadService(): ReadService {
  return new ReadService(getRepository(), getStorage());
}

export function getSignatureAuthenticator(): SignatureAuthenticator {
  return new SignatureAuthenticator(getRepository(), {
    timestampSkewSeconds: getRuntimeConfig().timestampSkewSeconds
  });
}

export function getLibraryMediaService(): LibraryMediaService {
  const config = getRuntimeConfig();
  return new LibraryMediaService(getRepository(), getStorage(), {
    baseUrl: config.baseUrl,
    mediaUrlTtlSeconds: config.mediaUrlTtlSeconds,
    cleanupDelaySeconds: config.libraryMediaCleanupDelaySeconds,
    qiniu: {
      bucket: config.qiniu.bucket ?? "memory",
      domain: config.qiniu.domain ?? "memory://media",
      uploadUrl: config.qiniu.uploadUrl
    }
  });
}

export function getMediaBearerAuthenticator(): MediaBearerAuthenticator {
  return new MediaBearerAuthenticator({
    keyHash: getRuntimeConfig().libraryMediaKeyHash
  });
}
