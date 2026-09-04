export interface OrderedMessage {
  id: string;
  role: string;
  createdAt: string;
}

export function findMessageIndex<T extends { id: string }>(
  orderedMessages: T[],
  messageId: string
): number {
  return orderedMessages.findIndex((m) => m.id === messageId);
}

export function getDescendantMessageIds(
  orderedMessages: OrderedMessage[],
  editMessageId: string
): string[] {
  const index = findMessageIndex(orderedMessages, editMessageId);
  if (index === -1) return [];
  return orderedMessages.slice(index + 1).map((m) => m.id);
}

export function shouldInvalidateSummary(
  coversUntilMessageId: string | null | undefined,
  editMessageId: string,
  descendantIds: string[],
  orderedMessages: OrderedMessage[]
): boolean {
  if (!coversUntilMessageId) return false;
  if (descendantIds.includes(coversUntilMessageId)) return true;

  const editIndex = findMessageIndex(orderedMessages, editMessageId);
  const coverIndex = findMessageIndex(orderedMessages, coversUntilMessageId);
  if (editIndex === -1 || coverIndex === -1) return false;

  return coverIndex >= editIndex;
}

export function canSubmitEditedMessage(
  text: string,
  attachmentCount: number
): boolean {
  return text.trim().length > 0 || attachmentCount > 0;
}

export function buildContextMessagesAfterEdit<T extends { id: string }>(
  orderedMessages: T[],
  editMessageId: string
): T[] {
  const index = findMessageIndex(orderedMessages, editMessageId);
  if (index === -1) return orderedMessages;
  return orderedMessages.slice(0, index + 1);
}
