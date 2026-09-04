import fs from "node:fs";
import path from "node:path";
import { eq, inArray } from "drizzle-orm";
import { nanoid } from "nanoid";
import { getDb } from "@/lib/db";
import { attachments, documentChunks } from "@/lib/db/schema";
import { estimateTokens } from "@/lib/context/token-estimator";
import { chunkText, extractTextFromFile } from "./extract";
import { buildStoragePath } from "./validate";

export function getAttachmentsRoot(): string {
  return path.join(process.cwd(), "data", "attachments");
}

export async function saveAttachmentFile(
  conversationId: string,
  filename: string,
  buffer: Buffer
): Promise<string> {
  const root = getAttachmentsRoot();
  const dir = path.join(root, conversationId);
  fs.mkdirSync(dir, { recursive: true });
  const localPath = buildStoragePath(root, conversationId, filename);
  fs.writeFileSync(localPath, buffer);
  return localPath;
}

export async function indexDocumentAttachment(
  attachmentId: string,
  conversationId: string,
  filePath: string,
  mimeType: string,
  filename: string
): Promise<number> {
  const text = await extractTextFromFile(filePath, mimeType, filename);
  const chunks = chunkText(text);
  const db = getDb();

  await db
    .delete(documentChunks)
    .where(eq(documentChunks.attachmentId, attachmentId));

  for (let i = 0; i < chunks.length; i++) {
    await db.insert(documentChunks).values({
      id: nanoid(),
      attachmentId,
      conversationId,
      chunkIndex: i,
      content: chunks[i]!,
      tokenEstimate: estimateTokens(chunks[i]!),
    });
  }

  await db
    .update(attachments)
    .set({ extractedCharCount: text.length })
    .where(eq(attachments.id, attachmentId));

  return text.length;
}

export function deleteAttachmentFile(localPath: string): void {
  try {
    if (fs.existsSync(localPath)) fs.unlinkSync(localPath);
  } catch {
    // ignore
  }
}

export async function deleteAttachmentById(id: string): Promise<boolean> {
  const db = getDb();
  const [row] = await db
    .select()
    .from(attachments)
    .where(eq(attachments.id, id))
    .limit(1);
  if (!row) return false;

  deleteAttachmentFile(row.localPath);
  await db.delete(attachments).where(eq(attachments.id, id));
  return true;
}

export async function attachToMessage(
  attachmentIds: string[],
  messageId: string
): Promise<void> {
  if (attachmentIds.length === 0) return;
  const db = getDb();
  await db
    .update(attachments)
    .set({ messageId, status: "attached" })
    .where(inArray(attachments.id, attachmentIds));
}

/** Marque des PJ comme utilisées (brouillon mail) pour ne plus bloquer la limite pending. */
export async function markAttachmentsAttached(
  attachmentIds: string[]
): Promise<void> {
  if (attachmentIds.length === 0) return;
  const db = getDb();
  await db
    .update(attachments)
    .set({ status: "attached" })
    .where(inArray(attachments.id, attachmentIds));
}

export async function getAttachmentsForMessage(messageId: string) {
  const db = getDb();
  return db
    .select()
    .from(attachments)
    .where(eq(attachments.messageId, messageId));
}

export async function getAttachmentsByIds(ids: string[]) {
  if (ids.length === 0) return [];
  const db = getDb();
  return db.select().from(attachments).where(inArray(attachments.id, ids));
}

export async function getPendingAttachments(conversationId: string) {
  const db = getDb();
  return db
    .select()
    .from(attachments)
    .where(eq(attachments.conversationId, conversationId));
}
