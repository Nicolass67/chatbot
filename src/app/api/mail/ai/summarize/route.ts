export const runtime = "nodejs";

import { z } from "zod";
import { withAuth } from "@/lib/auth/types";
import { apiAuthGuard } from "@/lib/auth/api-auth";
import { getMailThread } from "@/lib/mail/service";
import { summarizeMailThread } from "@/lib/mail/ai-service";
import { isEmailFeatureEnabled } from "@/lib/integrations/oauth";
import { EmailNotConnectedError } from "@/lib/integrations/email/types";
import { apiErrorResponse } from "@/lib/http/api-error";

const bodySchema = z.object({
  threadId: z.string().min(1),
  model: z.string().optional(),
});

export const POST = withAuth(apiAuthGuard, async (request, auth) => {
  if (!isEmailFeatureEnabled()) {
    return apiErrorResponse("FEATURE_DISABLED", "Email désactivé");
  }

  const userId = auth.userId ?? "local";

  try {
    const body = bodySchema.parse(await request.json());
    const thread = await getMailThread(userId, body.threadId);
    const summary = await summarizeMailThread(thread, body.model);
    return Response.json({ summary });
  } catch (error) {
    if (error instanceof EmailNotConnectedError) {
      return apiErrorResponse("EMAIL_NOT_CONNECTED", error.message);
    }
    if (error instanceof z.ZodError) {
      return apiErrorResponse("VALIDATION_ERROR", "Requête invalide");
    }
    const message =
      error instanceof Error ? error.message : "Erreur lors du résumé";
    console.error("[mail/ai/summarize]", error);
    return apiErrorResponse("AI_ERROR", message);
  }
});
