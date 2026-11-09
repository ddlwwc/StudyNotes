import type { NextRequest } from "next/server";

const hopByHopHeaders = new Set([
  "connection",
  "content-encoding",
  "content-length",
  "host",
  "keep-alive",
  "proxy-authenticate",
  "proxy-authorization",
  "te",
  "trailer",
  "transfer-encoding",
  "upgrade"
]);

async function proxy(request: NextRequest) {
  const apiUrl = process.env.STUDY_NOTES_API_URL ?? "http://127.0.0.1:8765";
  const target = new URL(
    `${request.nextUrl.pathname}${request.nextUrl.search}`,
    apiUrl
  );
  const requestHeaders = new Headers(request.headers);
  for (const header of hopByHopHeaders) {
    requestHeaders.delete(header);
  }

  try {
    const upstream = await fetch(target, {
      method: request.method,
      headers: requestHeaders,
      body:
        request.method === "GET" || request.method === "HEAD"
          ? undefined
          : await request.arrayBuffer(),
      redirect: "manual",
      cache: "no-store"
    });
    const responseHeaders = new Headers(upstream.headers);
    for (const header of hopByHopHeaders) {
      responseHeaders.delete(header);
    }

    return new Response(upstream.body, {
      status: upstream.status,
      statusText: upstream.statusText,
      headers: responseHeaders
    });
  } catch {
    return Response.json(
      { detail: "本地服务暂不可用。" },
      { status: 502 }
    );
  }
}

export {
  proxy as DELETE,
  proxy as GET,
  proxy as HEAD,
  proxy as OPTIONS,
  proxy as PATCH,
  proxy as POST,
  proxy as PUT
};
