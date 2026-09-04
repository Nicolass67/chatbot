import { inArray, eq } from "drizzle-orm";
import {
  parseStoredMessageContent,
  serializeContentForStorage,
} from "@/lib/attachments/multimodal";
import { getDb } from "@/lib/db";
import { conversationSummaries, messages } from "@/lib/db/schema";
import {
  canSubmitEditedMessage,
  getDescendantMessageIds,
  shouldInvalidateSummary,
} from "@/lib/agent/edit-message-utils";

export interface ApplyMessageEditInput {
  conversationId: string;
  editMessageId: string;
  newText: string;
  attachmentIds?: string[];
}

export interface ApplyMessageEditResult {
  updatedMessageId: string;
  deletedMessageIds: string[];
  attachmentIds: string[];
}

export async function applyMessageEdit(
  input: ApplyMessageEditInput
): Promise<ApplyMessageEditResult> {
  const db = getDb();

  const allDbMessages = await db.query.messages.findMany({
    where: eq(messages.conversationId, input.conversationId),
    orderBy: (m, { asc }) => [asc(m.createdAt)],
  });

  const editMessage = allDbMessages.find((m) => m.id === input.editMessageId);
  if (!editMessage) {
    throw new Error("Message introuvable.");
  }
  if (editMessage.role !== "user") {
    throw new Error("Seuls les messages utilisateur peuvent être modifiés.");
  }

  const stored = parseStoredMessageContent(editMessage.content);
  const attachmentIds =
    input.attachmentIds !== undefined
      ? input.attachmentIds
      : stored.attachmentIds;

  if (!canSubmitEditedMessage(input.newText, attachmentIds.length)) {
    throw new Error("Le message ne peut pas être vide.");
  }

  const descendantIds = getDescendantMessageIds(allDbMessages, input.editMessageId);

  await db
    .update(messages)
    .set({
      content: serializeContentForStorage(input.newText, attachmentIds),
    })
    .where(eq(messages.id, input.editMessageId));

  if (descendantIds.length > 0) {
    await db.delete(messages).where(inArray(messages.id, descendantIds));
  }

  const summary = await db.query.conversationSummaries.findFirst({
    where: eq(conversationSummaries.conversationId, input.conversationId),
  });

  if (
    summary &&
    shouldInvalidateSummary(
      summary.coversUntilMessageId,
      input.editMessageId,
      descendantIds,
      allDbMessages
    )
  ) {
    await db
      .delete(conversationSummaries)
      .where(eq(conversationSummaries.id, summary.id));
  }

  return {
    updatedMessageId: input.editMessageId,
    deletedMessageIds: descendantIds,
    attachmentIds,
  };
}
