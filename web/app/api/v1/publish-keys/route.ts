import { timingSafeEqual } from "node:crypto";
import { AuthenticationError } from "@/domain/errors";
import { readJsonBody, withErrorHandling } from "@/lib/api";
import { validateContract } from "@/lib/contract";
import { getRuntimeConfig } from "@/lib/env";
import type { PublishKeyRegistrationRequest } from "@/lib/api-types";
import { getPublishService } from "@/lib/services";

export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  return withErrorHandling(async () => {
    const expected = getRuntimeConfig().registrationSecret;
    const supplied = request.headers.get("x-studynotes-registration-secret") ?? "";
    if (!expected || !safeEqual(supplied, expected)) {
      throw new AuthenticationError("发布密钥注册凭据无效");
    }
    const parsed = await readJsonBody(request);
    const body = validateContract<PublishKeyRegistrationRequest>(
      "PublishKeyRegistrationRequest",
      parsed.value
    );
    const response = await getPublishService().registerKey(body);
    return Response.json(response, { status: 201 });
  });
}

function safeEqual(left: string, right: string): boolean {
  const leftBuffer = Buffer.from(left);
  const rightBuffer = Buffer.from(right);
  return (
    leftBuffer.length === rightBuffer.length &&
    timingSafeEqual(leftBuffer, rightBuffer)
  );
}
