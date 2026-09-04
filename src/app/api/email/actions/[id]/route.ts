export const runtime = "nodejs";

import { withAuth } from "@/lib/auth/types";
import { apiAuthGuard } from "@/lib/auth/api-auth";
import { getPublicEmailAction } from "@/lib/email/send";
import { isEmailFeatureEnabled } from "@/lib/integrations/oauth";
import { apiErrorResponse } from "@/lib/http/api-error";

export const GET = withAuth(
  apiAuthGuard,
  async (_request, auth, ctx: { params: Promise<{ id: string }> }) => {
    if (!isEmailFeatureEnabled()) {
      return apiErrorResponse("FEATURE_DISABLED", "Email désactivé");
    }

    const { id } = await ctx.params;
    const userId = auth.userId ?? "local";
    const action = await getPublicEmailAction(id, userId);

    if (!action) {
      return apiErrorResponse("NOT_FOUND", "Action introuvable");
    }

    return Response.json(action);
  }
);
