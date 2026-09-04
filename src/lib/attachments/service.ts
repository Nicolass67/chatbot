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
  // Toujours lister les PJ (y compris images) en texte : le mode mail coupe souvent
  // la vision pour garder le tool-calling, et les docs ne sont pas multimodaux.
  const attachmentNotice =
    msgAttachments.length > 0
      ? `\n\n[Pièces jointes du message : ${msgAttachments
          .map((a) => `${a.filename} (id=${a.id}, type=${a.type})`)
          .join(", ")}]`
      : "";
  const textWithAttachments = `${text || ""}${attachmentNotice}`.trim();

  if (images.length > 0) {
    return buildMultimodalUserMessage(
      textWithAttachments || text || msg.content,
      images
    );
  }

  return {
    role: "user",
    content: textWithAttachments || msg.content,
  };
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
