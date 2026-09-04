import { z } from "zod";
import { requireEmailDraftForUser } from "@/lib/email/draft";
import { EmailDraftError } from "@/lib/email/draft/types";
import type { Tool } from "../types";
import { getEmailProviderForTool, requireToolUserId } from "./helpers";

const inputSchema = z.object({
  draftId: z
    .string()
    .min(1)
    .describe("Identifiant interne du brouillon validé à envoyer"),
});

export type EmailSendInput = z.infer<typeof inputSchema>;

export const emailSendInternalTool: Tool<EmailSendInput> = {
  name: "email_send",
  description:
    "Outil interne — envoie un brouillon Gmail validé. Jamais exposé au LLM.",
  inputSchema,
  preferredRuntime: "local",
  async execute(input, ctx) {
    const userId = requireToolUserId(ctx);
    const draft = await requireEmailDraftForUser(input.draftId, userId);

    if (draft.status !== "validated") {
      throw new EmailDraftError(
        "INVALID_STATE",
        "Seuls les brouillons validés peuvent être envoyés."
      );
    }

    if (!draft.providerDraftId) {
      throw new EmailDraftError(
        "PROVIDER_ERROR",
        "Brouillon Gmail introuvable côté provider."
      );
    }

    const provider = await getEmailProviderForTool(ctx);
    const result = await provider.sendDraft(draft.providerDraftId);

    return {
      draftId: draft.id,
      messageId: result.messageId,
      threadId: result.threadId,
      providerDraftId: draft.providerDraftId,
    };
  },
};
