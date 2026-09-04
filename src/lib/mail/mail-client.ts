import type { EmailDraftPreview } from "@/lib/email/draft/types";
import type { ConfirmSendEmailResult } from "@/lib/email/send/types";
import type { SendProposalResponse } from "@/lib/email/email-client";
import type { ProposeTrashEmailResult } from "@/lib/email/trash/types";
import type { OAuthAccountPublic } from "@/lib/integrations/oauth/types";

export class MailApiError extends Error {
  readonly code: string;
  readonly status: number;

  constructor(status: number, code: string, message: string) {
    super(message);
    this.name = "MailApiError";
    this.code = code;
    this.status = status;
  }
}

async function readJson<T>(response: Response): Promise<T> {
  const text = await response.text();
  if (!text.trim()) {
    throw new MailApiError(
      response.status,
      "EMPTY_RESPONSE",
      "Réponse vide du serveur"
    );
  }
  try {
    return JSON.parse(text) as T;
  } catch {
    throw new MailApiError(
      response.status,
      "INVALID_JSON",
      "Réponse serveur invalide"
    );
  }
}

async function throwIfNotOk(response: Response): Promise<void> {
  if (response.ok) return;
  try {
    const body = await readJson<{ error?: string; code?: string }>(response);
    throw new MailApiError(
      response.status,
      body.code ?? "UNKNOWN",
      body.error ?? "Erreur mail"
    );
  } catch (error) {
    if (error instanceof MailApiError) throw error;
    throw new MailApiError(
      response.status,
      "UNKNOWN",
      `Erreur serveur (${response.status})`
    );
  }
}

export interface MailMessageSummary {
  id: string;
  threadId: string;
  from: { email: string; name?: string };
  subject: string;
  snippet: string;
  date: string;
  isUnread: boolean;
  hasAttachments: boolean;
}

export interface MailThreadMessage {
  id: string;
  threadId: string;
  from: { email: string; name?: string };
  to: { email: string; name?: string }[];
  cc: { email: string; name?: string }[];
  subject: string;
  date: string;
  snippet: string;
  bodyText: string;
  bodyHtml?: string;
  isUnread: boolean;
  hasAttachments: boolean;
  attachments?: Array<{
    id: string;
    filename: string;
    mimeType: string;
    sizeBytes: number;
  }>;
}

export interface MailThread {
  id: string;
  subject: string;
  participants: { email: string; name?: string }[];
  messages: MailThreadMessage[];
}

export async function fetchMailMessages(params: {
  q?: string;
  label?: string;
  category?: string;
}): Promise<MailMessageSummary[]> {
  const search = new URLSearchParams();
  if (params.q) search.set("q", params.q);
  if (params.label) search.set("label", params.label);
  if (params.category) search.set("category", params.category);
  const qs = search.toString();
  const response = await fetch(`/api/mail/messages${qs ? `?${qs}` : ""}`);
  await throwIfNotOk(response);
  const data = await readJson<{ messages: MailMessageSummary[] }>(response);
  return data.messages;
}

export async function fetchMailThread(threadId: string): Promise<MailThread> {
  const response = await fetch(`/api/mail/threads/${threadId}`);
  await throwIfNotOk(response);
  return readJson<MailThread>(response);
}

export async function markMailMessageRead(messageId: string): Promise<void> {
  const response = await fetch(`/api/mail/messages/${messageId}/read`, {
    method: "POST",
  });
  await throwIfNotOk(response);
}

export async function summarizeMailThread(
  threadId: string,
  model?: string
): Promise<string> {
  const response = await fetch("/api/mail/ai/summarize", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ threadId, model }),
  });
  await throwIfNotOk(response);
  const data = await readJson<{ summary: string }>(response);
  return data.summary;
}

export async function suggestMailReply(input: {
  threadId: string;
  instruction?: string;
  model?: string;
  attachmentIds?: string[];
}): Promise<{ draft: EmailDraftPreview }> {
  const response = await fetch("/api/mail/ai/suggest-reply", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(input),
  });
  await throwIfNotOk(response);
  const data = await readJson<{ draft: EmailDraftPreview }>(response);
  return data;
}

export async function mailAssistantChat(input: {
  message: string;
  threadId?: string;
  draftId?: string;
  model?: string;
  accountEmail?: string;
  attachmentNames?: string[];
  attachmentIds?: string[];
}): Promise<{
  reply: string;
  draft?: EmailDraftPreview;
  intent?: {
    action: string;
    includeAttachments: boolean;
    reason: string;
  };
  applied?: {
    action: string;
    attachmentsAdded: string[];
  };
}> {
  const response = await fetch("/api/mail/ai/chat", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(input),
  });
  await throwIfNotOk(response);
  return readJson(response);
}

export async function proposeMailTrash(
  messageId: string
): Promise<ProposeTrashEmailResult> {
  const response = await fetch("/api/mail/actions/trash", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ messageId }),
  });
  await throwIfNotOk(response);
  return readJson<ProposeTrashEmailResult>(response);
}

export async function confirmMailTrash(
  actionId: string,
  confirmationToken: string
): Promise<{ messageId: string; status: string }> {
  const response = await fetch(`/api/mail/actions/${actionId}/confirm`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ confirmationToken }),
  });
  await throwIfNotOk(response);
  return readJson<{ messageId: string; status: string }>(response);
}

export {
  fetchOAuthAccounts,
  fetchEmailDraft,
  updateEmailDraft,
  validateEmailDraft,
  proposeEmailSend,
  confirmEmailSend,
  cancelEmailSendAction as cancelEmailSend,
} from "@/lib/email/email-client";

export type { OAuthAccountPublic, SendProposalResponse, ConfirmSendEmailResult };
