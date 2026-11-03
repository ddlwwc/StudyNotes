import { withErrorHandling } from "@/lib/api";
import { parseSignedJson } from "@/lib/route-helpers";
import type { PublishRequest } from "@/lib/api-types";

export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  return withErrorHandling(async () => {
    const { body, keyId, requestHash, service } =
      await parseSignedJson<PublishRequest>(request, "PublishRequest");
    const result = await service.publish(keyId, requestHash, body);
    return Response.json(result.response, { status: result.status });
  });
}
