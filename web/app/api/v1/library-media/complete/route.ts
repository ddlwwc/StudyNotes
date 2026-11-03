import { withErrorHandling } from "@/lib/api";
import type { LibraryMediaCompleteRequest } from "@/lib/api-types";
import { parseBearerJson } from "@/lib/route-helpers";

export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  return withErrorHandling(async () => {
    const { body, service } =
      await parseBearerJson<LibraryMediaCompleteRequest>(
        request,
        "LibraryMediaCompleteRequest"
      );
    return Response.json(await service.completeUpload(body), {
      headers: { "Cache-Control": "no-store" }
    });
  });
}
