import { createHash } from "node:crypto";
import { getRuntimeConfig } from "@/lib/env";
import { getMemoryStorage } from "@/lib/runtime";
import { withErrorHandling } from "@/lib/api";
import { ValidationError } from "@/domain/errors";

export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  return withErrorHandling(async () => {
    const config = getRuntimeConfig();
    if (
      process.env.PLAYWRIGHT_TEST !== "1" ||
      config.repositoryMode !== "memory" ||
      config.storageMode !== "memory"
    ) {
      return new Response(null, { status: 404 });
    }
    const body = (await request.json()) as {
      objectKey?: string;
      contentType?: string;
      base64?: string;
    };
    if (!body.objectKey || !body.contentType || !body.base64) {
      throw new ValidationError("测试媒体参数不完整");
    }
    const bytes = Buffer.from(body.base64, "base64");
    const metadata = getMemoryStorage().putObject(
      body.objectKey,
      bytes,
      body.contentType
    );
    return Response.json({
      ...metadata,
      contentHash: `sha256:${createHash("sha256").update(bytes).digest("hex")}`
    });
  });
}
