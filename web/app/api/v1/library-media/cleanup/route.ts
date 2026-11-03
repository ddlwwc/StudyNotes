import { withErrorHandling } from "@/lib/api";
import type { LibraryMediaCleanupRequest } from "@/lib/api-types";
import { parseBearerJson } from "@/lib/route-helpers";

export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  return withErrorHandling(async () => {
    const { body, service } =
      await parseBearerJson<LibraryMediaCleanupRequest>(
        request,
        "LibraryMediaCleanupRequest"
      );
    return Response.json(await service.requestCleanup(body), {
      headers: { "Cache-Control": "no-store" }
    });
  });
}
