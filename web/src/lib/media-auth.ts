import { createHash, timingSafeEqual } from "node:crypto";
import { AuthenticationError, AppError } from "@/domain/errors";

const KEY_HASH_PATTERN = /^sha256:[a-f0-9]{64}$/;

export class MediaBearerAuthenticator {
  private readonly expectedHash: string;

  constructor(options: { keyHash: string | undefined }) {
    const keyHash = options.keyHash?.trim() ?? "";
    if (!KEY_HASH_PATTERN.test(keyHash)) {
      throw new AppError(
        "缺少或无效的 LIBRARY_MEDIA_KEY_SHA256 配置",
        500,
        "CONFIGURATION_ERROR"
      );
    }
    this.expectedHash = keyHash;
  }

  async authenticate(request: Request): Promise<void> {
    const authorization = request.headers.get("authorization") ?? "";
    const match = /^Bearer ([A-Za-z0-9_-]{32,256})$/.exec(authorization);
    if (!match) {
      throw new AuthenticationError("笔记媒体 Bearer 密钥无效");
    }
    const actualHash = `sha256:${createHash("sha256")
      .update(match[1]!)
      .digest("hex")}`;
    if (!safeEqual(actualHash, this.expectedHash)) {
      throw new AuthenticationError("笔记媒体 Bearer 密钥无效");
    }
  }
}

function safeEqual(left: string, right: string): boolean {
  const leftBuffer = Buffer.from(left);
  const rightBuffer = Buffer.from(right);
  return (
    leftBuffer.length === rightBuffer.length &&
    timingSafeEqual(leftBuffer, rightBuffer)
  );
}
