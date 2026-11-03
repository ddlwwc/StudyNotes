import { withErrorHandling } from "@/lib/api";
import { getReadService } from "@/lib/services";

export const dynamic = "force-dynamic";

export async function GET(
  _request: Request,
  context: { params: Promise<{ token: string }> }
) {
  return withErrorHandling(async () => {
    const { token } = await context.params;
    const result = await getReadService().exportHtml({
      type: "unlisted",
      token
    });
    return new Response(result.html, {
      headers: {
        "Content-Type": "text/html; charset=utf-8",
        "Content-Disposition": `attachment; filename*=UTF-8''${encodeURIComponent(result.filename)}`,
        "Cache-Control": "private, no-store",
        "X-Content-Type-Options": "nosniff"
      }
    });
  });
}
