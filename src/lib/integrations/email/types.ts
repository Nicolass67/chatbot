export interface EmailAddress {
  email: string;
  name?: string;
}

export interface EmailAttachmentMeta {
  id: string;
  filename: string;
  mimeType: string;
  sizeBytes: number;
}

export interface NormalizedEmailMessage {
  id: string;
  threadId: string;
  from: EmailAddress;
  to: EmailAddress[];
  cc: EmailAddress[];
  bcc: EmailAddress[];
  subject: string;
  date: string;
  snippet: string;
  bodyText: string;
  bodyHtml?: string;
  labelIds: string[];
  hasAttachments: boolean;
  attachments: EmailAttachmentMeta[];
  isUnread: boolean;
}

export interface NormalizedEmailThread {
  id: string;
  subject: string;
  messages: NormalizedEmailMessage[];
  participants: EmailAddress[];
}

export interface OutgoingEmailAttachment {
  filename: string;
  mimeType: string;
  /** Contenu binaire en base64 standard (pas base64url). */
  contentBase64: string;
}

export interface NormalizedDraftInput {
  threadId?: string;
  inReplyToMessageId?: string;
  inReplyToHeader?: string;
  referencesHeader?: string;
  to: string[];
  cc?: string[];
  bcc?: string[];
  subject: string;
  bodyText: string;
  bodyHtml?: string;
  attachments?: OutgoingEmailAttachment[];
}

export interface NormalizedDraft {
  providerDraftId: string;
  threadId?: string;
  messageId?: string;
  to: string[];
  cc: string[];
  bcc: string[];
  subject: string;
  bodyText: string;
}

export interface ProviderCapabilities {
  provider: "gmail";
  threads: boolean;
  drafts: boolean;
  search: boolean;
  send: boolean;
  trash: boolean;
  attachments: boolean;
  markRead: boolean;
}

export interface ListMessagesParams {
  query?: string;
  maxResults?: number;
  labelIds?: string[];
  after?: string;
  pageToken?: string;
}

export interface SearchMessagesParams {
  query: string;
  maxResults?: number;
  pageToken?: string;
}

export interface MailMessagesPage {
  messages: NormalizedEmailMessage[];
  nextPageToken: string | null;
  resultSizeEstimate: number | null;
}

export interface SendDraftResult {
  messageId: string;
  threadId: string;
}

export interface EmailProvider {
  readonly capabilities: ProviderCapabilities;
  readonly accountEmail: string;
  listMessages(params: ListMessagesParams): Promise<NormalizedEmailMessage[]>;
  /** Pagination Gmail (pageToken + estimate). */
  listMessagesPage(params: ListMessagesParams): Promise<MailMessagesPage>;
  getMessage(messageId: string): Promise<NormalizedEmailMessage>;
  getThread(threadId: string): Promise<NormalizedEmailThread>;
  search(params: SearchMessagesParams): Promise<NormalizedEmailMessage[]>;
  searchPage(params: SearchMessagesParams): Promise<MailMessagesPage>;
  createDraft(input: NormalizedDraftInput): Promise<NormalizedDraft>;
  sendDraft(providerDraftId: string): Promise<SendDraftResult>;
  /** Supprime un brouillon provider (best-effort ; ignore NOT_FOUND). */
  deleteDraft(providerDraftId: string): Promise<void>;
  trashMessage(messageId: string): Promise<void>;
  markMessageRead(messageId: string): Promise<void>;
  getAttachment(
    messageId: string,
    attachmentId: string
  ): Promise<{ data: Buffer; size: number }>;
}

export class EmailProviderError extends Error {
  readonly code: string;

  constructor(code: string, message: string) {
    super(message);
    this.name = "EmailProviderError";
    this.code = code;
  }
}

export class EmailNotConnectedError extends EmailProviderError {
  constructor() {
    super("EMAIL_NOT_CONNECTED", "Aucun compte Gmail connecté.");
  }
}
