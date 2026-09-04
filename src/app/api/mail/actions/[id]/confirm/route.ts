export const runtime = "nodejs";

import { z } from "zod";
import { ActionError } from "@/lib/actions";
import { withAuth } from "@/lib/auth/types";
import { apiAuthGuard } from "@/lib/auth/api-auth";
import { confirmAndExecuteEmailTrash } from "@/lib/email/trash";
import { isEmailFeatureEnabled } from "@/lib/integrations/oauth";
import { PolicyDeniedError } from "@/lib/policy";
import { apiErrorResponse } from "@/lib/http/api-error";

const bodySchema = z.object({
  confirmationToken: z.string().min(1),
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

    try {
      const result = await confirmAndExecuteEmailTrash({
        actionId: id,
        confirmationToken: body.confirmationToken,
        userId,
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
          error.code === "NOT_FOUND" || error.code === "MESSAGE_NOT_FOUND"
            ? 404
            : error.code === "FORBIDDEN"
              ? 403
              : error.code === "EXPIRED" || error.code === "ALREADY_USED"
                ? 409
                : 400;
        return Response.json({ error: error.message, code: error.code }, { status });
      }
      return Response.json(
        {
          error: error instanceof Error ? error.message : "Échec corbeille",
          code: "TRASH_FAILED",
        },
        { status: 502 }
      );
    }
  }
);
