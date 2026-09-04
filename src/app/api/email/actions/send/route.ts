export const runtime = "nodejs";

import { z } from "zod";
import { ActionError } from "@/lib/actions";
import { withAuth } from "@/lib/auth/types";
import { apiAuthGuard } from "@/lib/auth/api-auth";
import {
  buildSendProposalResponse,
  proposeEmailSend,
} from "@/lib/email/send";
import { requireEmailDraftForUser } from "@/lib/email/draft";
import { EmailDraftError } from "@/lib/email/draft/types";
import { isEmailFeatureEnabled } from "@/lib/integrations/oauth";
import { apiErrorResponse } from "@/lib/http/api-error";

const bodySchema = z.object({
  draftId: z.string().min(1),
});

export const POST = withAuth(apiAuthGuard, async (request, auth) => {
  if (!isEmailFeatureEnabled()) {
    return apiErrorResponse("FEATURE_DISABLED", "Email désactivé");
  }

  const userId = auth.userId ?? "local";
  const body = bodySchema.parse(await request.json());

  try {
    const proposal = await proposeEmailSend({
      userId,
      draftId: body.draftId,
    });
    const draft = await requireEmailDraftForUser(body.draftId, userId);
    return Response.json(await buildSendProposalResponse(proposal, draft), {
      status: 201,
    });
  } catch (error) {
    if (error instanceof ActionError) {
      const status =
        error.code === "DRAFT_NOT_FOUND" || error.code === "NOT_FOUND"
          ? 404
          : error.code === "DRAFT_NOT_VALIDATED" ||
              error.code === "HASH_MISMATCH"
            ? 409
            : error.code === "ALREADY_USED"
              ? 409
              : 400;
      return Response.json({ error: error.message, code: error.code }, { status });
    }
    if (error instanceof EmailDraftError) {
      return Response.json(
        { error: error.message, code: error.code },
        { status: error.code === "NOT_FOUND" ? 404 : 409 }
      );
    }
    throw error;
  }
});
