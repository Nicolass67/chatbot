import { eq } from "drizzle-orm";
import { parseStoredMessageContent } from "@/lib/attachments/multimodal";
import { getDb } from "@/lib/db";
import { messages } from "@/lib/db/schema";

export type ConversationMessageDTO = {
  id: string;
  role: string;
  content: string;
  conversationId: string;
  createdAt: string;
  sources?: unknown[];
  attachments?: unknown[];
  [key: string]: unknown;
};

export type ConversationMessagesPayload = {
  messages: ConversationMessageDTO[];
  toolCalls: unknown[];
};

/** Shared loader for RSC page + GET /api/conversations/[id]/messages */
export async function loadConversationMessagesPayload(
  conversationId: string
): Promise<ConversationMessagesPayload> {
  const db = getDb();

  const [msgs, toolCalls] = await Promise.all([
    db.query.messages.findMany({
      where: eq(messages.conversationId, conversationId),
      orderBy: (m, { asc }) => [asc(m.createdAt)],
      with: { sources: true, attachments: true },
    }),
    db.query.toolCalls.findMany({
      where: (t, { eq: eqOp }) => eqOp(t.conversationId, conversationId),
      orderBy: (t, { asc }) => [asc(t.createdAt)],
    }),
  ]);

  const formatted = msgs.map((m) => {
    const { text } = parseStoredMessageContent(m.content);
    return {
      ...m,
      content: text || m.content,
      attachments: m.attachments ?? [],
    };
  });

  return { messages: formatted, toolCalls };
}
