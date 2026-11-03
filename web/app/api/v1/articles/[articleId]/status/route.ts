import { withErrorHandling } from "@/lib/api";
import { parseSignedEmpty } from "@/lib/route-helpers";

export const dynamic = "force-dynamic";

export async function GET(
  request: Request,
  context: { params: Promise<{ articleId: string }> }
) {
  return withErrorHandling(async () => {
    const { service } = await parseSignedEmpty(request);
    const { articleId } = await context.params;
    return Response.json(await service.getStatus(articleId));
  });
}
