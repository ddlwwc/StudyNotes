import { withErrorHandling } from "@/lib/api";
import { parseBearerEmpty } from "@/lib/route-helpers";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  return withErrorHandling(async () => {
    const service = await parseBearerEmpty(request);
    const status = await service.status();
    return Response.json(status, {
      status: status.ok ? 200 : 503,
      headers: { "Cache-Control": "no-store" }
    });
  });
}
