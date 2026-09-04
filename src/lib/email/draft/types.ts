import type { EmailDraft } from "@/lib/db/schema";

export type EmailDraftStatus = EmailDraft["status"];

export interface EmailDraftAttachmentPreview {
  id: string;
  filename: string;
  mimeType: string;
  sizeBytes: number;
}

export interface EmailDraftPreview {
  draftId: string;
  conversationId: string;
  to: string[];
  cc: string[];
  bcc: string[];
  subject: string;
  bodyText: string;
  status: EmailDraftStatus;
  contentHash: string;
  threadId?: string | null;
  inReplyToMessageId?: string | null;
  providerDraftId?: string | null;
  attachments: EmailDraftAttachmentPreview[];
  requiresConfirmation: true;
}

export interface PersistEmailDraftInput {
  userId: string;
  conversationId: string;
  threadId?: string | null;
  provider: "gmail";
  providerDraftId?: string | null;
  to: string[];
  cc?: string[];
  bcc?: string[];
  subject: string;
  bodyText: string;
  inReplyToMessageId?: string | null;
  attachmentIds?: string[];
}

export interface UpdateEmailDraftInput {
  to?: string[];
  cc?: string[];
  bcc?: string[];
  subject?: string;
  bodyText?: string;
  attachmentIds?: string[];
}

export class EmailDraftError extends Error {
  readonly code: string;

  constructor(code: string, message: string) {
    super(message);
    this.name = "EmailDraftError";
    this.code = code;
  }
}

export interface WritingPreference {
  id: string;
  content: string;
  category: string;
  importance: number;
}
