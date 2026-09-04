import { z } from "zod";
import type { Tool } from "../types";
import {
  EMAIL_LIST_DEFAULT_MAX,
  getEmailProviderForTool,
  toMessagePreview,
  withUntrustedNotice,
} from "./helpers";

const inputSchema = z.object({
  maxResults: z
    .number()
    .min(1)
    .max(50)
    .optional()
    .describe("Nombre maximum de messages (défaut 20)"),
  label: z
    .string()
    .optional()
    .describe("Label Gmail, ex: INBOX, UNREAD, STARRED"),
  after: z
    .string()
    .optional()
    .describe("Date ISO — ne retourner que les emails après cette date"),
});

export type EmailListInput = z.infer<typeof inputSchema>;

export const emailListTool: Tool<EmailListInput> = {
  name: "email_list",
  description:
    "Liste les emails récents du compte Gmail connecté. Utilise label pour filtrer (INBOX, UNREAD).",
  inputSchema,
  preferredRuntime: "local",
  async execute(input, ctx) {
    const provider = await getEmailProviderForTool(ctx);
    const messages = await provider.listMessages({
      maxResults: input.maxResults ?? EMAIL_LIST_DEFAULT_MAX,
      labelIds: input.label ? [input.label] : undefined,
      after: input.after,
    });

    return withUntrustedNotice({
      accountEmail: provider.accountEmail,
      count: messages.length,
      messages: messages.map(toMessagePreview),
    });
  },
};
