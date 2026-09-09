export const runtime = "nodejs";

import { z } from "zod";
import { withAuth } from "@/lib/auth/types";
import { apiAuthGuard } from "@/lib/auth/api-auth";
import { isEmailFeatureEnabled } from "@/lib/integrations/oauth";
import { EmailNotConnectedError } from "@/lib/integrations/email/types";
import { apiErrorResponse } from "@/lib/http/api-error";
import { composeMailDraftBody } from "@/lib/mail/draft-generation";

const bodySchema = z.object({
  instruction: z.string().min(1).max(4000),
  recipientHint: z.string().max(200).optional(),
  subject: z.string().max(500).optional(),
  conversationId: z.string().max(128).optional(),
  model: z.string().optional(),
});

export const POST = withAuth(apiAuthGuard, async (request, auth) => {
  if (!isEmailFeatureEnabled()) {
    return apiErrorResponse("FEATURE_DISABLED", "Email désactivé");
  }
  const userId = auth.userId ?? "local";
  try {
    const body = bodySchema.parse(await request.json());
    const result = await composeMailDraftBody({
      userId,
      instruction: body.instruction,
      recipientHint: body.recipientHint,
      subject: body.subject,
      conversationId: body.conversationId,
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
      error instanceof Error ? error.message : "Erreur lors de la rédaction";
    console.error("[mail/ai/compose-draft]", error);
    return apiErrorResponse("AI_ERROR", message);
  }
});
