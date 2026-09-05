import { withAuth } from "@/lib/auth/types";
import { apiAuthGuard } from "@/lib/auth/api-auth";
import {
  getNormalizedInfrastructureStatus,
  planFromStatus,
} from "@/lib/infrastructure/supervisor-client";

export const runtime = "nodejs";

/**
 * POST /api/infrastructure/diagnose — plan de réparation minimal (sans exécution).
 */
export const POST = withAuth(apiAuthGuard, async (request) => {
  let serviceId: string | undefined;
  try {
    const body = (await request.json()) as { serviceId?: string };
    if (typeof body?.serviceId === "string" && body.serviceId.trim()) {
      serviceId = body.serviceId.trim();
    }
  } catch {
    // empty body ok
  }

  const status = await getNormalizedInfrastructureStatus();
  const { plan, summary } = planFromStatus(status, serviceId);
  return Response.json({
    status,
    plan,
    summary,
  });
});
