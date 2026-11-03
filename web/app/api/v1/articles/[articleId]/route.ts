import { withErrorHandling } from "@/lib/api";
import { parseSignedJson } from "@/lib/route-helpers";
import type { DeleteRequest } from "@/lib/api-types";

export const dynamic = "force-dynamic";

export async function DELETE(
  request: Request,
  context: { params: Promise<{ articleId: string }> }
) {
  return withErrorHandling(async () => {
    const { body, keyId, requestHash, service } =
      await parseSignedJson<DeleteRequest>(request, "DeleteRequest");
    const { articleId } = await context.params;
    return Response.json(
      await service.deleteArticle(keyId, articleId, requestHash, body)
    );
  });
}
