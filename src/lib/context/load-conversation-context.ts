import { eq } from "drizzle-orm";
import { DIRECT_INJECT_MAX_CHARS } from "@/lib/attachments/constants";
import { buildDocumentContext } from "@/lib/attachments/rag";
import {
  dbMessageToChatMessage,
  getConversationAttachments,
  loadAttachmentsForMessages,
} from "@/lib/attachments/service";
import { contentToPlainText } from "@/lib/runtime/capabilities";
import { getDb } from "@/lib/db";
import { conversationSummaries, messages } from "@/lib/db/schema";
import { memoryRetriever } from "@/lib/memory/search";
import { getSettings } from "@/lib/settings/service";
import {
  buildContextWithSnapshot,
  type ContextSnapshot,
} from "./snapshot";

export interface LoadContextOptions {
  conversationId: string;
  query?: string;
  attachmentIds?: string[];
}

export async function loadConversationContextSnapshot(
  options: LoadContextOptions
): Promise<ContextSnapshot> {
  const { conversationId, query, attachmentIds = [] } = options;
  const settings = await getSettings();
  const db = getDb();

  const allDbMessages = await db.query.messages.findMany({
    where: eq(messages.conversationId, conversationId),
    orderBy: (m, { asc }) => [asc(m.createdAt)],
  });

  const summaryRow = await db.query.conversationSummaries.findFirst({
    where: eq(conversationSummaries.conversationId, conversationId),
  });

  let recentDbMessages = allDbMessages;
  if (summaryRow?.coversUntilMessageId) {
    const idx = allDbMessages.findIndex(
      (m) => m.id === summaryRow.coversUntilMessageId
    );
    if (idx >= 0) recentDbMessages = allDbMessages.slice(idx + 1);
  }

  const attachmentMap = await loadAttachmentsForMessages(
    recentDbMessages.map((m) => m.id)
  );

  const recentMessages = [];
  for (const m of recentDbMessages.slice(-settings.recentMessagesCount)) {
    const chatMsg = await dbMessageToChatMessage(m, attachmentMap);
    if (chatMsg) recentMessages.push(chatMsg);
  }

  const searchQuery =
    query ??
    contentToPlainText(
      recentMessages.filter((m) => m.role === "user").at(-1)?.content ?? ""
    ) ??
    "";

  const pendingAttachments = attachmentIds.length
    ? await getConversationAttachments(conversationId, attachmentIds)
    : [];

  const documentContext = await buildDocumentContext(
    conversationId,
    pendingAttachments,
    searchQuery,
    DIRECT_INJECT_MAX_CHARS
  );

  const relevantMemories = settings.memoryEnabled
    ? await memoryRetriever.search(searchQuery)
    : [];

  const { snapshot } = buildContextWithSnapshot({
    systemPrompt: settings.systemPrompt,
    memories: relevantMemories,
    summary: summaryRow?.content ?? null,
    documentContext,
    toolMessages: [],
    recentMessages,
    settings,
    totalMessageCount: allDbMessages.length,
  });

  return snapshot;
}
