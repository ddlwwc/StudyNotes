import { withErrorHandling } from "@/lib/api";
import { parseSignedJson } from "@/lib/route-helpers";
import type { MediaUploadTokenRequest } from "@/lib/api-types";

export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  return withErrorHandling(async () => {
    const { body, service } = await parseSignedJson<MediaUploadTokenRequest>(
      request,
      "MediaUploadTokenRequest"
    );
    return Response.json(await service.createMediaUploadToken(body));
  });
}
