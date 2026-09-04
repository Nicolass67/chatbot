export const runtime = "nodejs";

import { z } from "zod";
import { ActionError } from "@/lib/actions";
import { withAuth } from "@/lib/auth/types";
import { apiAuthGuard } from "@/lib/auth/api-auth";
import { confirmAndExecuteEmailSend } from "@/lib/email/send";
import { isEmailFeatureEnabled } from "@/lib/integrations/oauth";
import { PolicyDeniedError } from "@/lib/policy";
import { getSettings } from "@/lib/settings/service";
import { apiErrorResponse } from "@/lib/http/api-error";

const bodySchema = z.object({
  confirmationToken: z.string().min(1),
  conversationId: z.string().min(1),
});

export const POST = withAuth(
  apiAuthGuard,
  async (request, auth, ctx: { params: Promise<{ id: string }> }) => {
    if (!isEmailFeatureEnabled()) {
      return apiErrorResponse("FEATURE_DISABLED", "Email désactivé");
    }

    const { id } = await ctx.params;
    const userId = auth.userId ?? "local";
    const body = bodySchema.parse(await request.json());
    const settings = await getSettings();

    try {
      const result = await confirmAndExecuteEmailSend({
        actionId: id,
        confirmationToken: body.confirmationToken,
        userId,
        settings,
        conversationId: body.conversationId,
        signal: request.signal,
      });
      return Response.json(result);
    } catch (error) {
      if (error instanceof PolicyDeniedError) {
        return Response.json(
          { error: error.message, code: error.code },
          { status: 403 }
        );
      }
      if (error instanceof ActionError) {
        const status =
          error.code === "NOT_FOUND" || error.code === "DRAFT_NOT_FOUND"
            ? 404
            : error.code === "FORBIDDEN"
              ? 403
              : error.code === "EXPIRED" || error.code === "ALREADY_USED"
                ? 409
                : error.code === "HASH_MISMATCH"
                  ? 409
                  : 400;
        return Response.json({ error: error.message, code: error.code }, { status });
      }
      return Response.json(
        {
          error: error instanceof Error ? error.message : "Échec d'envoi",
          code: "SEND_FAILED",
        },
        { status: 502 }
      );
    }
  }
);
