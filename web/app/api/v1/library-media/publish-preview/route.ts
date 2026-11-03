import { withErrorHandling } from "@/lib/api";
import type { LibraryMediaPublishPreviewRequest } from "@/lib/api-types";
import { parseBearerJson } from "@/lib/route-helpers";

export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  return withErrorHandling(async () => {
    const { body, service } =
      await parseBearerJson<LibraryMediaPublishPreviewRequest>(
        request,
        "LibraryMediaPublishPreviewRequest"
      );
    return Response.json(await service.publishPreview(body), {
      headers: { "Cache-Control": "no-store" }
    });
  });
}
