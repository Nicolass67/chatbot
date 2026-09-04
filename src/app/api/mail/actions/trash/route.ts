export const runtime = "nodejs";

import { z } from "zod";
import { ActionError } from "@/lib/actions";
import { withAuth } from "@/lib/auth/types";
import { apiAuthGuard } from "@/lib/auth/api-auth";
import { proposeEmailTrash } from "@/lib/email/trash";
import { isEmailFeatureEnabled } from "@/lib/integrations/oauth";
import { PolicyDeniedError } from "@/lib/policy";
import { EmailNotConnectedError } from "@/lib/integrations/email/types";
import { apiErrorResponse } from "@/lib/http/api-error";

const bodySchema = z.object({
  messageId: z.string().min(1),
});

export const POST = withAuth(apiAuthGuard, async (request, auth) => {
  if (!isEmailFeatureEnabled()) {
    return apiErrorResponse("FEATURE_DISABLED", "Email désactivé");
  }

  const userId = auth.userId ?? "local";
  const body = bodySchema.parse(await request.json());

  try {
    const proposal = await proposeEmailTrash({
      userId,
      messageId: body.messageId,
    });
    return Response.json(proposal, { status: 201 });
  } catch (error) {
    if (error instanceof PolicyDeniedError) {
      return Response.json(
        { error: error.message, code: error.code },
        { status: 403 }
      );
    }
    if (error instanceof EmailNotConnectedError) {
      return apiErrorResponse("EMAIL_NOT_CONNECTED", error.message);
    }
    if (error instanceof ActionError) {
      const status =
        error.code === "MESSAGE_NOT_FOUND" || error.code === "NOT_FOUND"
          ? 404
          : error.code === "ALREADY_USED"
            ? 409
            : 400;
      return Response.json({ error: error.message, code: error.code }, { status });
    }
    throw error;
  }
});
