import { withAuth } from "@/lib/auth/types";
import { apiAuthGuard } from "@/lib/auth/api-auth";
import { getNormalizedInfrastructureStatus } from "@/lib/infrastructure/supervisor-client";

export const runtime = "nodejs";

/**
 * GET /api/infrastructure/status — snapshot agrégé (Supervisor HTTP puis fichier).
 */
export const GET = withAuth(apiAuthGuard, async () => {
  const status = await getNormalizedInfrastructureStatus();
  return Response.json(status);
});
