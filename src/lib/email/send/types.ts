export interface SendEmailExecutionResult {
  draftId: string;
  messageId: string;
  threadId: string;
  providerDraftId?: string;
}

export interface ProposeSendEmailResult {
  actionId: string;
  draftId: string;
  conversationId: string;
  status: string;
  expiresAt: string;
  confirmationToken: string;
  payloadHash: string;
}

export interface ConfirmSendEmailResult {
  actionId: string;
  draftId: string;
  status: "completed";
  messageId: string;
  threadId: string;
}

export interface PublicPendingAction {
  actionId: string;
  draftId: string | null;
  conversationId: string;
  status: string;
  expiresAt: string;
  payloadHash: string;
  confirmedAt?: string | null;
  executedAt?: string | null;
  errorCode?: string | null;
  errorMessage?: string | null;
}
