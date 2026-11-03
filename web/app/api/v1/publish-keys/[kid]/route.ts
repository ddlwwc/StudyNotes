import { withErrorHandling } from "@/lib/api";
import { parseSignedEmpty } from "@/lib/route-helpers";

export const dynamic = "force-dynamic";

export async function DELETE(
  request: Request,
  context: { params: Promise<{ kid: string }> }
) {
  return withErrorHandling(async () => {
    const { service } = await parseSignedEmpty(request);
    const { kid } = await context.params;
    await service.revokeKey(kid);
    return new Response(null, { status: 204 });
  });
}
