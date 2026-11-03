import { withErrorHandling } from "@/lib/api";
import type { LibraryMediaUploadRequest } from "@/lib/api-types";
import { parseBearerJson } from "@/lib/route-helpers";

export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  return withErrorHandling(async () => {
    const { body, service } =
      await parseBearerJson<LibraryMediaUploadRequest>(
        request,
        "LibraryMediaUploadRequest"
      );
    return Response.json(await service.createUploadToken(body), {
      headers: { "Cache-Control": "no-store" }
    });
  });
}
