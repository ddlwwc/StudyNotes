import { AppError, ValidationError } from "@/domain/errors";

const MAX_REQUEST_BODY_BYTES = 2_500_000;

export interface ParsedJsonBody {
  text: string;
  value: unknown;
}

export async function readJsonBody(request: Request): Promise<ParsedJsonBody> {
  const contentType = request.headers.get("content-type") ?? "";
  if (!contentType.includes("application/json")) {
    throw new ValidationError("Content-Type 必须为 application/json");
  }
  const text = await request.text();
  if (Buffer.byteLength(text, "utf8") > MAX_REQUEST_BODY_BYTES) {
    throw new AppError("请求体过大", 413, "PAYLOAD_TOO_LARGE");
  }
  if (!text.trim()) {
    throw new ValidationError("请求体不能为空");
  }
  try {
    return { text, value: JSON.parse(text) as unknown };
  } catch {
    throw new ValidationError("请求体不是有效 JSON");
  }
}

export async function readOptionalJsonBody(
  request: Request
): Promise<ParsedJsonBody> {
  const text = await request.text();
  if (!text.trim()) {
    return { text: "", value: {} };
  }
  return { text, value: JSON.parse(text) as unknown };
}

export function errorResponse(error: unknown): Response {
  if (error instanceof AppError) {
    return Response.json(
      {
        code: error.code,
        message: error.message,
        ...(error.details === undefined ? {} : { details: error.details })
      },
      { status: error.status }
    );
  }
  console.error(error);
  return Response.json(
    {
      code: "INTERNAL_SERVER_ERROR",
      message: "服务器处理请求失败"
    },
    { status: 500 }
  );
}

export async function withErrorHandling(
  handler: () => Promise<Response>
): Promise<Response> {
  try {
    return await handler();
  } catch (error) {
    return errorResponse(error);
  }
}
