export const runtime = "nodejs";

import { nanoid } from "nanoid";
import { and, asc, eq } from "drizzle-orm";
import { getOrCreateMailWorkspaceConversation } from "@/lib/mail/workspace";
import {
  deleteAttachmentById,
  indexDocumentAttachment,
  saveAttachmentFile,
} from "@/lib/attachments/storage";
import { validateFile } from "@/lib/attachments/validate";
import { getDb } from "@/lib/db";
import { attachments } from "@/lib/db/schema";
import { getSettings } from "@/lib/settings/service";

/** Libère de la place en retirant les PJ pending les plus anciennes. */
async function ensurePendingSlot(
  conversationId: string,
  maxPending: number
): Promise<void> {
  const db = getDb();
  const pending = await db.query.attachments.findMany({
    where: and(
      eq(attachments.conversationId, conversationId),
      eq(attachments.status, "pending")
    ),
    orderBy: [asc(attachments.createdAt)],
  });

  if (pending.length < maxPending) return;

  const overflow = pending.length - maxPending + 1;
  const toRemove = pending.slice(0, overflow);
  for (const row of toRemove) {
    await deleteAttachmentById(row.id);
  }
}

export async function POST(request: Request) {
  const form = await request.formData();
  const file = form.get("file");
  const conversationIdRaw = form.get("conversationId");

  if (!(file instanceof File)) {
    return Response.json({ error: "Fichier manquant" }, { status: 400 });
  }
  if (typeof conversationIdRaw !== "string" || !conversationIdRaw) {
    return Response.json({ error: "conversationId requis" }, { status: 400 });
  }

  const conversationId =
    conversationIdRaw === "mail-workspace"
      ? await getOrCreateMailWorkspaceConversation()
      : conversationIdRaw;

  const settings = await getSettings();
  const maxBytes = settings.maxAttachmentSizeMb * 1024 * 1024;
  const validation = validateFile({
    filename: file.name,
    mimeType: file.type || "application/octet-stream",
    sizeBytes: file.size,
    maxBytes,
  });

  if (!validation.ok) {
    return Response.json({ error: validation.error }, { status: 400 });
  }

  await ensurePendingSlot(conversationId, settings.maxAttachmentsPerMessage);

  const buffer = Buffer.from(await file.arrayBuffer());
  const localPath = await saveAttachmentFile(conversationId, file.name, buffer);
  const id = nanoid();
  const db = getDb();

  await db.insert(attachments).values({
    id,
    conversationId,
    type: validation.type,
    filename: file.name,
    mimeType: file.type || "application/octet-stream",
    localPath,
    sizeBytes: file.size,
    status: "pending",
  });

  let extractedCharCount = 0;
  if (validation.type === "document") {
    try {
      extractedCharCount = await indexDocumentAttachment(
        id,
        conversationId,
        localPath,
        file.type || "application/octet-stream",
        file.name
      );
    } catch (err) {
      // L’upload doit réussir même si l’extraction texte échoue (ex. PDF).
      console.warn(
        "[attachments/upload] indexation ignorée:",
        err instanceof Error ? err.message : err
      );
    }
  }

  const [row] = await db
    .select()
    .from(attachments)
    .where(eq(attachments.id, id))
    .limit(1);

  return Response.json({
    attachment: {
      ...row,
      extractedCharCount,
    },
  });
}
