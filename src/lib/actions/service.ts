import { createHash } from "node:crypto";
import { nanoid } from "nanoid";
import { and, desc, eq, lt } from "drizzle-orm";
import { getDb } from "@/lib/db";
import { logActionAudit } from "@/lib/observability/action-logger";
import {
  actionAuditLog,
  emailDrafts,
  pendingActions,
  type PendingAction,
} from "@/lib/db/schema";
import {
  evaluateActionConfirm,
  PolicyDeniedError,
} from "@/lib/policy";
import {
  assertTransition,
  canTransition,
  initialSendActionStatus,
} from "./state-machine";
import {
  ActionError,
  buildSendIdempotencyKey,
  computeExpiresAt,
  isActionExpired,
  type ActionStatus,
  type AuditStatus,
  type ConfirmSendActionInput,
  type CreateSendActionInput,
  type ConfirmTrashActionInput,
  type CreateTrashActionInput,
  buildTrashIdempotencyKey,
} from "./types";

export function hashDraftPayload(parts: {
  toJson: string;
  ccJson: string;
  bccJson: string;
  subject: string;
  bodyText: string;
  attachmentIdsJson?: string;
}): string {
  const canonical = JSON.stringify({
    to: JSON.parse(parts.toJson),
    cc: JSON.parse(parts.ccJson),
    bcc: JSON.parse(parts.bccJson),
    subject: parts.subject,
    bodyText: parts.bodyText,
    attachmentIds: JSON.parse(parts.attachmentIdsJson ?? "[]"),
  });
  return createHash("sha256").update(canonical).digest("hex");
}

async function writeAuditLog(params: {
  userId: string;
  actionType: string;
  resourceType: string;
  resourceId: string;
  status: AuditStatus;
  metadata?: Record<string, unknown>;
}) {
  const db = getDb();
  await db.insert(actionAuditLog).values({
    id: nanoid(),
    userId: params.userId,
    actionType: params.actionType,
    resourceType: params.resourceType,
    resourceId: params.resourceId,
    status: params.status,
    metadataJson: JSON.stringify(params.metadata ?? {}),
  });

  logActionAudit({
    userId: params.userId,
    actionType: params.actionType,
    resourceType: params.resourceType,
    resourceId: params.resourceId,
    status: params.status,
    metadata: params.metadata,
  });
}

async function getOwnedAction(
  actionId: string,
  userId: string
): Promise<PendingAction> {
  const db = getDb();
  const action = await db.query.pendingActions.findFirst({
    where: and(
      eq(pendingActions.id, actionId),
      eq(pendingActions.userId, userId)
    ),
  });

  if (!action) {
    throw new ActionError("NOT_FOUND", "Action introuvable.");
  }

  return action;
}

async function expireActionIfNeeded(action: PendingAction): Promise<PendingAction> {
  if (
    action.status !== "pending_confirmation" ||
    !isActionExpired(action.expiresAt)
  ) {
    return action;
  }

  const db = getDb();
  await db
    .update(pendingActions)
    .set({ status: "expired" })
    .where(
      and(
        eq(pendingActions.id, action.id),
        eq(pendingActions.status, "pending_confirmation")
      )
    );

  await writeAuditLog({
    userId: action.userId,
    actionType: action.actionType,
    resourceType: "pending_action",
    resourceId: action.id,
    status: "rejected",
    metadata: { reason: "expired" },
  });

  return { ...action, status: "expired" };
}

async function requireValidatedDraft(draftId: string, userId: string) {
  const db = getDb();
  const draft = await db.query.emailDrafts.findFirst({
    where: and(eq(emailDrafts.id, draftId), eq(emailDrafts.userId, userId)),
  });

  if (!draft) {
    throw new ActionError("DRAFT_NOT_FOUND", "Brouillon introuvable.");
  }

  if (draft.status !== "validated") {
    throw new ActionError(
      "DRAFT_NOT_VALIDATED",
      "Le brouillon doit être validé avant envoi."
    );
  }

  return draft;
}

