import { z } from "zod";
import {
  persistEmailDraft,
  toEmailDraftPreview,
} from "@/lib/email/draft";
import type { Tool } from "../types";
import {
  getEmailProviderForTool,
  parseCsv,
  requireToolUserId,
  resolveRecipients,
} from "./helpers";
import { getOAuthAccount } from "@/lib/integrations/oauth";

const inputSchema = z.object({
  to: z
    .string()
    .min(1)
    .describe("Destinataires séparés par des virgules"),
  cc: z.string().optional().describe("Copie séparée par des virgules"),
  bcc: z.string().optional().describe("Copie cachée séparée par des virgules"),
  subject: z.string().min(1).describe("Objet du message"),
  bodyText: z.string().min(1).describe("Corps du message en texte brut"),
  threadId: z
    .string()
    .optional()
    .describe("ID du thread Gmail pour une réponse"),
  inReplyToMessageId: z
    .string()
    .optional()
    .describe("ID du message auquel répondre"),
});

export type EmailCreateDraftInput = z.infer<typeof inputSchema>;

export const emailCreateDraftTool: Tool<EmailCreateDraftInput> = {
  name: "email_create_draft",
  description:
    "Crée un brouillon Gmail pour toute demande d'écrire ou d'envoyer un mail (y compris à soi-même). L'envoi réel se fait ensuite via confirmation utilisateur (bouton Envoyer) — pas via un autre outil.",
  inputSchema,
  preferredRuntime: "local",
  async execute(input, ctx) {
    const userId = requireToolUserId(ctx);
    const provider = await getEmailProviderForTool(ctx);
    let accountEmail: string | null = null;
    try {
      const account = await getOAuthAccount(userId, "gmail");
      accountEmail = account?.accountEmail ?? null;
    } catch {
      accountEmail = null;
    }

    const to = resolveRecipients(input.to, accountEmail);
    const cc = parseCsv(input.cc);
    const bcc = parseCsv(input.bcc);

    if (to.length === 0) {
      throw new Error("Au moins un destinataire est requis.");
    }

    let inReplyToHeader: string | undefined;
    let referencesHeader: string | undefined;

    if (input.inReplyToMessageId) {
      const replyTarget = await provider.getMessage(input.inReplyToMessageId);
      inReplyToHeader = replyTarget.id;
      referencesHeader = replyTarget.id;
    }

    const draft = await provider.createDraft({
      to,
      cc,
      bcc,
      subject: input.subject,
      bodyText: input.bodyText,
      threadId: input.threadId,
      inReplyToMessageId: input.inReplyToMessageId,
      inReplyToHeader,
      referencesHeader,
    });

    const stored = await persistEmailDraft({
      userId,
      conversationId: ctx.conversationId,
      threadId: draft.threadId ?? input.threadId ?? null,
      provider: "gmail",
      providerDraftId: draft.providerDraftId,
      to,
      cc,
      bcc,
      subject: input.subject,
      bodyText: input.bodyText,
      inReplyToMessageId: input.inReplyToMessageId ?? null,
    });

    const preview = await toEmailDraftPreview(stored);

    return {
      ...preview,
      notice:
        "Brouillon créé — l'envoi nécessite une validation explicite de l'utilisateur.",
    };
  },
};
