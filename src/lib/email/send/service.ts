import {
  cancelAction,
  confirmSendAction,
  createSendConfirmationAction,
  getActionById,
  getPendingSendActionForConversation,
  markActionCompleted,
  markActionFailed,
} from "@/lib/actions";
import { ActionError } from "@/lib/actions/types";
import { requireEmailDraftForUser, toEmailDraftPreview, markEmailDraftSent } from "@/lib/email/draft";
import { getEmailProvider } from "@/lib/integrations/email";
import { resolveEmailPolicyContext } from "@/lib/tools/policy-context";
import { executeToolWithPolicy } from "@/lib/tools/execute-with-policy";
import type { AppSettings } from "@/lib/settings/service";
import type {
  ConfirmSendEmailResult,
  ProposeSendEmailResult,
  PublicPendingAction,
  SendEmailExecutionResult,
} from "./types";

function toPublicPendingAction(
  action: import("@/lib/db/schema").PendingAction
): PublicPendingAction {
  return {
    actionId: action.id,
    draftId: action.draftId,
    conversationId: action.conversationId,
    status: action.status,
    expiresAt: action.expiresAt,
    payloadHash: action.payloadHash,
    confirmedAt: action.confirmedAt,
    executedAt: action.executedAt,
    errorCode: action.errorCode,
    errorMessage: action.errorMessage,
  };
}

export async function proposeEmailSend(input: {
  userId: string;
  draftId: string;
}): Promise<ProposeSendEmailResult> {
  const draft = await requireEmailDraftForUser(input.draftId, input.userId);

  if (draft.status !== "validated") {
    throw new ActionError(
      "DRAFT_NOT_VALIDATED",
      "Validez le brouillon avant de demander l'envoi."
    );
  }

  const action = await createSendConfirmationAction({
    userId: input.userId,
    conversationId: draft.conversationId,
    draftId: draft.id,
    payloadHash: draft.contentHash,
  });

  return {
    actionId: action.id,
    draftId: draft.id,
    conversationId: action.conversationId,
    status: action.status,
    expiresAt: action.expiresAt,
    confirmationToken: action.confirmationToken,
    payloadHash: action.payloadHash,
  };
}

export async function getPublicEmailAction(
  actionId: string,
  userId: string
): Promise<PublicPendingAction | null> {
  const action = await getActionById(actionId, userId);
  return action ? toPublicPendingAction(action) : null;
}

export async function getPublicPendingSendForConversation(
  conversationId: string,
  userId: string
): Promise<PublicPendingAction | null> {
  const action = await getPendingSendActionForConversation(
    conversationId,
    userId
  );
  return action ? toPublicPendingAction(action) : null;
}

export async function cancelEmailSendAction(
  actionId: string,
  userId: string
): Promise<PublicPendingAction> {
  const action = await cancelAction(actionId, userId);
  return toPublicPendingAction(action);
}

export async function confirmAndExecuteEmailSend(input: {
  actionId: string;
  confirmationToken: string;
  userId: string;
  settings: AppSettings;
  conversationId: string;
  signal?: AbortSignal;
}): Promise<ConfirmSendEmailResult> {
  const policyContext = await resolveEmailPolicyContext(input.userId);

  const executing = await confirmSendAction({
    actionId: input.actionId,
    confirmationToken: input.confirmationToken,
    userId: input.userId,
    emailConnected: policyContext.emailConnected,
    grantedPermissions: policyContext.grantedPermissions,
  });

  if (!executing.draftId) {
    throw new ActionError("DRAFT_NOT_FOUND", "Aucun brouillon lié à cette action.");
  }

  try {
    const result = (await executeToolWithPolicy(
      "email_send",
      { draftId: executing.draftId },
      {
        signal: input.signal ?? AbortSignal.timeout(35_000),
        settings: input.settings,
        conversationId: input.conversationId,
        runtimeLocation: "local",
        userId: input.userId,
        policyContext: {
          ...policyContext,
          hasConfirmation: true,
        },
      }
    )) as SendEmailExecutionResult;

    await markEmailDraftSent(executing.draftId, input.userId);
    await markActionCompleted(executing.id, input.userId);

    return {
      actionId: executing.id,
      draftId: executing.draftId,
      status: "completed",
      messageId: result.messageId,
      threadId: result.threadId,
    };
  } catch (error) {
    const errorCode =
      error instanceof ActionError
        ? error.code
        : error instanceof Error
          ? error.name
          : "SEND_FAILED";
    const errorMessage =
      error instanceof Error ? error.message : "Échec d'envoi email.";

    await markActionFailed(
      executing.id,
      input.userId,
      errorCode,
      errorMessage
    );
    throw error;
  }
}

export async function assertEmailSendReady(userId: string): Promise<void> {
  await getEmailProvider(userId);
}

export async function buildSendProposalResponse(
  proposal: ProposeSendEmailResult,
  draft: Awaited<ReturnType<typeof requireEmailDraftForUser>>
) {
  return {
    ...proposal,
    draft: await toEmailDraftPreview(draft),
  };
}
