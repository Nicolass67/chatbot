export const runtime = "nodejs";

import { getLocalAIRuntime } from "@/lib/runtime/factory";

export async function GET() {
  const runtime = getLocalAIRuntime();
  const status = await runtime.status();
  return Response.json({
    ok: status.status === "READY" || status.status === "BUSY",
    ...status,
  });
}
