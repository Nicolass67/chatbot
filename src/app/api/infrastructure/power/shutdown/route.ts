import { withAuth } from "@/lib/auth/types";
import { apiAuthGuard } from "@/lib/auth/api-auth";
import { createHostPowerController } from "@/lib/host/power-controller";

export const runtime = "nodejs";

/**
 * POST /api/infrastructure/power/shutdown — planifie l’extinction du PC hôte.
 */
export const POST = withAuth(apiAuthGuard, async () => {
  const power = createHostPowerController();
  const result = power.shutdownPc();
  const status =
    result.ok ? 200 : result.error === "unsupported_platform" ? 501 : 500;
  return Response.json(result, { status });
});
