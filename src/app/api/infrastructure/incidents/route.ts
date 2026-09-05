import { withAuth } from "@/lib/auth/types";
import { apiAuthGuard } from "@/lib/auth/api-auth";
import { listIncidents } from "@/lib/infrastructure/supervisor-client";

export const runtime = "nodejs";

/**
 * GET /api/infrastructure/incidents — historique des incidents Supervisor.
 */
export const GET = withAuth(apiAuthGuard, async () => {
  return Response.json({ incidents: listIncidents() });
});
