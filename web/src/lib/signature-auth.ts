import type { PublishRepository } from "@/domain/types";
import { AuthenticationError, ReplayError } from "@/domain/errors";
import {
  assertNonceFormat,
  assertTimestampFresh,
  verifyRequestSignature
} from "@/lib/signature";

export interface AuthenticatedRequest {
  keyId: string;
  timestamp: Date;
  nonce: string;
}

export class SignatureAuthenticator {
  constructor(
    private readonly repository: PublishRepository,
    private readonly options: { timestampSkewSeconds: number }
  ) {}

  async authenticate(request: Request, body: string): Promise<AuthenticatedRequest> {
    const keyId = request.headers.get("x-studynotes-key-id")?.trim() ?? "";
    const timestamp = request.headers.get("x-studynotes-timestamp")?.trim() ?? "";
    const nonce = request.headers.get("x-studynotes-nonce")?.trim() ?? "";
    const signature = request.headers.get("x-studynotes-signature")?.trim() ?? "";
    const contentSha256 =
      request.headers.get("x-studynotes-content-sha256")?.trim() ?? "";

    if (!keyId || !timestamp || !nonce || !signature || !contentSha256) {
      throw new AuthenticationError("缺少发布请求签名头");
    }
    assertNonceFormat(nonce);
    const timestampDate = assertTimestampFresh(
      timestamp,
      this.options.timestampSkewSeconds
    );
    const key = await this.repository.getPublishKey(keyId);
    if (!key || key.status !== "ACTIVE") {
      throw new AuthenticationError("发布密钥不存在或已撤销");
    }

    verifyRequestSignature(
      {
        method: request.method,
        pathname: new URL(request.url).pathname,
        searchParams: new URL(request.url).searchParams,
        body
      },
      {
        keyId,
        timestamp,
        nonce,
        signature,
        contentSha256
      },
      key.publicKeyJwk
    );

    const expiresAt = new Date(
      timestampDate.getTime() + this.options.timestampSkewSeconds * 2000
    );
    const accepted = await this.repository.consumeNonce(
      keyId,
      nonce,
      new Date(),
      expiresAt
    );
    if (!accepted) {
      throw new ReplayError();
    }
    return { keyId, timestamp: timestampDate, nonce };
  }
}
