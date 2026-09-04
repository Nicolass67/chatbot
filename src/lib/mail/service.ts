import type {
  NormalizedEmailMessage,
  NormalizedEmailThread,
} from "@/lib/integrations/email/types";
import { getEmailProvider } from "@/lib/integrations/email";

export interface ListMailMessagesParams {
  userId: string;
  query?: string;
  label?: string;
  categoryQuery?: string;
  maxResults?: number;
}

export async function listMailMessages(
  params: ListMailMessagesParams
): Promise<NormalizedEmailMessage[]> {
  const provider = await getEmailProvider(params.userId);
  const maxResults = params.maxResults ?? 30;

  if (params.query?.trim()) {
    return provider.search({
      query: params.query.trim(),
      maxResults,
    });
  }

  if (params.categoryQuery?.trim()) {
    return provider.search({
      query: params.categoryQuery.trim(),
      maxResults,
    });
  }

  const labelIds = params.label ? [params.label] : ["INBOX"];

  return provider.listMessages({
    labelIds,
    maxResults,
  });
}

export async function getMailMessage(
  userId: string,
  messageId: string
): Promise<NormalizedEmailMessage> {
  const provider = await getEmailProvider(userId);
  return provider.getMessage(messageId);
}

export async function getMailThread(
  userId: string,
  threadId: string
): Promise<NormalizedEmailThread> {
  const provider = await getEmailProvider(userId);
  return provider.getThread(threadId);
}

export async function markMailMessageRead(
  userId: string,
  messageId: string
): Promise<void> {
  const provider = await getEmailProvider(userId);
  await provider.markMessageRead(messageId);
}

export function toPublicMessageSummary(message: NormalizedEmailMessage) {
  return {
    id: message.id,
    threadId: message.threadId,
    from: message.from,
    subject: message.subject,
    snippet: message.snippet,
    date: message.date,
    isUnread: message.isUnread,
    hasAttachments: message.hasAttachments,
  };
}

export function toPublicThread(thread: NormalizedEmailThread) {
  return {
    id: thread.id,
    subject: thread.subject,
    participants: thread.participants,
    messages: thread.messages.map((m) => ({
      id: m.id,
      threadId: m.threadId,
      from: m.from,
      to: m.to,
      cc: m.cc,
      subject: m.subject,
      date: m.date,
      snippet: m.snippet,
      bodyText: m.bodyText,
      bodyHtml: m.bodyHtml,
      isUnread: m.isUnread,
      hasAttachments: m.hasAttachments,
      attachments: m.attachments.map((a) => ({
        id: a.id,
        filename: a.filename,
        mimeType: a.mimeType,
        sizeBytes: a.sizeBytes,
      })),
    })),
  };
}
