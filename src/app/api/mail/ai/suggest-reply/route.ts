export const runtime = "nodejs";

import { z } from "zod";
import { withAuth } from "@/lib/auth/types";
import { apiAuthGuard } from "@/lib/auth/api-auth";
import { getMailThread } from "@/lib/mail/service";
import { suggestMailReply } from "@/lib/mail/ai-service";
import { toEmailDraftPreview } from "@/lib/email/draft";
import { requireEmailDraftForUser } from "@/lib/email/draft";
import { isEmailFeatureEnabled } from "@/lib/integrations/oauth";
import { EmailNotConnectedError } from "@/lib/integrations/email/types";
import { apiErrorResponse } from "@/lib/http/api-error";

const bodySchema = z.object({
  threadId: z.string().min(1),
  instruction: z.string().max(2000).optional(),
  model: z.string().optional(),
  attachmentIds: z.array(z.string().min(1)).max(20).optional(),
});

export const POST = withAuth(apiAuthGuard, async (request, auth) => {
  if (!isEmailFeatureEnabled()) {
    return apiErrorResponse("FEATURE_DISABLED", "Email désactivé");
  }

  const userId = auth.userId ?? "local";

  try {
    const body = bodySchema.parse(await request.json());
    const thread = await getMailThread(userId, body.threadId);
    const result = await suggestMailReply({
      userId,
      thread,
      instruction: body.instruction,
      model: body.model,
      attachmentIds: body.attachmentIds,
    });
    const draft = await requireEmailDraftForUser(result.draftId, userId);
    return Response.json({
      draftId: result.draftId,
      bodyText: result.bodyText,
      subject: result.subject,
      draft: await toEmailDraftPreview(draft),
    });
  } catch (error) {
    if (error instanceof EmailNotConnectedError) {
      return apiErrorResponse("EMAIL_NOT_CONNECTED", error.message);
    }
    if (error instanceof z.ZodError) {
      return apiErrorResponse("VALIDATION_ERROR", "Requête invalide");
    }
    const message =
      error instanceof Error
        ? error.message
        : "Erreur lors de la suggestion de réponse";
    console.error("[mail/ai/suggest-reply]", error);
    return apiErrorResponse("AI_ERROR", message);
  }
});
