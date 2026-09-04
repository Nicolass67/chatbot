import { createHash } from "node:crypto";
import { and, eq } from "drizzle-orm";
import { nanoid } from "nanoid";
import { getDb } from "@/lib/db";
import { actionAuditLog, pendingActions } from "@/lib/db/schema";
import {
  computeExpiresAt,
  type ActionType,
} from "@/lib/actions/types";
import { initialSendActionStatus } from "@/lib/actions/state-machine";
import { logActionAudit } from "@/lib/observability/action-logger";
import type { FrozenFilesMutationPayload } from "./types";

export function hashFilesPayload(payload: FrozenFilesMutationPayload): string {
  return createHash("sha256").update(JSON.stringify(payload)).digest("hex");
}

export async function auditFiles(params: {
  userId: string;
  actionType: string;
  resourceId: string;
  status: "success" | "rejected" | "failed";
  metadata?: Record<string, unknown>;
}) {
  const db = getDb();
  await db.insert(actionAuditLog).values({
    id: nanoid(),
    userId: params.userId,
    actionType: params.actionType,
    resourceType: "file",
    resourceId: params.resourceId,
    status: params.status,
    metadataJson: JSON.stringify(params.metadata ?? {}),
  });
  logActionAudit({
    userId: params.userId,
    actionType: params.actionType,
    resourceType: "file",
    resourceId: params.resourceId,
    status: params.status,
    metadata: params.metadata,
  });
}

export async function createFilesMutationAction(input: {
  userId: string;
  conversationId: string;
  actionType: Extract<
    ActionType,
    "create_directory" | "rename_file" | "move_file"
  >;
  payload: FrozenFilesMutationPayload;
}): Promise<{
  actionId: string;
  confirmationToken: string;
  payloadHash: string;
  expiresAt: string;
  payload: FrozenFilesMutationPayload;
}> {
  const db = getDb();
  const actionId = nanoid(16);
  const confirmationToken = nanoid(32);
  const payloadHash = hashFilesPayload(input.payload);
  const expiresAt = computeExpiresAt();
  const idempotencyKey = `${input.actionType}:${input.userId}:${payloadHash}:${Date.now()}`;

  await db.insert(pendingActions).values({
    id: actionId,
    userId: input.userId,
    conversationId: input.conversationId,
    actionType: input.actionType,
    status: initialSendActionStatus(),
    payloadHash,
    payloadJson: JSON.stringify(input.payload),
    confirmationToken,
    expiresAt,
    idempotencyKey,
    resourceId: input.payload.sourceFileId ?? input.payload.destRootId,
  });

  await auditFiles({
    userId: input.userId,
    actionType: input.actionType,
    resourceId: actionId,
    status: "success",
    metadata: { event: "action_created", op: input.payload.op },
  });

  return {
    actionId,
    confirmationToken,
    payloadHash,
    expiresAt,
    payload: input.payload,
  };
}

export async function getPendingFilesAction(
  userId: string,
  actionId: string
): Promise<typeof pendingActions.$inferSelect | null> {
  const db = getDb();
  const row = await db.query.pendingActions.findFirst({
    where: and(
      eq(pendingActions.id, actionId),
      eq(pendingActions.userId, userId)
    ),
  });
  return row ?? null;
}
