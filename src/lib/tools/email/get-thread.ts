import { z } from "zod";
import type { Tool } from "../types";
import {
  getEmailProviderForTool,
  toMessagePreview,
  withUntrustedNotice,
} from "./helpers";

const inputSchema = z.object({
  threadId: z.string().min(1).describe("Identifiant du fil de conversation Gmail"),
});

export type EmailGetThreadInput = z.infer<typeof inputSchema>;

export const emailGetThreadTool: Tool<EmailGetThreadInput> = {
  name: "email_get_thread",
  description:
    "Récupère un fil de conversation Gmail complet avec tous les messages du thread.",
  inputSchema,
  preferredRuntime: "local",
  async execute(input, ctx) {
    const provider = await getEmailProviderForTool(ctx);
    const thread = await provider.getThread(input.threadId);

    return withUntrustedNotice({
      threadId: thread.id,
      subject: thread.subject,
      participants: thread.participants,
      messageCount: thread.messages.length,
      messages: thread.messages.map(toMessagePreview),
    });
  },
};
