import { getRuntimeConfig } from "@/lib/env";
import { getRepository, getStorage } from "@/lib/runtime";
import { PublishService } from "@/lib/services/publish-service";
import { ReadService } from "@/lib/services/read-service";
import { SignatureAuthenticator } from "@/lib/signature-auth";

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
