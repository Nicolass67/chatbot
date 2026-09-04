export const runtime = "nodejs";

import { withAuth } from "@/lib/auth/types";
import { apiAuthGuard } from "@/lib/auth/api-auth";
import {
  EmailDraftError,
  toEmailDraftPreview,
  validateEmailDraft,
} from "@/lib/email/draft";
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
      const validated = await validateEmailDraft(id, userId);
      return Response.json(await toEmailDraftPreview(validated));
    } catch (error) {
      if (error instanceof EmailDraftError) {
        const status =
          error.code === "NOT_FOUND"
            ? 404
            : error.code === "VALIDATION_ERROR"
              ? 400
              : 409;
        return Response.json({ error: error.message, code: error.code }, { status });
      }
      throw error;
    }
  }
);
