export type PermissionScope =
  | "READ_EMAIL"
  | "SEARCH_EMAIL"
  | "ANALYZE_EMAIL"
  | "CREATE_DRAFT"
  | "SEND_EMAIL"
  | "TRASH_EMAIL"
  | "READ_FILE"
  | "SEARCH_FILES"
  | "ANALYZE_FILE"
  | "CREATE_DIRECTORY"
  | "RENAME_FILE"
  | "MOVE_FILE"
  | "DELETE_FILE";

export type RiskLevel = "safe" | "moderate" | "critical";

export type ToolDomain = "web" | "email" | "files";

export type TaintPolicy = "none" | "output_untrusted";

export interface ToolMetadata {
  name: string;
  domain: ToolDomain;
  requiredPermissions: PermissionScope[];
  riskLevel: RiskLevel;
  exposedToLlm: boolean;
  requiresConfirmation: boolean;
  confirmationType?: "preview" | "explicit_api";
  timeoutMs: number;
  maxRetries: number;
  taintPolicy: TaintPolicy;
}

export type PolicyDenyCode =
  | "UNKNOWN_TOOL"
  | "UNAUTHENTICATED"
  | "EMAIL_NOT_CONNECTED"
  | "FILES_NOT_CONFIGURED"
  | "MISSING_PERMISSION"
  | "CONFIRMATION_REQUIRED"
  | "CAPABILITY_DISABLED"
  | "POLICY_DENIED";

export type PolicyDecision =
  | { outcome: "allow" }
  | { outcome: "deny"; reason: string; code: PolicyDenyCode }
  | {
      outcome: "pending_confirmation";
      reason: string;
      actionType:
        | "send_email"
        | "trash_email"
        | "create_directory"
        | "rename_file"
        | "move_file"
        | "delete_file";
    };

export interface ActionProposal {
  toolName: string;
  params: unknown;
  userId: string;
  conversationId: string;
  accountId?: string;
}

export interface ActionConfirmation {
  actionId: string;
  confirmationToken: string;
  userId: string;
  payloadHash: string;
}

export interface PolicyContext {
  userId: string;
  conversationId: string;
  emailConnected?: boolean;
  /** Permissions applicatives dérivées du compte OAuth (phase 3+). */
  grantedPermissions?: PermissionScope[];
  hasConfirmation?: boolean;
  filesEnabled?: boolean;
  hasConfiguredRoots?: boolean;
}

export class PolicyDeniedError extends Error {
  readonly code: PolicyDenyCode;

  constructor(code: PolicyDenyCode, message: string) {
    super(message);
    this.name = "PolicyDeniedError";
    this.code = code;
  }
}
