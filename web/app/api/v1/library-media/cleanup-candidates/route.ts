import { withErrorHandling } from "@/lib/api";
import { parseBearerEmpty } from "@/lib/route-helpers";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  return withErrorHandling(async () => {
    const service = await parseBearerEmpty(request);
    return Response.json(await service.cleanupCandidates(), {
      headers: { "Cache-Control": "no-store" }
    });
  });
}
