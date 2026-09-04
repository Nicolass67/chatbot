import { z } from "zod";
import type { Tool } from "../types";
import {
  EMAIL_LIST_DEFAULT_MAX,
  getEmailProviderForTool,
  toMessagePreview,
  withUntrustedNotice,
} from "./helpers";

const inputSchema = z.object({
  query: z
    .string()
    .min(1)
    .describe("Requête de recherche Gmail (syntaxe Gmail supportée)"),
  maxResults: z
    .number()
    .min(1)
    .max(50)
    .optional()
    .describe("Nombre maximum de résultats (défaut 20)"),
});

export type EmailSearchInput = z.infer<typeof inputSchema>;

export const emailSearchTool: Tool<EmailSearchInput> = {
  name: "email_search",
  description:
    "Recherche des emails dans Gmail avec la syntaxe de recherche Gmail (from:, to:, is:unread, subject:, etc.).",
  inputSchema,
  preferredRuntime: "local",
  async execute(input, ctx) {
    const provider = await getEmailProviderForTool(ctx);
    const messages = await provider.search({
      query: input.query,
      maxResults: input.maxResults ?? EMAIL_LIST_DEFAULT_MAX,
    });

    return withUntrustedNotice({
      query: input.query,
      accountEmail: provider.accountEmail,
      count: messages.length,
      messages: messages.map(toMessagePreview),
    });
  },
};
