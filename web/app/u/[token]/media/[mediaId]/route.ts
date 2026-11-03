import { withErrorHandling } from "@/lib/api";
import { getRuntimeConfig } from "@/lib/env";
import { getReadService } from "@/lib/services";

export const dynamic = "force-dynamic";

export async function GET(
  _request: Request,
  context: { params: Promise<{ token: string; mediaId: string }> }
) {
  return withErrorHandling(async () => {
    const { token, mediaId } = await context.params;
    const url = await getReadService().mediaUrl(
      { type: "unlisted", token },
      mediaId,
      getRuntimeConfig().mediaUrlTtlSeconds
    );
    return new Response(null, {
      status: 307,
      headers: {
        Location: url,
        "Cache-Control": "private, no-store"
      }
    });
  });
}
