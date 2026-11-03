import { withErrorHandling } from "@/lib/api";
import { parseSignedJson } from "@/lib/route-helpers";
import type { RollbackRequest } from "@/lib/api-types";

export const dynamic = "force-dynamic";

export async function POST(
  request: Request,
  context: { params: Promise<{ articleId: string }> }
) {
  return withErrorHandling(async () => {
    const { body, keyId, requestHash, service } =
      await parseSignedJson<RollbackRequest>(request, "RollbackRequest");
    const { articleId } = await context.params;
    return Response.json(
      await service.rollback(keyId, articleId, requestHash, body)
    );
  });
}
