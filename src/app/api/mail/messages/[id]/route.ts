export const runtime = "nodejs";

import { withAuth } from "@/lib/auth/types";
import { apiAuthGuard } from "@/lib/auth/api-auth";
import { getMailMessage, toPublicMessageSummary } from "@/lib/mail/service";
import { isEmailFeatureEnabled } from "@/lib/integrations/oauth";
import { apiErrorResponse } from "@/lib/http/api-error";
import {
  EmailNotConnectedError,
  EmailProviderError,
} from "@/lib/integrations/email/types";

export const GET = withAuth(
  apiAuthGuard,
  async (_request, auth, ctx: { params: Promise<{ id: string }> }) => {
    if (!isEmailFeatureEnabled()) {
      return apiErrorResponse("FEATURE_DISABLED", "Email désactivé");
    }

    const { id } = await ctx.params;
    const userId = auth.userId ?? "local";

    try {
      const message = await getMailMessage(userId, id);
      return Response.json(toPublicMessageSummary(message));
    } catch (error) {
      if (error instanceof EmailNotConnectedError) {
        return apiErrorResponse("EMAIL_NOT_CONNECTED", error.message);
      }
      if (error instanceof EmailProviderError && error.code === "NOT_FOUND") {
        return apiErrorResponse("NOT_FOUND", "Message introuvable.");
      }
      throw error;
    }
  }
);
