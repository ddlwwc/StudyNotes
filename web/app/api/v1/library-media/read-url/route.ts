import { withErrorHandling } from "@/lib/api";
import type { LibraryMediaReadRequest } from "@/lib/api-types";
import { parseBearerJson } from "@/lib/route-helpers";

export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  return withErrorHandling(async () => {
    const { body, service } =
      await parseBearerJson<LibraryMediaReadRequest>(
        request,
        "LibraryMediaReadRequest"
      );
    return Response.json(await service.createReadUrl(body), {
      headers: { "Cache-Control": "no-store" }
    });
  });
}
