import { withAuth } from "@/lib/auth/types";
import { apiAuthGuard } from "@/lib/auth/api-auth";
import { createHostPowerController } from "@/lib/host/power-controller";

export const runtime = "nodejs";

/**
 * POST /api/infrastructure/power/wake — signal de réveil (CHATBOT_WAKE_URL).
 */
export const POST = withAuth(apiAuthGuard, async () => {
  const power = createHostPowerController();
  const result = await power.wakePc();
  const status = result.ok ? 200 : result.error === "not_configured" ? 501 : 502;
  return Response.json(result, { status });
});
