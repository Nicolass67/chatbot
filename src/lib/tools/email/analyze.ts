import { z } from "zod";
import type { NormalizedEmailMessage } from "@/lib/integrations/email";
import type { Tool } from "../types";
import {
  EMAIL_ANALYZE_DEFAULT_MAX,
  getEmailProviderForTool,
  parseCsv,
  toMessagePreview,
  withUntrustedNotice,
} from "./helpers";

const inputSchema = z.object({
  threadIds: z
    .string()
    .optional()
    .describe("IDs de threads séparés par des virgules"),
  messageIds: z
    .string()
    .optional()
    .describe("IDs de messages séparés par des virgules"),
  query: z
    .string()
    .optional()
    .describe("Recherche Gmail — analyse les premiers résultats"),
  maxItems: z
    .number()
    .min(1)
    .max(20)
    .optional()
    .describe("Nombre max d'emails à inclure (défaut 10)"),
});

export type EmailAnalyzeInput = z.infer<typeof inputSchema>;

function dedupeMessages(messages: NormalizedEmailMessage[]) {
  const seen = new Set<string>();
  const result: NormalizedEmailMessage[] = [];
  for (const message of messages) {
    if (seen.has(message.id)) continue;
    seen.add(message.id);
    result.push(message);
  }
  return result;
}

export const emailAnalyzeTool: Tool<EmailAnalyzeInput> = {
  name: "email_analyze",
  description:
    "Charge des emails pour analyse (priorités, réponses attendues, synthèse). Fournir threadIds, messageIds ou query. L'analyse sémantique est faite par l'assistant sur ces données.",
  inputSchema,
  preferredRuntime: "local",
  async execute(input, ctx) {
    const threadIds = parseCsv(input.threadIds);
    const messageIds = parseCsv(input.messageIds);
    const maxItems = input.maxItems ?? EMAIL_ANALYZE_DEFAULT_MAX;

    if (threadIds.length === 0 && messageIds.length === 0 && !input.query?.trim()) {
      throw new Error(
        "Indiquez threadIds, messageIds ou query pour email_analyze."
      );
    }

    const provider = await getEmailProviderForTool(ctx);
    const collected: NormalizedEmailMessage[] = [];

    for (const threadId of threadIds) {
      if (collected.length >= maxItems) break;
      const thread = await provider.getThread(threadId);
      collected.push(...thread.messages);
    }

    for (const messageId of messageIds) {
      if (collected.length >= maxItems) break;
      collected.push(await provider.getMessage(messageId));
    }

    if (input.query?.trim() && collected.length < maxItems) {
      const found = await provider.search({
        query: input.query.trim(),
        maxResults: maxItems,
      });
      collected.push(...found);
    }

    const messages = dedupeMessages(collected).slice(0, maxItems);

    return withUntrustedNotice({
      accountEmail: provider.accountEmail,
      itemCount: messages.length,
      items: messages.map((message) => ({
        ...toMessagePreview(message),
        labels: message.labelIds,
      })),
      analysisHint:
        "Analyse ces emails pour identifier ceux nécessitant une réponse, les urgences et les actions suggérées.",
    });
  },
};
