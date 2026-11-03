import { assertRuntimeStorageConfigured } from "@/lib/env";
import { getRepository } from "@/lib/runtime";

export const dynamic = "force-dynamic";

export async function GET() {
  const errors: string[] = [];
  try {
    await getRepository().health();
  } catch (error) {
    errors.push(
      `数据库不可用：${error instanceof Error ? error.message : String(error)}`
    );
  }
  try {
    assertRuntimeStorageConfigured();
  } catch (error) {
    errors.push(
      `存储不可用：${error instanceof Error ? error.message : String(error)}`
    );
  }
  const ok = errors.length === 0;
  return Response.json(
    { ok, ...(ok ? {} : { message: errors.join("；") }) },
    { status: ok ? 200 : 503 }
  );
}
