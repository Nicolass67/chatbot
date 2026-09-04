import {
  ActionError,
  confirmTrashAction,
  createTrashConfirmationAction,
  getActionById,
  markActionCompleted,
  markActionFailed,
  hashTrashPayload,
} from "@/lib/actions";
import { getEmailProvider } from "@/lib/integrations/email";
import { EmailProviderError } from "@/lib/integrations/email/types";
import { resolveEmailPolicyContext } from "@/lib/tools/policy-context";
import { getOrCreateMailWorkspaceConversation } from "@/lib/mail/workspace";
import type {
  ConfirmTrashEmailResult,
  ProposeTrashEmailResult,
  PublicTrashAction,
} from "./types";

function toPublicTrashAction(
  action: import("@/lib/db/schema").PendingAction,
  snapshot?: { from: string; subject: string }
): PublicTrashAction {
  return {
    actionId: action.id,
    messageId: action.resourceId ?? "",
    conversationId: action.conversationId,
    status: action.status,
    expiresAt: action.expiresAt,
    payloadHash: action.payloadHash,
    confirmationToken: action.confirmationToken,
    messageSnapshot: snapshot,
  };
}

export async function proposeEmailTrash(input: {
  userId: string;
  messageId: string;
}): Promise<ProposeTrashEmailResult> {
  const provider = await getEmailProvider(input.userId);
  let message;
  try {
    message = await provider.getMessage(input.messageId);
  } catch (error) {
    if (error instanceof EmailProviderError && error.code === "NOT_FOUND") {
      throw new ActionError("MESSAGE_NOT_FOUND", "Message introuvable.");
    }
    throw error;
  }

  const payloadHash = hashTrashPayload({
    messageId: message.id,
    from: message.from.email,
    subject: message.subject,
  });

  const conversationId = await getOrCreateMailWorkspaceConversation();
  const action = await createTrashConfirmationAction({
    userId: input.userId,
    conversationId,
    messageId: message.id,
    payloadHash,
    messageSnapshot: {
      from: message.from.name
        ? `${message.from.name} <${message.from.email}>`
        : message.from.email,
      subject: message.subject,
    },
  });

  return {
    actionId: action.id,
    messageId: message.id,
    conversationId: action.conversationId,
    status: action.status,
    expiresAt: action.expiresAt,
    confirmationToken: action.confirmationToken,
    payloadHash: action.payloadHash,
    messageSnapshot: {
      from: message.from.name
        ? `${message.from.name} <${message.from.email}>`
        : message.from.email,
      subject: message.subject,
    },
  };
}

export async function getPublicTrashAction(
  actionId: string,
  userId: string
): Promise<PublicTrashAction | null> {
  const action = await getActionById(actionId, userId);
  if (!action || action.actionType !== "trash_email") return null;
  return toPublicTrashAction(action);
}

export async function confirmAndExecuteEmailTrash(input: {
  actionId: string;
  confirmationToken: string;
  userId: string;
}): Promise<ConfirmTrashEmailResult> {
  const policyContext = await resolveEmailPolicyContext(input.userId);

  const executing = await confirmTrashAction({
    actionId: input.actionId,
    confirmationToken: input.confirmationToken,
    userId: input.userId,
    emailConnected: policyContext.emailConnected,
    grantedPermissions: policyContext.grantedPermissions,
  });

  if (!executing.resourceId) {
    throw new ActionError("MESSAGE_NOT_FOUND", "Aucun message lié à cette action.");
  }

  try {
    const provider = await getEmailProvider(input.userId);
    await provider.trashMessage(executing.resourceId);
    await markActionCompleted(executing.id, input.userId);

    return {
      actionId: executing.id,
      messageId: executing.resourceId,
      status: "completed",
    };
  } catch (error) {
    const errorCode =
      error instanceof ActionError
        ? error.code
        : error instanceof EmailProviderError
          ? error.code
          : error instanceof Error
            ? error.name
            : "TRASH_FAILED";
    const errorMessage =
      error instanceof Error ? error.message : "Échec de mise à la corbeille.";

    await markActionFailed(
      executing.id,
      input.userId,
      errorCode,
      errorMessage
    );
    throw error;
  }
}
