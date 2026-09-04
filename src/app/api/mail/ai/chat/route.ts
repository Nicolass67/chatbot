export const runtime = "nodejs";

import { z } from "zod";
import { withAuth } from "@/lib/auth/types";
import { apiAuthGuard } from "@/lib/auth/api-auth";
import { getMailThread } from "@/lib/mail/service";
import { mailAssistantChat } from "@/lib/mail/ai-service";
import { toEmailDraftPreview, requireEmailDraftForUser } from "@/lib/email/draft";
import { isEmailFeatureEnabled } from "@/lib/integrations/oauth";
import { EmailNotConnectedError } from "@/lib/integrations/email/types";
import { apiErrorResponse } from "@/lib/http/api-error";

const bodySchema = z.object({
  message: z.string().min(1).max(4000),
  threadId: z.string().optional(),
  draftId: z.string().optional(),
  model: z.string().optional(),
  accountEmail: z.string().email().optional(),
  attachmentNames: z.array(z.string()).optional(),
  attachmentIds: z.array(z.string().min(1)).max(20).optional(),
});

export const POST = withAuth(apiAuthGuard, async (request, auth) => {
  if (!isEmailFeatureEnabled()) {
    return apiErrorResponse("FEATURE_DISABLED", "Email désactivé");
  }

  const userId = auth.userId ?? "local";

  try {
    const body = bodySchema.parse(await request.json());
    const thread = body.threadId
      ? await getMailThread(userId, body.threadId)
      : undefined;

    const result = await mailAssistantChat({
      userId,
      message: body.message,
      thread,
      draftId: body.draftId,
      model: body.model,
      accountEmail: body.accountEmail,
      attachmentNames: body.attachmentNames,
      attachmentIds: body.attachmentIds,
    });

    const payload: {
      reply: string;
      draft?: Awaited<ReturnType<typeof toEmailDraftPreview>>;
      intent: typeof result.intent;
      applied: typeof result.applied;
    } = {
      reply: result.reply,
      intent: result.intent,
      applied: result.applied,
    };

    if (result.draftId) {
      const draft = await requireEmailDraftForUser(result.draftId, userId);
      payload.draft = await toEmailDraftPreview(draft);
    }

    return Response.json(payload);
  } catch (error) {
    if (error instanceof EmailNotConnectedError) {
      return apiErrorResponse("EMAIL_NOT_CONNECTED", error.message);
    }
    if (error instanceof z.ZodError) {
      return apiErrorResponse("VALIDATION_ERROR", "Requête invalide");
    }
    const message =
      error instanceof Error ? error.message : "Erreur assistant mail";
    console.error("[mail/ai/chat]", error);
    return apiErrorResponse("AI_ERROR", message);
  }
});
