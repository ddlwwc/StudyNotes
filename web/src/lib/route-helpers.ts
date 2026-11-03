import { ValidationError } from "@/domain/errors";
import { readJsonBody, readOptionalJsonBody } from "@/lib/api";
import { validateContract } from "@/lib/contract";
import { sha256 } from "@/lib/signature";
import {
  getSignatureAuthenticator,
  getPublishService,
  getLibraryMediaService,
  getMediaBearerAuthenticator
} from "@/lib/services";
import type { PublishService } from "@/lib/services/publish-service";
import type { LibraryMediaService } from "@/lib/services/library-media-service";

export interface SignedBody<T> {
  body: T;
  rawBody: string;
  requestHash: string;
  keyId: string;
  service: PublishService;
}

export async function parseSignedJson<T>(
  request: Request,
  schemaName: string
): Promise<SignedBody<T>> {
  const parsed = await readJsonBody(request);
  const body = validateContract<T>(schemaName, parsed.value);
  const authenticated = await getSignatureAuthenticator().authenticate(
    request,
    parsed.text
  );
  return {
    body,
    rawBody: parsed.text,
    requestHash: sha256(parsed.text),
    keyId: authenticated.keyId,
    service: getPublishService()
  };
}

export async function parseSignedEmpty(request: Request) {
  const parsed = await readOptionalJsonBody(request);
  if (parsed.text.trim()) {
    throw new ValidationError("该请求不接受请求体");
  }
  const authenticated = await getSignatureAuthenticator().authenticate(
    request,
    ""
  );
  return {
    keyId: authenticated.keyId,
    requestHash: sha256(""),
    service: getPublishService()
  };
}

export async function parseBearerJson<T>(
  request: Request,
  schemaName: string
): Promise<{ body: T; service: LibraryMediaService }> {
  await getMediaBearerAuthenticator().authenticate(request);
  const parsed = await readJsonBody(request);
  return {
    body: validateContract<T>(schemaName, parsed.value),
    service: getLibraryMediaService()
  };
}

export async function parseBearerEmpty(request: Request) {
  await getMediaBearerAuthenticator().authenticate(request);
  return getLibraryMediaService();
}
