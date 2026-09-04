import fs from "node:fs";
import { and, eq } from "drizzle-orm";
import { getDb } from "@/lib/db";
import { pendingActions } from "@/lib/db/schema";
import { assertTransition } from "@/lib/actions/state-machine";
import { ActionError, isActionExpired } from "@/lib/actions/types";
import { evaluateActionConfirm } from "@/lib/policy";
import { defaultFilesGrantedPermissions } from "@/lib/policy/engine";
import { isFilesFeatureEnabled } from "./feature";
import { auditFiles, getPendingFilesAction, hashFilesPayload } from "./mutations";
import {
  mkdirUnderRoot,
  moveAcrossRoots,
  renameUnderRoot,
  deleteFileUnderRoot,
} from "./provider";
import { getFileRoot, hasConfiguredRoots } from "./roots";
import { resolveUnderRoot } from "./path-guard";
import type { FrozenFilesMutationPayload } from "./types";

export async function confirmFilesMutationAction(input: {
  actionId: string;
  confirmationToken: string;
  userId: string;
}): Promise<{ ok: true }> {
  if (!isFilesFeatureEnabled()) {
    throw new ActionError("POLICY_DENIED", "Files désactivé.");
  }

  const action = await getPendingFilesAction(input.userId, input.actionId);
  if (!action) {
    throw new ActionError("NOT_FOUND", "Action introuvable.");
  }

  if (isActionExpired(action.expiresAt)) {
    throw new ActionError("EXPIRED", "Action expirée.");
  }

  if (action.confirmationToken !== input.confirmationToken) {
    throw new ActionError("FORBIDDEN", "Token de confirmation invalide.");
  }

  if (!action.payloadJson) {
    throw new ActionError("INVALID_STATE", "Payload frozen manquant.");
  }

  let payload: FrozenFilesMutationPayload;
  try {
    payload = JSON.parse(action.payloadJson) as FrozenFilesMutationPayload;
  } catch {
    throw new ActionError("INVALID_STATE", "Payload frozen invalide.");
  }

  const expectedHash = hashFilesPayload(payload);
  if (expectedHash !== action.payloadHash) {
    throw new ActionError("HASH_MISMATCH", "payloadHash incohérent.");
  }

  const decision = evaluateActionConfirm(
    {
      actionId: action.id,
      confirmationToken: input.confirmationToken,
      userId: input.userId,
      payloadHash: action.payloadHash,
    },
    {
      userId: input.userId,
      conversationId: action.conversationId,
      expectedUserId: action.userId,
      expectedPayloadHash: action.payloadHash,
      status: action.status,
      expiresAt: action.expiresAt,
      confirmationAlreadyUsed: Boolean(action.confirmedAt),
      actionType: action.actionType as
        | "create_directory"
        | "rename_file"
        | "move_file"
        | "delete_file",
      hasConfirmation: true,
      filesEnabled: true,
      hasConfiguredRoots: await hasConfiguredRoots(input.userId),
      grantedPermissions: defaultFilesGrantedPermissions(),
    }
  );

  if (decision.outcome !== "allow") {
    throw new ActionError(
      "POLICY_DENIED",
      decision.outcome === "deny" ? decision.reason : "Confirmation refusée."
    );
  }

  // Revalidation fingerprint
  if (
    payload.sourceRelativePath &&
    payload.sourceRootId &&
    payload.expectedMtimeMs != null
  ) {
    const srcRoot = await getFileRoot(input.userId, payload.sourceRootId);
    if (!srcRoot?.enabled) {
      throw new ActionError("NOT_FOUND", "Root source inactive.");
    }
    const srcAbs = resolveUnderRoot(
      srcRoot.absolutePath,
      payload.sourceRelativePath
    );
    if (!fs.existsSync(srcAbs)) {
      throw new ActionError("NOT_FOUND", "Fichier source disparu.");
    }
    const st = fs.lstatSync(srcAbs);
    if (
      Math.floor(st.mtimeMs) !== payload.expectedMtimeMs ||
      (payload.expectedSizeBytes != null && st.size !== payload.expectedSizeBytes)
    ) {
      throw new ActionError(
        "HASH_MISMATCH",
        "Fichier modifié depuis la proposition (stale)."
      );
    }
  }

  const db = getDb();
  assertTransition(action.status, "confirmed");
  await db
    .update(pendingActions)
    .set({
      status: "confirmed",
      confirmedAt: new Date().toISOString(),
    })
    .where(
      and(
        eq(pendingActions.id, action.id),
        eq(pendingActions.status, "pending_confirmation")
      )
    );

  assertTransition("confirmed", "executing");
  await db
    .update(pendingActions)
    .set({ status: "executing" })
    .where(eq(pendingActions.id, action.id));

  try {
    if (payload.op === "create_directory") {
      const root = await getFileRoot(input.userId, payload.destRootId);
      if (!root?.enabled) throw new Error("Root destination inactive.");
      mkdirUnderRoot(root.absolutePath, payload.destRelativePath);
    } else if (payload.op === "rename_file") {
      const root = await getFileRoot(input.userId, payload.destRootId);
      if (!root?.enabled || !payload.sourceRelativePath) {
        throw new Error("Rename invalide.");
      }
      renameUnderRoot({
        rootAbsolute: root.absolutePath,
        sourceRelative: payload.sourceRelativePath,
        destRelative: payload.destRelativePath,
      });
    } else if (payload.op === "move_file") {
      if (!payload.sourceRootId || !payload.sourceRelativePath) {
        throw new Error("Move invalide.");
      }
      const srcRoot = await getFileRoot(input.userId, payload.sourceRootId);
      const destRoot = await getFileRoot(input.userId, payload.destRootId);
      if (!srcRoot?.enabled || !destRoot?.enabled) {
        throw new Error("Roots move invalides.");
      }
      moveAcrossRoots({
        sourceRootAbsolute: srcRoot.absolutePath,
        sourceRelative: payload.sourceRelativePath,
        destRootAbsolute: destRoot.absolutePath,
        destRelative: payload.destRelativePath,
      });
    } else if (payload.op === "delete_file") {
      if (!payload.sourceRootId || !payload.sourceRelativePath) {
        throw new Error("Delete invalide.");
      }
      const root = await getFileRoot(input.userId, payload.sourceRootId);
      if (!root?.enabled) throw new Error("Root source inactive.");
      deleteFileUnderRoot(root.absolutePath, payload.sourceRelativePath);
    } else {
      throw new Error("Opération inconnue.");
    }

    assertTransition("executing", "completed");
    await db
      .update(pendingActions)
      .set({
        status: "completed",
        executedAt: new Date().toISOString(),
      })
      .where(eq(pendingActions.id, action.id));

    await auditFiles({
      userId: input.userId,
      actionType: action.actionType,
      resourceId: action.id,
      status: "success",
      metadata: { event: "action_completed", op: payload.op },
    });

    return { ok: true };
  } catch (err) {
    const message = err instanceof Error ? err.message : "Échec exécution";
    await db
      .update(pendingActions)
      .set({
        status: "failed",
        errorCode: "EXEC_FAILED",
        errorMessage: message,
      })
      .where(eq(pendingActions.id, action.id));
    await auditFiles({
      userId: input.userId,
      actionType: action.actionType,
      resourceId: action.id,
      status: "failed",
      metadata: { event: "action_failed", error: message },
    });
    throw err;
  }
}

export async function cancelFilesMutationAction(input: {
  actionId: string;
  userId: string;
}): Promise<void> {
  const action = await getPendingFilesAction(input.userId, input.actionId);
  if (!action) throw new ActionError("NOT_FOUND", "Action introuvable.");
  if (action.status !== "pending_confirmation") {
    throw new ActionError(
      "INVALID_STATE",
      "Cette proposition est déjà traitée ou expirée."
    );
  }
  const db = getDb();
  await db
    .update(pendingActions)
    .set({ status: "cancelled" })
    .where(eq(pendingActions.id, action.id));
  await auditFiles({
    userId: input.userId,
    actionType: action.actionType,
    resourceId: action.id,
    status: "success",
    metadata: { event: "action_cancelled" },
  });
}
