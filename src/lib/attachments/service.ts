import { getDb } from "@/lib/db";
import type { Attachment } from "@/lib/db/schema";
import type { ChatMessage } from "@/lib/runtime/types";
import {
  buildMultimodalUserMessage,
  parseStoredMessageContent,
} from "./multimodal";

export async function loadAttachmentsForMessages(
  messageIds: string[]
): Promise<Map<string, Attachment[]>> {
  if (messageIds.length === 0) return new Map();
  const db = getDb();
  const rows = await db.query.attachments.findMany({
    where: (a, { inArray }) => inArray(a.messageId, messageIds),
  });
  const map = new Map<string, Attachment[]>();
  for (const row of rows) {
    if (!row.messageId) continue;
    const list = map.get(row.messageId) ?? [];
    list.push(row);
    map.set(row.messageId, list);
  }
  return map;
}

export async function dbMessageToChatMessage(
  msg: { id: string; role: string; content: string },
  attachmentMap: Map<string, Attachment[]>
): Promise<ChatMessage | null> {
  if (msg.role !== "user" && msg.role !== "assistant") return null;

  if (msg.role === "assistant") {
    return { role: "assistant", content: msg.content };
  }

  const { text, attachmentIds } = parseStoredMessageContent(msg.content);
  let msgAttachments = attachmentMap.get(msg.id) ?? [];
  if (msgAttachments.length === 0 && attachmentIds.length > 0) {
    const db = getDb();
    msgAttachments = await db.query.attachments.findMany({
      where: (a, { inArray }) => inArray(a.id, attachmentIds),
    });
  }

  const images = msgAttachments.filter((a) => a.type === "image");
  if (images.length > 0) {
    return buildMultimodalUserMessage(text, images);
  }

  return { role: "user", content: text || msg.content };
}

export async function getConversationAttachments(
  conversationId: string,
  ids: string[]
): Promise<Attachment[]> {
  if (ids.length === 0) return [];
  const db = getDb();
  return db.query.attachments.findMany({
    where: (a, { and, eq, inArray }) =>
      and(eq(a.conversationId, conversationId), inArray(a.id, ids)),
  });
}
