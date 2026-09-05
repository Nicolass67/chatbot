import { withAuth } from "@/lib/auth/types";
import { apiAuthGuard } from "@/lib/auth/api-auth";
import { createHostPowerController } from "@/lib/host/power-controller";
import { getNormalizedInfrastructureStatus } from "@/lib/infrastructure/supervisor-client";

export const runtime = "nodejs";

/**
 * GET /api/infrastructure/power — état d’alimentation hôte + statut infra.
 */
export const GET = withAuth(apiAuthGuard, async () => {
  const power = createHostPowerController();
  const powerState = await power.getPowerStatus();
  const infra = await getNormalizedInfrastructureStatus();

  return Response.json({
    powerState,
    infrastructurePowerState: infra.powerState,
    supervisorAlive: infra.supervisorAlive,
    overallState: infra.overallState,
    message: infra.message,
    generatedAt: new Date().toISOString(),
  });
});
