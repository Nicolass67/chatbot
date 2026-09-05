export const runtime = "nodejs";

import { withAuth } from "@/lib/auth/types";
import { apiAuthGuard } from "@/lib/auth/api-auth";
import { scheduleHostPcShutdown } from "@/lib/host/shutdown-pc";

/**
 * POST /api/host/shutdown — planifie l'extinction du PC hôte (Windows).
 * Auth : session app Bearer (`chs_`) ou Cloudflare Access.
 */
export const POST = withAuth(apiAuthGuard, async () => {
  const result = scheduleHostPcShutdown();

  if (!result.ok) {
    const status = result.error === "unsupported_platform" ? 501 : 500;
    return Response.json(result, { status });
  }

  return Response.json(result);
});
