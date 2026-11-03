import { withErrorHandling } from "@/lib/api";
import { getReadService } from "@/lib/services";

export const dynamic = "force-dynamic";

export async function GET(
  _request: Request,
  context: { params: Promise<{ articleId: string }> }
) {
  return withErrorHandling(async () => {
    const { articleId } = await context.params;
    const result = await getReadService().exportHtml({
      type: "public",
      articleId
    });
    return htmlResponse(result.filename, result.html);
  });
}

function htmlResponse(filename: string, html: string): Response {
  return new Response(html, {
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Content-Disposition": `attachment; filename*=UTF-8''${encodeURIComponent(filename)}`,
      "Cache-Control": "private, no-store",
      "X-Content-Type-Options": "nosniff"
    }
  });
}
