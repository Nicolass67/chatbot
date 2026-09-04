export interface ProposeTrashEmailResult {
  actionId: string;
  messageId: string;
  conversationId: string;
  status: string;
  expiresAt: string;
  confirmationToken: string;
  payloadHash: string;
  messageSnapshot: {
    from: string;
    subject: string;
  };
}

export interface ConfirmTrashEmailResult {
  actionId: string;
  messageId: string;
  status: "completed";
}

export interface PublicTrashAction {
  actionId: string;
  messageId: string;
  conversationId: string;
  status: string;
  expiresAt: string;
  payloadHash: string;
  confirmationToken: string;
  messageSnapshot?: {
    from: string;
    subject: string;
  };
}