export async function createSendConfirmationAction(
  input: CreateSendActionInput
): Promise<PendingAction> {
  const db = getDb();
  const draft = await requireValidatedDraft(input.draftId, input.userId);

  if (draft.contentHash !== input.payloadHash) {
    throw new ActionError(
      "HASH_MISMATCH",
      "Le hash du brouillon ne correspond pas à l'action demandée."
    );
  }

  const idempotencyKey = buildSendIdempotencyKey(
    input.draftId,
    input.payloadHash
  );

  const existing = await db.query.pendingActions.findFirst({
    where: eq(pendingActions.idempotencyKey, idempotencyKey),
  });

  if (existing) {
    if (
      existing.status === "pending_confirmation" &&
      !isActionExpired(existing.expiresAt)
    ) {
      return existing;
    }
    if (existing.status === "completed") {
      throw new ActionError(
        "ALREADY_USED",
        "Cet envoi a déjà été effectué."
      );
    }
  }

  const actionId = nanoid();
  const confirmationToken = nanoid(32);
  const expiresAt = computeExpiresAt();
  const status = initialSendActionStatus();

  await db.insert(pendingActions).values({
    id: actionId,
    userId: input.userId,
    conversationId: input.conversationId,
    draftId: input.draftId,
    actionType: "send_email",
    status,
    payloadHash: input.payloadHash,
    confirmationToken,
    expiresAt,
    idempotencyKey,
  });

  await writeAuditLog({
    userId: input.userId,
    actionType: "send_email",
    resourceType: "pending_action",
    resourceId: actionId,
    status: "success",
    metadata: {
      event: "action_created",
      draftId: input.draftId,
      conversationId: input.conversationId,
    },
  });

  const created = await db.query.pendingActions.findFirst({
    where: eq(pendingActions.id, actionId),
  });

  if (!created) {
    throw new ActionError("NOT_FOUND", "Échec de création de l'action.");
  }

  return created;
}

export async function getActionById(
  actionId: string,
  userId: string
): Promise<PendingAction | null> {
  const db = getDb();
  const action = await db.query.pendingActions.findFirst({
    where: and(
      eq(pendingActions.id, actionId),
      eq(pendingActions.userId, userId)
    ),
  });
  if (!action) return null;
  return expireActionIfNeeded(action);
}

export async function getPendingSendActionForConversation(
  conversationId: string,
  userId: string
): Promise<PendingAction | null> {
  const db = getDb();
  const action = await db.query.pendingActions.findFirst({
    where: and(
      eq(pendingActions.conversationId, conversationId),
      eq(pendingActions.userId, userId),
      eq(pendingActions.actionType, "send_email"),
      eq(pendingActions.status, "pending_confirmation")
    ),
    orderBy: desc(pendingActions.createdAt),
  });

  if (!action) return null;
  return expireActionIfNeeded(action);
}

