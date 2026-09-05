import { withAuth } from "@/lib/auth/types";
import { apiAuthGuard } from "@/lib/auth/api-auth";
import {
  getNormalizedInfrastructureStatus,
  planFromStatus,
  requestSupervisorRepair,
} from "@/lib/infrastructure/supervisor-client";

export const runtime = "nodejs";

/**
 * POST /api/infrastructure/repair — body optionnel `{ serviceId }`.
 * Tente le Supervisor HTTP puis enqueue un fichier commande.
 */
export const POST = withAuth(apiAuthGuard, async (request) => {
  let serviceId: string | undefined;
  try {
    const body = (await request.json()) as { serviceId?: string };
    if (typeof body?.serviceId === "string" && body.serviceId.trim()) {
      serviceId = body.serviceId.trim();
    }
  } catch {
    // empty body = repair all down services
  }

  const status = await getNormalizedInfrastructureStatus();
  const { plan, summary } = planFromStatus(status, serviceId);
  const result = await requestSupervisorRepair(serviceId);

  return Response.json({
    plan,
    summary,
    result,
  });
});
