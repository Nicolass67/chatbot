import { and, desc, eq, lt } from "drizzle-orm";
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
  /** True when older messages exist beyond this page (paginated requests only). */
  hasMore?: boolean;
  /** Pass as `beforeId` to fetch the next older page. */
  nextBeforeId?: string;
};

export type LoadConversationMessagesOptions = {
  /** Newest page size. Omit = full history (web / legacy). */
  limit?: number;
  /** Load messages strictly older than this message id. */
  beforeId?: string;
};

function formatMessage(
  m: {
    id: string;
    role: string;
    content: string;
    conversationId: string;
    createdAt: string;
    sources?: unknown[] | null;
    attachments?: unknown[] | null;
  } & Record<string, unknown>
): ConversationMessageDTO {
  const { text } = parseStoredMessageContent(m.content);
  return {
    ...m,
    content: text || m.content,
    attachments: m.attachments ?? [],
  };
}

/**
 * Shared loader for RSC page + GET /api/conversations/[id]/messages.
 * - No `limit` → full chronological history (backward compatible).
 * - With `limit` → newest page (or older page if `beforeId`), oldest→newest order.
 */
export async function loadConversationMessagesPayload(
  conversationId: string,
  options: LoadConversationMessagesOptions = {}
): Promise<ConversationMessagesPayload> {
  const db = getDb();
  const limit =
    typeof options.limit === "number" && Number.isFinite(options.limit)
      ? Math.min(100, Math.max(1, Math.floor(options.limit)))
      : undefined;
  const beforeId = options.beforeId?.trim() || undefined;

  if (!limit) {
    const [msgs, toolCalls] = await Promise.all([
      db.query.messages.findMany({
        where: eq(messages.conversationId, conversationId),
        orderBy: (m, { asc: ascOp }) => [ascOp(m.createdAt)],
        with: { sources: true, attachments: true },
      }),
      db.query.toolCalls.findMany({
        where: (t, { eq: eqOp }) => eqOp(t.conversationId, conversationId),
        orderBy: (t, { asc: ascOp }) => [ascOp(t.createdAt)],
      }),
    ]);

    return {
      messages: msgs.map((m) => formatMessage(m)),
      toolCalls,
    };
  }

  let pivotCreatedAt: string | undefined;
  if (beforeId) {
    const pivot = await db.query.messages.findFirst({
      where: and(
        eq(messages.id, beforeId),
        eq(messages.conversationId, conversationId)
      ),
      columns: { id: true, createdAt: true },
    });
    if (!pivot) {
      return { messages: [], toolCalls: [], hasMore: false };
    }
    pivotCreatedAt = pivot.createdAt;
  }

  const whereClause =
    pivotCreatedAt != null
      ? and(
          eq(messages.conversationId, conversationId),
          lt(messages.createdAt, pivotCreatedAt)
        )
      : eq(messages.conversationId, conversationId);

  const rows = await db.query.messages.findMany({
    where: whereClause,
    orderBy: [desc(messages.createdAt)],
    limit: limit + 1,
    with: { sources: true, attachments: true },
  });

  const hasMore = rows.length > limit;
  const pageDesc = hasMore ? rows.slice(0, limit) : rows;
  const page = pageDesc.slice().reverse();
  const formatted = page.map((m) => formatMessage(m));
  const pageIds = new Set(formatted.map((m) => m.id));

  const toolCalls = await db.query.toolCalls.findMany({
    where: (t, { eq: eqOp }) => eqOp(t.conversationId, conversationId),
    orderBy: (t, { asc: ascOp }) => [ascOp(t.createdAt)],
  });
  const filteredToolCalls = toolCalls.filter((t) => {
    const mid = (t as { messageId?: string | null }).messageId;
    return !mid || pageIds.has(mid);
  });

  return {
    messages: formatted,
    toolCalls: filteredToolCalls,
    hasMore,
    nextBeforeId: formatted[0]?.id,
  };
}
