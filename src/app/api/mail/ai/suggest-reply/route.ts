export const runtime = "nodejs";

import { z } from "zod";
import { withAuth } from "@/lib/auth/types";
import { apiAuthGuard } from "@/lib/auth/api-auth";
import { getMailThread } from "@/lib/mail/service";
import {
  streamSuggestMailReply,
} from "@/lib/mail/ai-service";
import { persistEmailDraft } from "@/lib/email/draft";
import { getOrCreateMailWorkspaceConversation } from "@/lib/mail/workspace";
import { toEmailDraftPreview } from "@/lib/email/draft";
import { isEmailFeatureEnabled } from "@/lib/integrations/oauth";
import { EmailNotConnectedError } from "@/lib/integrations/email/types";
import { apiErrorResponse } from "@/lib/http/api-error";

const bodySchema = z.object({
  threadId: z.string().min(1),
  instruction: z.string().max(2000).optional(),
  model: z.string().optional(),
  attachmentIds: z.array(z.string().min(1)).max(20).optional(),
  stream: z.boolean().optional(),
});

export const POST = withAuth(apiAuthGuard, async (request, auth) => {
  if (!isEmailFeatureEnabled()) {
    return apiErrorResponse("FEATURE_DISABLED", "Email désactivé");
  }

  const userId = auth.userId ?? "local";

  try {
    const body = bodySchema.parse(await request.json());
    const thread = await getMailThread(userId, body.threadId);
    const wantsStream =
      body.stream === true ||
      (request.headers.get("accept") ?? "").includes("text/event-stream");

    if (!wantsStream) {
      const { suggestMailReply } = await import("@/lib/mail/ai-service");
      const result = await suggestMailReply({
        userId,
        thread,
        instruction: body.instruction,
        model: body.model,
        attachmentIds: body.attachmentIds,
      });
      const { requireEmailDraftForUser } = await import("@/lib/email/draft");
      const draft = await requireEmailDraftForUser(result.draftId, userId);
      return Response.json({
        draftId: result.draftId,
        bodyText: result.bodyText,
        subject: result.subject,
        draft: await toEmailDraftPreview(draft),
      });
    }

    const lastMessage = thread.messages[thread.messages.length - 1];
    if (!lastMessage) {
      return apiErrorResponse("AI_ERROR", "Fil vide.");
    }

    const encoder = new TextEncoder();
    const stream = new ReadableStream({
      async start(controller) {
        const send = (obj: Record<string, unknown>) => {
          controller.enqueue(
            encoder.encode(`data: ${JSON.stringify(obj)}\n\n`)
          );
        };
        try {
          send({ type: "status", message: "Préparation de la réponse…" });
          let bodyText = "";
          await streamSuggestMailReply(
            {
              userId,
              thread,
              instruction: body.instruction,
              model: body.model,
              attachmentIds: body.attachmentIds,
            },
            (token) => {
              bodyText += token;
              send({ type: "token", content: token });
            }
          );

          const subject = thread.subject.startsWith("Re:")
            ? thread.subject
            : `Re: ${thread.subject}`;
          const conversationId = await getOrCreateMailWorkspaceConversation();
          const draft = await persistEmailDraft({
            userId,
            conversationId,
            threadId: thread.id,
            provider: "gmail",
            to: [lastMessage.from.email],
            subject,
            bodyText: bodyText.trim() || "…",
            inReplyToMessageId: lastMessage.id,
            attachmentIds: body.attachmentIds,
          });

          send({
            type: "done",
            draftId: draft.id,
            bodyText: draft.bodyText,
            subject,
            draft: await toEmailDraftPreview(draft),
          });
        } catch (error) {
          const message =
            error instanceof Error
              ? error.message
              : "Erreur lors de la suggestion de réponse";
          send({ type: "error", message });
        } finally {
          controller.close();
        }
      },
    });

    return new Response(stream, {
      headers: {
        "Content-Type": "text/event-stream; charset=utf-8",
        "Cache-Control": "no-cache, no-transform",
        Connection: "keep-alive",
      },
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
