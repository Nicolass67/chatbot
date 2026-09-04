import { getFilesCapabilities } from "@/lib/files/feature";
import { getToolMetadata } from "./metadata";
import type {
  ActionConfirmation,
  ActionProposal,
  PermissionScope,
  PolicyContext,
  PolicyDecision,
  PolicyDenyCode,
} from "./types";

function deny(code: PolicyDenyCode, reason: string): PolicyDecision {
  return { outcome: "deny", code, reason };
}

function requireAuthenticated(userId: string | undefined): PolicyDecision | null {
  if (!userId?.trim()) {
    return deny("UNAUTHENTICATED", "Utilisateur non authentifié.");
  }
  return null;
}

function isEmailPermission(p: PermissionScope): boolean {
  return (
    p === "READ_EMAIL" ||
    p === "SEARCH_EMAIL" ||
    p === "ANALYZE_EMAIL" ||
    p === "CREATE_DRAFT" ||
    p === "SEND_EMAIL" ||
    p === "TRASH_EMAIL"
  );
}

function isFilesPermission(p: PermissionScope): boolean {
  return (
    p === "READ_FILE" ||
    p === "SEARCH_FILES" ||
    p === "ANALYZE_FILE" ||
    p === "CREATE_DIRECTORY" ||
    p === "RENAME_FILE" ||
    p === "MOVE_FILE" ||
    p === "DELETE_FILE"
  );
}

function evaluateEmailPermissions(
  ctx: PolicyContext,
  requiredPermissions: PermissionScope[]
): PolicyDecision | null {
  const emailPerms = requiredPermissions.filter(isEmailPermission);
  if (emailPerms.length === 0) return null;

  if (!ctx.emailConnected) {
    return deny(
      "EMAIL_NOT_CONNECTED",
      "Aucun compte Gmail connecté. Connectez Gmail dans les paramètres."
    );
  }

  const granted = ctx.grantedPermissions ?? [];
  for (const permission of emailPerms) {
    if (!granted.includes(permission)) {
      return deny(
        "MISSING_PERMISSION",
        `Permission insuffisante : ${permission}.`
      );
    }
  }

  return null;
}

function evaluateFilesPermissions(
  ctx: PolicyContext,
  requiredPermissions: PermissionScope[]
): PolicyDecision | null {
  const filePerms = requiredPermissions.filter(isFilesPermission);
  if (filePerms.length === 0) return null;

  if (!ctx.filesEnabled) {
    return deny("POLICY_DENIED", "La fonctionnalité Files est désactivée.");
  }
  if (!ctx.hasConfiguredRoots) {
    return deny(
      "FILES_NOT_CONFIGURED",
      "Aucune root Files configurée."
    );
  }

  const caps = getFilesCapabilities();
  for (const permission of filePerms) {
    if (permission === "SEARCH_FILES" && !caps.search) {
      return deny("CAPABILITY_DISABLED", "Capacité search désactivée.");
    }
    if (permission === "READ_FILE" && !caps.read) {
      return deny("CAPABILITY_DISABLED", "Capacité read désactivée.");
    }
    if (permission === "ANALYZE_FILE" && !caps.analyze) {
      return deny("CAPABILITY_DISABLED", "Capacité analyze désactivée.");
    }
    if (permission === "CREATE_DIRECTORY" && !caps.mkdir) {
      return deny("CAPABILITY_DISABLED", "Capacité mkdir désactivée.");
    }
    if (permission === "RENAME_FILE" && !caps.rename) {
      return deny("CAPABILITY_DISABLED", "Capacité rename désactivée.");
    }
    if (permission === "MOVE_FILE" && !caps.move) {
      return deny("CAPABILITY_DISABLED", "Capacité move désactivée.");
    }
    if (permission === "DELETE_FILE" && !caps.delete) {
      return deny("CAPABILITY_DISABLED", "Capacité delete désactivée.");
    }
  }

  const granted = ctx.grantedPermissions ?? [];
  // If grantedPermissions includes file scopes, enforce; else default allow when roots configured.
  const hasAnyFileGrant = granted.some(isFilesPermission);
  if (hasAnyFileGrant) {
    for (const permission of filePerms) {
      if (!granted.includes(permission)) {
        return deny(
          "MISSING_PERMISSION",
          `Permission insuffisante : ${permission}.`
        );
      }
    }
  }

  return null;
}

function mutationActionType(
  toolName: string
): "create_directory" | "rename_file" | "move_file" | null {
  if (toolName === "file_create_directory") return "create_directory";
  if (toolName === "file_rename") return "rename_file";
  if (toolName === "file_move") return "move_file";
  return null;
}