export async function confirmSendAction(
  input: ConfirmSendActionInput
): Promise<PendingAction> {
  let action = await getOwnedAction(input.actionId, input.userId);

  if (action.status === "executing" || action.status === "completed") {
    throw new ActionError(
      "ALREADY_USED",
      "Cette confirmation a déjà été utilisée."
    );
  }

  action = await expireActionIfNeeded(action);

  if (action.status === "expired") {
    throw new ActionError("EXPIRED", "La confirmation a expiré.");
  }

  if (action.confirmationToken !== input.confirmationToken) {
    await writeAuditLog({
      userId: input.userId,
      actionType: action.actionType,
      resourceType: "pending_action",
      resourceId: action.id,
      status: "rejected",
      metadata: { reason: "invalid_token" },
    });
    throw new ActionError("FORBIDDEN", "Token de confirmation invalide.");
  }

  if (!action.draftId) {
    throw new ActionError("DRAFT_NOT_FOUND", "Aucun brouillon lié à cette action.");
  }

  const draft = await requireValidatedDraft(action.draftId, input.userId);
  if (draft.contentHash !== action.payloadHash) {
    throw new ActionError(
      "HASH_MISMATCH",
      "Le brouillon a été modifié depuis la demande de confirmation."
    );
  }

  const policyDecision = evaluateActionConfirm(
    {
      actionId: input.actionId,
      confirmationToken: input.confirmationToken,
      userId: input.userId,
      payloadHash: action.payloadHash,
    },
    {
      userId: input.userId,
      conversationId: action.conversationId,
      emailConnected: input.emailConnected ?? false,
      grantedPermissions: input.grantedPermissions ?? [],
      hasConfirmation: true,
      expectedUserId: action.userId,
      expectedPayloadHash: action.payloadHash,
      status: action.status,
      expiresAt: action.expiresAt,
      confirmationAlreadyUsed: false,
      actionType: action.actionType as "send_email" | "trash_email",
    }
  );

  if (policyDecision.outcome !== "allow") {
    await writeAuditLog({
      userId: input.userId,
      actionType: action.actionType,
      resourceType: "pending_action",
      resourceId: action.id,
      status: "rejected",
      metadata: {
        reason:
          policyDecision.outcome === "deny"
            ? policyDecision.code
            : "policy_denied",
      },
    });
    if (policyDecision.outcome === "deny") {
      throw new PolicyDeniedError(policyDecision.code, policyDecision.reason);
    }
    throw new ActionError("POLICY_DENIED", "Confirmation refusée par la policy.");
  }

  const db = getDb();
  const now = new Date().toISOString();

  const confirmed = await db
    .update(pendingActions)
    .set({ status: "confirmed", confirmedAt: now })
    .where(
      and(
        eq(pendingActions.id, input.actionId),
        eq(pendingActions.userId, input.userId),
        eq(pendingActions.status, "pending_confirmation"),
        eq(pendingActions.confirmationToken, input.confirmationToken)
      )
    )
    .returning();

  if (confirmed.length === 0) {
    throw new ActionError(
      "ALREADY_USED",
      "Cette confirmation a déjà été utilisée ou l'action n'est plus valide."
    );
  }

  assertTransition("confirmed", "executing");

  const executing = await db
    .update(pendingActions)
    .set({ status: "executing" })
    .where(
      and(
        eq(pendingActions.id, input.actionId),
        eq(pendingActions.status, "confirmed")
      )
    )
    .returning();

  if (executing.length === 0) {
    throw new ActionError("INVALID_STATE", "Impossible de démarrer l'exécution.");
  }

  await writeAuditLog({
    userId: input.userId,
    actionType: "send_email",
    resourceType: "pending_action",
    resourceId: input.actionId,
    status: "success",
    metadata: { event: "action_confirmed" },
  });

  return executing[0];
}

export async function cancelAction(
  actionId: string,
  userId: string
): Promise<PendingAction> {
  const action = await getOwnedAction(actionId, userId);

  if (!canTransition(action.status, "cancelled")) {
    throw new ActionError(
      "INVALID_STATE",
      `Impossible d'annuler une action en état ${action.status}.`
    );
  }

  const db = getDb();
  const updated = await db
    .update(pendingActions)
    .set({ status: "cancelled" })
    .where(
      and(
        eq(pendingActions.id, actionId),
        eq(pendingActions.userId, userId),
        eq(pendingActions.status, action.status)
      )
    )
    .returning();

  if (updated.length === 0) {
    throw new ActionError("INVALID_STATE", "Annulation impossible.");
  }

  await writeAuditLog({
    userId,
    actionType: action.actionType,
    resourceType: "pending_action",
    resourceId: actionId,
    status: "success",
    metadata: { event: "action_cancelled" },
  });

  return updated[0];
}

export async function markActionCompleted(
  actionId: string,
  userId: string
): Promise<PendingAction> {
  const action = await getOwnedAction(actionId, userId);
  assertTransition(action.status, "completed");

  const db = getDb();
  const now = new Date().toISOString();
  const updated = await db
    .update(pendingActions)
    .set({ status: "completed", executedAt: now })
    .where(
      and(
        eq(pendingActions.id, actionId),
        eq(pendingActions.userId, userId),
        eq(pendingActions.status, "executing")
      )
    )
    .returning();

  if (updated.length === 0) {
    throw new ActionError("INVALID_STATE", "Impossible de finaliser l'action.");
  }

  if (updated[0].draftId) {
    await db
      .update(emailDrafts)
      .set({ status: "sent", updatedAt: now })
      .where(eq(emailDrafts.id, updated[0].draftId));
  }

  await writeAuditLog({
    userId,
    actionType: action.actionType,
    resourceType: "pending_action",
    resourceId: actionId,
    status: "success",
    metadata: { event: "action_completed" },
  });

  return updated[0];
}

