import type { EmailDraftPreview } from "@/lib/email/draft/types";
import type {
  ConfirmSendEmailResult,
  ProposeSendEmailResult,
  PublicPendingAction,
} from "@/lib/email/send/types";
import type { OAuthAccountPublic } from "@/lib/integrations/oauth/types";

export class EmailApiError extends Error {
  readonly code: string;
  readonly status: number;

  constructor(status: number, code: string, message: string) {
    super(message);
    this.name = "EmailApiError";
    this.code = code;
    this.status = status;
  }
}

async function readJson<T>(response: Response): Promise<T> {
  return (await response.json()) as T;
}

async function throwIfNotOk(response: Response): Promise<void> {
  if (response.ok) return;
  const body = await readJson<{ error?: string; code?: string }>(response);
  throw new EmailApiError(
    response.status,
    body.code ?? "UNKNOWN",
    body.error ?? "Erreur email"
  );
}

export interface OAuthAccountsResponse {
  configured: boolean;
  accounts: OAuthAccountPublic[];
  redirectUri?: string | null;
}

export interface SendProposalResponse extends ProposeSendEmailResult {
  draft: EmailDraftPreview;
}

export interface UpdateDraftInput {
  to?: string[];
  cc?: string[];
  bcc?: string[];
  subject?: string;
  bodyText?: string;
  attachmentIds?: string[];
}

export async function fetchOAuthAccounts(
  fetchFn: typeof fetch = fetch
): Promise<OAuthAccountsResponse> {
  if (fetchFn === fetch) {
    const { cachedGetJson } = await import("@/lib/client/fetch-cache");
    const res = await cachedGetJson<OAuthAccountsResponse>(
      "/api/oauth/accounts",
      { ttlMs: 30_000 }
    );
    if (!res.ok) {
      throw new Error("Impossible de charger les comptes OAuth");
    }
    return res.data;
  }
  const response = await fetchFn("/api/oauth/accounts");
  await throwIfNotOk(response);
  return readJson<OAuthAccountsResponse>(response);
}

export async function disconnectGmail(
  fetchFn: typeof fetch = fetch
): Promise<void> {
  const response = await fetchFn("/api/oauth/gmail/disconnect", {
    method: "POST",
  });
  await throwIfNotOk(response);
}

export async function fetchEmailDraft(
  draftId: string,
  fetchFn: typeof fetch = fetch
): Promise<EmailDraftPreview> {
  const response = await fetchFn(`/api/email/drafts/${draftId}`);
  await throwIfNotOk(response);
  return readJson<EmailDraftPreview>(response);
}

export async function updateEmailDraft(
  draftId: string,
  patch: UpdateDraftInput,
  fetchFn: typeof fetch = fetch
): Promise<EmailDraftPreview> {
  const response = await fetchFn(`/api/email/drafts/${draftId}`, {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(patch),
  });
  await throwIfNotOk(response);
  return readJson<EmailDraftPreview>(response);
}

export async function validateEmailDraft(
  draftId: string,
  fetchFn: typeof fetch = fetch
): Promise<EmailDraftPreview> {
  const response = await fetchFn(`/api/email/drafts/${draftId}/validate`, {
    method: "POST",
  });
  await throwIfNotOk(response);
  return readJson<EmailDraftPreview>(response);
}

export async function proposeEmailSend(
  draftId: string,
  fetchFn: typeof fetch = fetch
): Promise<SendProposalResponse> {
  const response = await fetchFn("/api/email/actions/send", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ draftId }),
  });
  await throwIfNotOk(response);
  return readJson<SendProposalResponse>(response);
}

export async function confirmEmailSend(
  actionId: string,
  input: { confirmationToken: string; conversationId: string },
  fetchFn: typeof fetch = fetch
): Promise<ConfirmSendEmailResult> {
  const response = await fetchFn(`/api/email/actions/${actionId}/confirm`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(input),
  });
  await throwIfNotOk(response);
  return readJson<ConfirmSendEmailResult>(response);
}

export async function cancelEmailSendAction(
  actionId: string,
  fetchFn: typeof fetch = fetch
): Promise<PublicPendingAction> {
  const response = await fetchFn(`/api/email/actions/${actionId}/cancel`, {
    method: "POST",
  });
  await throwIfNotOk(response);
  return readJson<PublicPendingAction>(response);
}

export async function fetchPendingSendAction(
  conversationId: string,
  fetchFn: typeof fetch = fetch
): Promise<PublicPendingAction | null> {
  const response = await fetchFn(
    `/api/email/actions/pending?conversationId=${encodeURIComponent(conversationId)}`
  );
  await throwIfNotOk(response);
  const body = await readJson<{ action: PublicPendingAction | null }>(response);
  return body.action;
}
