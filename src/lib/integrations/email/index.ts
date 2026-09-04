export {
  getEmailProvider,
  isEmailProviderConnected,
} from "./factory";
export { GmailProvider } from "./gmail/provider";
export { createGmailApiClient } from "./gmail/client";
export {
  buildGmailListQuery,
  buildGmailRawMessage,
  normalizeGmailMessage,
  normalizeGmailThread,
} from "./gmail/normalizer";
export type {
  EmailAddress,
  EmailAttachmentMeta,
  EmailProvider,
  ListMessagesParams,
  NormalizedDraft,
  NormalizedDraftInput,
  NormalizedEmailMessage,
  NormalizedEmailThread,
  ProviderCapabilities,
  SearchMessagesParams,
  SendDraftResult,
} from "./types";
export {
  EmailNotConnectedError,
  EmailProviderError,
} from "./types";