export async function markActionFailed(
  actionId: string,
  userId: string,
  errorCode: string,
  errorMessage: string
): Promise<PendingAction> {
  const action = await getOwnedAction(actionId, userId);

  if (!canTransition(action.status, "failed")) {
    throw new ActionError(
      "INVALID_STATE",
      `Impossible de marquer l'action en échec depuis ${action.status}.`
    );
  }

  const db = getDb();
  const updated = await db
    .update(pendingActions)
    .set({
      status: "failed",
      errorCode,
      errorMessage,
    })
    .where(
      and(
        eq(pendingActions.id, actionId),
        eq(pendingActions.userId, userId),
        eq(pendingActions.status, action.status)
      )
    )
    .returning();

  if (updated.length === 0) {
    throw new ActionError("INVALID_STATE", "Impossible de marquer l'échec.");
  }

  await writeAuditLog({
    userId,
    actionType: action.actionType,
    resourceType: "pending_action",
    resourceId: actionId,
    status: "failed",
    metadata: { errorCode },
  });

  return updated[0];
}

export async function expireStaleActions(): Promise<number> {
  const db = getDb();
  const now = new Date().toISOString();

  const stale = await db
    .update(pendingActions)
    .set({ status: "expired" })
    .where(
      and(
        eq(pendingActions.status, "pending_confirmation"),
        lt(pendingActions.expiresAt, now)
      )
    )
    .returning();

  for (const action of stale) {
    await writeAuditLog({
      userId: action.userId,
      actionType: action.actionType,
      resourceType: "pending_action",
      resourceId: action.id,
      status: "rejected",
      metadata: { reason: "expired_batch" },
    });
  }

  return stale.length;
}

export async function transitionActionStatus(
  actionId: string,
  userId: string,
  to: ActionStatus
): Promise<PendingAction> {
  const action = await getOwnedAction(actionId, userId);
  assertTransition(action.status, to);

  const db = getDb();
  const updated = await db
    .update(pendingActions)
    .set({ status: to })
    .where(
      and(
        eq(pendingActions.id, actionId),
        eq(pendingActions.userId, userId),
        eq(pendingActions.status, action.status)
      )
    )
    .returning();

  if (updated.length === 0) {
    throw new ActionError("INVALID_STATE", "Transition concurrente détectée.");
  }

  return updated[0];
}

export async function createTrashConfirmationAction(
  input: CreateTrashActionInput
): Promise<PendingAction> {
  const db = getDb();
  const idempotencyKey = buildTrashIdempotencyKey(input.messageId, input.userId);

  const existing = await db.query.pendingActions.findFirst({
    where: eq(pendingActions.idempotencyKey, idempotencyKey),
  });

  if (existing) {
    if (
      existing.status === "pending_confirmation" &&
      !isActionExpired(existing.expiresAt)
    ) {
      return existing;
    }
    if (existing.status === "completed") {
      throw new ActionError(
        "ALREADY_USED",
        "Ce message a déjà été mis à la corbeille."
      );
    }
  }

  const actionId = nanoid();
  const confirmationToken = nanoid(32);
  const expiresAt = computeExpiresAt();
  const status = initialSendActionStatus();

  await db.insert(pendingActions).values({
    id: actionId,
    userId: input.userId,
    conversationId: input.conversationId,
    resourceId: input.messageId,
    actionType: "trash_email",
    status,
    payloadHash: input.payloadHash,
    confirmationToken,
    expiresAt,
    idempotencyKey,
  });

  await writeAuditLog({
    userId: input.userId,
    actionType: "trash_email",
    resourceType: "message",
    resourceId: input.messageId,
    status: "success",
    metadata: {
      event: "action_created",
      conversationId: input.conversationId,
      snapshot: input.messageSnapshot,
    },
  });

  const created = await db.query.pendingActions.findFirst({
    where: eq(pendingActions.id, actionId),
  });

  if (!created) {
    throw new ActionError("NOT_FOUND", "Échec de création de l'action.");
  }

  return created;
}

