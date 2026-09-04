export const runtime = "nodejs";

import { ActionError } from "@/lib/actions";
import { withAuth } from "@/lib/auth/types";
import { apiAuthGuard } from "@/lib/auth/api-auth";
import { cancelEmailSendAction } from "@/lib/email/send";
import { isEmailFeatureEnabled } from "@/lib/integrations/oauth";
import { apiErrorResponse } from "@/lib/http/api-error";

export const POST = withAuth(
  apiAuthGuard,
  async (_request, auth, ctx: { params: Promise<{ id: string }> }) => {
    if (!isEmailFeatureEnabled()) {
      return apiErrorResponse("FEATURE_DISABLED", "Email désactivé");
    }

    const { id } = await ctx.params;
    const userId = auth.userId ?? "local";

    try {
      const action = await cancelEmailSendAction(id, userId);
      return Response.json(action);
    } catch (error) {
      if (error instanceof ActionError) {
        const status =
          error.code === "NOT_FOUND"
            ? 404
            : error.code === "INVALID_STATE"
              ? 409
              : 400;
        return Response.json({ error: error.message, code: error.code }, { status });
      }
      throw error;
    }
  }
);