export function evaluateToolCall(
  proposal: ActionProposal,
  ctx: PolicyContext
): PolicyDecision {
  const authError = requireAuthenticated(proposal.userId);
  if (authError) return authError;

  const metadata = getToolMetadata(proposal.toolName);
  if (!metadata) {
    return deny("UNKNOWN_TOOL", `Outil inconnu ou non autorisé : ${proposal.toolName}.`);
  }

  const emailError = evaluateEmailPermissions(ctx, metadata.requiredPermissions);
  if (emailError) return emailError;

  const filesError = evaluateFilesPermissions(ctx, metadata.requiredPermissions);
  if (filesError) return filesError;

  if (metadata.requiresConfirmation) {
    if (metadata.name === "email_send") {
      if (!ctx.hasConfirmation) {
        return deny(
          "CONFIRMATION_REQUIRED",
          "L'envoi d'email nécessite une confirmation explicite via l'interface."
        );
      }
      return { outcome: "allow" };
    }

    const fileMut = mutationActionType(metadata.name);
    if (fileMut) {
      // Propose tools return pending_confirmation payload themselves;
      // policy allows the propose call (creates pending action).
      // Execution internals go through confirm API with hasConfirmation.
      if (ctx.hasConfirmation) {
        return { outcome: "allow" };
      }
      return {
        outcome: "allow",
      };
    }

    return {
      outcome: "pending_confirmation",
      reason: "Action nécessitant une confirmation utilisateur.",
      actionType: "send_email",
    };
  }

  return { outcome: "allow" };
}

export function evaluateActionConfirm(
  confirmation: ActionConfirmation,
  ctx: PolicyContext & {
    expectedUserId: string;
    expectedPayloadHash: string;
    status: string;
    expiresAt: string;
    confirmationAlreadyUsed: boolean;
    actionType?:
      | "send_email"
      | "trash_email"
      | "create_directory"
      | "rename_file"
      | "move_file"
      | "delete_file";
  }
): PolicyDecision {
  const authError = requireAuthenticated(confirmation.userId);
  if (authError) return authError;

  if (confirmation.userId !== ctx.expectedUserId) {
    return deny("POLICY_DENIED", "Action non autorisée pour cet utilisateur.");
  }

  if (confirmation.payloadHash !== ctx.expectedPayloadHash) {
    return deny(
      "POLICY_DENIED",
      "Le contenu de l'action a changé depuis la demande de confirmation."
    );
  }

  if (ctx.confirmationAlreadyUsed) {
    return deny("POLICY_DENIED", "Cette confirmation a déjà été utilisée.");
  }

  if (ctx.status !== "pending_confirmation") {
    return deny("POLICY_DENIED", `État d'action invalide : ${ctx.status}.`);
  }

  if (new Date(ctx.expiresAt).getTime() <= Date.now()) {
    return deny("POLICY_DENIED", "La confirmation a expiré.");
  }

  const fileActions = new Set([
    "create_directory",
    "rename_file",
    "move_file",
    "delete_file",
  ]);

  if (ctx.actionType && fileActions.has(ctx.actionType)) {
    const perm: PermissionScope =
      ctx.actionType === "create_directory"
        ? "CREATE_DIRECTORY"
        : ctx.actionType === "rename_file"
          ? "RENAME_FILE"
          : ctx.actionType === "delete_file"
            ? "DELETE_FILE"
            : "MOVE_FILE";
    const filesError = evaluateFilesPermissions(ctx, [perm]);
    if (filesError) return filesError;
  } else {
    const requiredPermission =
      ctx.actionType === "trash_email" ? "TRASH_EMAIL" : "SEND_EMAIL";
    const emailError = evaluateEmailPermissions(ctx, [requiredPermission]);
    if (emailError) return emailError;
  }

  if (!ctx.hasConfirmation) {
    return deny(
      "CONFIRMATION_REQUIRED",
      "Confirmation explicite requise avant exécution."
    );
  }

  return { outcome: "allow" };
}

/** Permissions Files accordées par défaut quand feature + roots OK. */
export function defaultFilesGrantedPermissions(): PermissionScope[] {
  return [
    "READ_FILE",
    "SEARCH_FILES",
    "ANALYZE_FILE",
    "CREATE_DIRECTORY",
    "RENAME_FILE",
    "MOVE_FILE",
    "DELETE_FILE",
  ];
}
