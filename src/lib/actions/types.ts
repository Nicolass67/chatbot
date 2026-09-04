import { createHash } from "node:crypto";

export type ActionType =
  | "send_email"
  | "trash_email"
  | "create_directory"
  | "rename_file"
  | "move_file";

export type ActionStatus =
  | "proposed"
  | "pending_confirmation"
  | "confirmed"
  | "executing"
  | "completed"
  | "rejected"
  | "cancelled"
  | "expired"
  | "failed";

export type AuditStatus = "success" | "rejected" | "failed";

export type ActionErrorCode =
  | "NOT_FOUND"
  | "FORBIDDEN"
  | "INVALID_STATE"
  | "EXPIRED"
  | "ALREADY_USED"
  | "HASH_MISMATCH"
  | "POLICY_DENIED"
  | "DRAFT_NOT_FOUND"
  | "DRAFT_NOT_VALIDATED"
  | "MESSAGE_NOT_FOUND";

export class ActionError extends Error {
  readonly code: ActionErrorCode;

  constructor(code: ActionErrorCode, message: string) {
    super(message);
    this.name = "ActionError";
    this.code = code;
  }
}

export interface CreateSendActionInput {
  userId: string;
  conversationId: string;
  draftId: string;
  payloadHash: string;
}

export interface CreateTrashActionInput {
  userId: string;
  conversationId: string;
  messageId: string;
  payloadHash: string;
  messageSnapshot: {
    from: string;
    subject: string;
  };
}

export interface ConfirmSendActionInput {
  actionId: string;
  confirmationToken: string;
  userId: string;
  emailConnected?: boolean;
  grantedPermissions?: import("@/lib/policy").PermissionScope[];
}

export interface ConfirmTrashActionInput {
  actionId: string;
  confirmationToken: string;
  userId: string;
  emailConnected?: boolean;
  grantedPermissions?: import("@/lib/policy").PermissionScope[];
}

export function buildSendIdempotencyKey(
  draftId: string,
  payloadHash: string
): string {
  return `send_email:${draftId}:${payloadHash}`;
}

export function buildTrashIdempotencyKey(
  messageId: string,
  userId: string
): string {
  return `trash_email:${userId}:${messageId}`;
}

export function hashTrashPayload(parts: {
  messageId: string;
  from: string;
  subject: string;
}): string {
  const canonical = JSON.stringify({
    messageId: parts.messageId,
    from: parts.from,
    subject: parts.subject,
  });
  return createHash("sha256").update(canonical).digest("hex");
}

/** Durée de validité d'une action en attente de confirmation (30 min). */
export const PENDING_ACTION_TTL_MS = 30 * 60 * 1000;

export function computeExpiresAt(from = Date.now()): string {
  return new Date(from + PENDING_ACTION_TTL_MS).toISOString();
}

export function isActionExpired(expiresAt: string, now = Date.now()): boolean {
  return new Date(expiresAt).getTime() <= now;
}
