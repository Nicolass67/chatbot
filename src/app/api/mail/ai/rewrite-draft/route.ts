export const runtime = "nodejs";

import { z } from "zod";
import { withAuth } from "@/lib/auth/types";
import { apiAuthGuard } from "@/lib/auth/api-auth";
import { isEmailFeatureEnabled } from "@/lib/integrations/oauth";
import { EmailNotConnectedError } from "@/lib/integrations/email/types";
import { apiErrorResponse } from "@/lib/http/api-error";
import { rewriteMailDraftBody } from "@/lib/mail/draft-generation";

const bodySchema = z.object({
  instruction: z.string().min(1).max(4000),
  body: z.string().min(1).max(20_000),
  to: z.string().max(500).optional(),
  subject: z.string().max(500).optional(),
  draftId: z.string().max(128).optional(),
  model: z.string().optional(),
});

export const POST = withAuth(apiAuthGuard, async (request, auth) => {
  if (!isEmailFeatureEnabled()) {
    return apiErrorResponse("FEATURE_DISABLED", "Email désactivé");
  }
  const userId = auth.userId ?? "local";
  try {
    const body = bodySchema.parse(await request.json());
    const result = await rewriteMailDraftBody({
      userId,
      instruction: body.instruction,
      body: body.body,
      to: body.to,
      subject: body.subject,
      draftId: body.draftId,
      model: body.model,
    });
    return Response.json(result);
  } catch (error) {
    if (error instanceof EmailNotConnectedError) {
      return apiErrorResponse("EMAIL_NOT_CONNECTED", error.message);
    }
    if (error instanceof z.ZodError) {
      return apiErrorResponse("VALIDATION_ERROR", "Requête invalide");
    }
    const message =
      error instanceof Error ? error.message : "Erreur lors de la réécriture";
    console.error("[mail/ai/rewrite-draft]", error);
    return apiErrorResponse("AI_ERROR", message);
  }
});