export async function confirmTrashAction(
  input: ConfirmTrashActionInput
): Promise<PendingAction> {
  let action = await getOwnedAction(input.actionId, input.userId);

  if (action.status === "executing" || action.status === "completed") {
    throw new ActionError(
      "ALREADY_USED",
      "Cette confirmation a déjà été utilisée."
    );
  }

  action = await expireActionIfNeeded(action);

  if (action.status === "expired") {
    throw new ActionError("EXPIRED", "La confirmation a expiré.");
  }

  if (action.actionType !== "trash_email") {
    throw new ActionError("INVALID_STATE", "Action incompatible.");
  }

  if (action.confirmationToken !== input.confirmationToken) {
    await writeAuditLog({
      userId: input.userId,
      actionType: action.actionType,
      resourceType: "pending_action",
      resourceId: action.id,
      status: "rejected",
      metadata: { reason: "invalid_token" },
    });
    throw new ActionError("FORBIDDEN", "Token de confirmation invalide.");
  }

  if (!action.resourceId) {
    throw new ActionError("MESSAGE_NOT_FOUND", "Aucun message lié à cette action.");
  }

  const policyDecision = evaluateActionConfirm(
    {
      actionId: input.actionId,
      confirmationToken: input.confirmationToken,
      userId: input.userId,
      payloadHash: action.payloadHash,
    },
    {
      userId: input.userId,
      conversationId: action.conversationId,
      emailConnected: input.emailConnected ?? false,
      grantedPermissions: input.grantedPermissions ?? [],
      hasConfirmation: true,
      expectedUserId: action.userId,
      expectedPayloadHash: action.payloadHash,
      status: action.status,
      expiresAt: action.expiresAt,
      confirmationAlreadyUsed: false,
      actionType: "trash_email",
    }
  );

  if (policyDecision.outcome !== "allow") {
    await writeAuditLog({
      userId: input.userId,
      actionType: action.actionType,
      resourceType: "pending_action",
      resourceId: action.id,
      status: "rejected",
      metadata: {
        reason:
          policyDecision.outcome === "deny"
            ? policyDecision.code
            : "policy_denied",
      },
    });
    if (policyDecision.outcome === "deny") {
      throw new PolicyDeniedError(policyDecision.code, policyDecision.reason);
    }
    throw new ActionError("POLICY_DENIED", "Confirmation refusée par la policy.");
  }

  const db = getDb();
  const now = new Date().toISOString();

  const confirmed = await db
    .update(pendingActions)
    .set({ status: "confirmed", confirmedAt: now })
    .where(
      and(
        eq(pendingActions.id, input.actionId),
        eq(pendingActions.userId, input.userId),
        eq(pendingActions.status, "pending_confirmation"),
        eq(pendingActions.confirmationToken, input.confirmationToken)
      )
    )
    .returning();

  if (confirmed.length === 0) {
    throw new ActionError(
      "ALREADY_USED",
      "Cette confirmation a déjà été utilisée ou l'action n'est plus valide."
    );
  }

  assertTransition("confirmed", "executing");

  const executing = await db
    .update(pendingActions)
    .set({ status: "executing" })
    .where(
      and(
        eq(pendingActions.id, input.actionId),
        eq(pendingActions.status, "confirmed")
      )
    )
    .returning();

  if (executing.length === 0) {
    throw new ActionError("INVALID_STATE", "Impossible de démarrer l'exécution.");
  }

  await writeAuditLog({
    userId: input.userId,
    actionType: "trash_email",
    resourceType: "pending_action",
    resourceId: input.actionId,
    status: "success",
    metadata: { event: "action_confirmed" },
  });

  return executing[0];
}
