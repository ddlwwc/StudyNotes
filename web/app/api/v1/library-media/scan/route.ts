import { withErrorHandling } from "@/lib/api";
import type { LibraryMediaScanRequest } from "@/lib/api-types";
import { parseBearerJson } from "@/lib/route-helpers";

export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  return withErrorHandling(async () => {
    const { body, service } =
      await parseBearerJson<LibraryMediaScanRequest>(
        request,
        "LibraryMediaScanRequest"
      );
    return Response.json(await service.scanReferences(body), {
      headers: { "Cache-Control": "no-store" }
    });
  });
}
