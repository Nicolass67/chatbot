export interface EditableMessage {
  id: string;
  role: string;
  content: string;
}

export function canStartEditingMessage(
  message: EditableMessage,
  isGenerating: boolean
): boolean {
  if (isGenerating) return false;
  if (message.role !== "user") return false;
  if (message.id.startsWith("pending-user-")) return false;
  return true;
}

export function applyEditToLocalMessages<T extends EditableMessage>(
  messages: T[],
  editMessageId: string,
  newContent: string
): T[] {
  const index = messages.findIndex((m) => m.id === editMessageId);
  if (index === -1) return messages;
  return messages.slice(0, index + 1).map((m, i) =>
    i === index ? { ...m, content: newContent } : m
  );
}

export function handleEditTextareaKeyDown(
  event: { key: string; shiftKey: boolean; preventDefault: () => void },
  onSubmit: () => void
): void {
  if (event.key !== "Enter" || event.shiftKey) return;
  event.preventDefault();
  onSubmit();
}
